#!/usr/bin/env python3
"""Hörbuchwunsch – kleiner Dienst für Ohrregal.

Nimmt Hörbuch-Wünsche entgegen (API siehe API.md), sucht sie über Prowlarr,
lädt sie mit SABnzbd, sortiert sie in die Audiobookshelf-Bibliothek ein und
meldet per ntfy, wenn sie da sind. Nur Python-Standardbibliothek.

Alle Einstellungen kommen aus Umgebungsvariablen (siehe beispiel.env).
Es wird nie etwas aus der Bibliothek gelöscht.

Aufruf:
  hoerbuch_wunsch.py dienst              HTTP-Schnittstelle + Hintergrundarbeit
  hoerbuch_wunsch.py token-neu <name>    neuen Benutzer-Token anlegen (wird einmal ausgegeben)
  hoerbuch_wunsch.py token-weg <name>    Token eines Benutzers entfernen
  hoerbuch_wunsch.py suche-test <autor> <titel> [laufzeitMin]
                                         nur suchen und bewerten, nichts laden
"""
import base64
import hashlib
import json
import os
import re
import secrets
import shutil
import sqlite3
import sys
import threading
import time
import traceback
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = "1.1.0"


def env(name, standard=None, pflicht=False):
    wert = os.environ.get(name, standard)
    if pflicht and not wert:
        sys.exit(f"Umgebungsvariable {name} fehlt")
    return wert


class Einstellungen:
    def __init__(self):
        self.bind = env("WUNSCH_BIND", "0.0.0.0")
        self.port = int(env("WUNSCH_PORT", "8097"))
        self.datenbank = env("WUNSCH_DATENBANK", "/var/lib/hoerbuch-wunsch/wunsch.sqlite")
        self.tokens = env("WUNSCH_TOKENS", "/var/lib/hoerbuch-wunsch/tokens.json")
        self.prowlarr = env("PROWLARR_URL", "http://127.0.0.1:9696").rstrip("/")
        self.prowlarr_key = env("PROWLARR_KEY", pflicht=True)
        self.kategorien = [int(k) for k in env("PROWLARR_KATEGORIEN", "3030").split(",")]
        ids = env("PROWLARR_INDEXER", "")
        self.indexer = [int(i) for i in ids.split(",") if i.strip()]
        self.sab = env("SAB_URL", "http://127.0.0.1:8080").rstrip("/")
        self.sab_key = env("SAB_KEY", pflicht=True)
        self.sab_kategorie = env("SAB_KATEGORIE", "hoerbuchwunsch")
        # So sieht der Dienst Pfade, die SABnzbd meldet: "sab-pfad=dienst-pfad"
        self.sab_pfade = [p.split("=", 1) for p in env("SAB_PFADE", "").split(";") if "=" in p]
        self.bibliothek = env("BIBLIOTHEK", pflicht=True).rstrip("/")
        self.abs_db = env("ABS_DATENBANK", "")
        # Anmeldung mit dem Audiobookshelf-Token der App (GET /api/me)
        self.abs_url = env("ABS_URL", "").rstrip("/")
        self.abs_bibliothek = env("ABS_BIBLIOTHEK_ID", "")
        # Pfad der Bibliothek, wie Audiobookshelf ihn sieht (für absItemId)
        self.abs_pfad = env("ABS_BIBLIOTHEK_PFAD", "").rstrip("/")
        self.ntfy = env("NTFY_URL", "")
        self.ntfy_token = env("NTFY_TOKEN", "")
        self.parallel = int(env("WUNSCH_PARALLEL", "2"))
        self.takt = int(env("WUNSCH_TAKT_SEKUNDEN", "60"))
        self.neuversuch_h = int(env("WUNSCH_NEUVERSUCH_STUNDEN", "24"))


E = None
DB_SPERRE = threading.Lock()
STATUS = ("gewuenscht", "nicht_gefunden", "laedt", "einsortieren", "da", "fehler")
FELDER = ("asin", "titel", "autor", "sprecher", "reihe", "teil", "laufzeitMin", "sprache", "coverUrl")


def jetzt():
    return datetime.now(timezone.utc)


def iso(t):
    return t.astimezone().isoformat(timespec="seconds") if t else None


def log(*teile):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), *teile, flush=True)


# ---------------------------------------------------------------- Datenbank

def db():
    v = sqlite3.connect(E.datenbank, timeout=30)
    v.row_factory = sqlite3.Row
    return v


def db_anlegen():
    os.makedirs(os.path.dirname(E.datenbank), exist_ok=True)
    with db() as v:
        v.executescript("""
        CREATE TABLE IF NOT EXISTS wunsch (
          id TEXT PRIMARY KEY, benutzer TEXT NOT NULL,
          asin TEXT, titel TEXT NOT NULL, autor TEXT NOT NULL, sprecher TEXT,
          reihe TEXT, teil TEXT, laufzeitMin INTEGER, sprache TEXT, coverUrl TEXT,
          status TEXT NOT NULL, hinweis TEXT, fortschritt INTEGER, absItemId TEXT,
          erstellt TEXT NOT NULL, aktualisiert TEXT NOT NULL, naechsterVersuch TEXT,
          versuche INTEGER NOT NULL DEFAULT 0,
          nzo TEXT, guid TEXT, release TEXT, ziel TEXT, fertigSeit TEXT,
          verworfen TEXT NOT NULL DEFAULT '[]', zurueckgezogen INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS interesse (
          wunsch TEXT NOT NULL, benutzer TEXT NOT NULL, PRIMARY KEY (wunsch, benutzer));
        """)


def setze(wid, **werte):
    werte["aktualisiert"] = jetzt().isoformat()
    teile = ", ".join(f"{k}=?" for k in werte)
    with DB_SPERRE, db() as v:
        v.execute(f"UPDATE wunsch SET {teile} WHERE id=?", (*werte.values(), wid))


def als_json(z):
    d = {"id": z["id"]}
    for f in FELDER:
        d[f] = z[f]
    d["status"] = z["status"]
    if z["hinweis"]:
        d["hinweis"] = z["hinweis"]
    if z["status"] == "laedt" and z["fortschritt"] is not None:
        d["fortschritt"] = z["fortschritt"]
    if z["status"] == "da" and z["absItemId"]:
        d["absItemId"] = z["absItemId"]
    d["erstellt"] = iso(datetime.fromisoformat(z["erstellt"]))
    d["aktualisiert"] = iso(datetime.fromisoformat(z["aktualisiert"]))
    if z["status"] == "nicht_gefunden" and z["naechsterVersuch"]:
        d["naechsterVersuch"] = iso(datetime.fromisoformat(z["naechsterVersuch"]))
    d["versuche"] = z["versuche"]
    return d


# ---------------------------------------------------------------- Tokens

def tokens_lesen():
    try:
        with open(E.tokens) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def tokens_schreiben(t):
    os.makedirs(os.path.dirname(E.tokens), exist_ok=True)
    tmp = E.tokens + ".neu"
    with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
        json.dump(t, f, indent=1)
    os.replace(tmp, E.tokens)


def hash_token(t):
    return hashlib.sha256(t.encode()).hexdigest()


ABS_CACHE = {}
ABS_CACHE_SPERRE = threading.Lock()
ABS_CACHE_SEKUNDEN = 300


def abs_benutzer(token):
    """Prüft ein Audiobookshelf-Token über /api/me; Ergebnis 5 Minuten zwischengespeichert."""
    if not E.abs_url:
        return None
    h = hash_token(token)
    with ABS_CACHE_SPERRE:
        z = ABS_CACHE.get(h)
        if z and z[1] > time.time():
            return z[0]
    try:
        me = json.loads(hole(E.abs_url + "/api/me", kopf={"Authorization": "Bearer " + token}, zeit=10))
    except urllib.error.HTTPError:
        return None  # 401/403: Token ungültig oder abgelaufen
    except Exception as f:
        log("Audiobookshelf nicht erreichbar:", f)
        return None
    if not me.get("id") or me.get("isActive") is False or me.get("isLocked"):
        return None
    if E.abs_bibliothek:
        rechte = me.get("permissions") or {}
        if not rechte.get("accessAllLibraries") and \
                E.abs_bibliothek not in (me.get("librariesAccessible") or []):
            return None
    name = "abs:" + me["id"]
    with ABS_CACHE_SPERRE:
        if len(ABS_CACHE) > 1000:
            ABS_CACHE.clear()
        ABS_CACHE[h] = (name, time.time() + ABS_CACHE_SEKUNDEN)
    return name


def benutzer_zu_token(token):
    if not token:
        return None
    h = hash_token(token)
    for name, gespeichert in tokens_lesen().items():
        if secrets.compare_digest(gespeichert, h):
            return name
    return abs_benutzer(token)


# ---------------------------------------------------------------- HTTP-Helfer

def hole(url, daten=None, kopf=None, zeit=60, methode=None):
    anf = urllib.request.Request(url, data=daten, headers=kopf or {}, method=methode)
    with urllib.request.urlopen(anf, timeout=zeit) as a:
        return a.read()


def prowlarr(pfad, **param):
    teile = []
    for k, v in param.items():
        for x in (v if isinstance(v, list) else [v]):
            teile.append((k, x))
    url = f"{E.prowlarr}/api/v1/{pfad}?" + urllib.parse.urlencode(teile)
    return json.loads(hole(url, kopf={"X-Api-Key": E.prowlarr_key}, zeit=120))


def sab(modus, **param):
    param.update(mode=modus, apikey=E.sab_key, output="json")
    return json.loads(hole(f"{E.sab}/api?" + urllib.parse.urlencode(param)))


def sab_pfad(p):
    for sab_p, dienst_p in E.sab_pfade:
        if p.startswith(sab_p):
            return dienst_p + p[len(sab_p):]
    return p


def push(titel, text, wunsch_id=None):
    if not E.ntfy:
        return
    kopf = {"Title": "=?UTF-8?B?" + base64.b64encode(titel.encode()).decode() + "?=",
            "Tags": "headphones"}
    if E.ntfy_token:
        kopf["Authorization"] = "Bearer " + E.ntfy_token
    try:
        hole(E.ntfy, text.encode(), kopf, zeit=15)
    except Exception as f:
        log("ntfy fehlgeschlagen:", f)


# ---------------------------------------------------------------- Audiobookshelf (nur lesend)

def abs_db():
    if not E.abs_db:
        return None
    try:
        return sqlite3.connect(f"file:{E.abs_db}?mode=ro", uri=True, timeout=10)
    except sqlite3.Error as f:
        log("ABS-Datenbank nicht lesbar:", f)
        return None


def abs_vorhanden(asin, titel, autor):
    """absItemId, falls das Buch schon in der Bibliothek ist."""
    v = abs_db()
    if not v:
        return None
    try:
        if asin:
            z = v.execute("SELECT li.id FROM books b JOIN libraryItems li ON li.mediaId=b.id "
                          "WHERE upper(b.asin)=upper(?) AND li.isMissing=0 LIMIT 1", (asin,)).fetchone()
            if z:
                return z[0]
        nt, na = norm(titel), nachname(autor)
        for lid, t, a in v.execute("SELECT id, title, authorNamesFirstLast FROM libraryItems "
                                   "WHERE mediaType='book' AND isMissing=0"):
            if norm(t or "") == nt and na and na in norm(a or ""):
                return lid
    except sqlite3.Error as f:
        log("ABS-Abfrage fehlgeschlagen:", f)
    finally:
        v.close()
    return None


def abs_item_zu_pfad(pfad):
    v = abs_db()
    if not v or not E.abs_pfad:
        return None
    rel = os.path.relpath(pfad, E.bibliothek)
    try:
        z = v.execute("SELECT id FROM libraryItems WHERE path=? AND isMissing=0",
                      (E.abs_pfad + "/" + rel,)).fetchone()
        return z[0] if z else None
    except sqlite3.Error:
        return None
    finally:
        v.close()


# ---------------------------------------------------------------- Bewertung

UMLAUTE = str.maketrans({"ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss", "Ä": "ae", "Ö": "oe", "Ü": "ue"})
FUELLWOERTER = {"der", "die", "das", "und", "ein", "eine", "the", "a", "of", "von", "im", "in", "zu", "an"}


def norm(s):
    s = (s or "").translate(UMLAUTE)
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    return " ".join(re.sub(r"[^a-z0-9]+", " ", s).split())


def kurztitel(titel):
    """Haupttitel ohne Untertitel, z. B. 'Name: Roman' -> 'Name'."""
    t = re.split(r"\s*[:–—(\[]\s*|\s+-\s+", titel or "")[0]
    return t.strip() or titel


def nachname(autor):
    erster = re.split(r"[,;&]| und ", autor or "")[0].strip()
    teile = norm(erster).split()
    return teile[-1] if teile else ""


def woerter(s):
    return [w for w in norm(s).split() if w not in FUELLWOERTER] or norm(s).split()


def bewerte(r, w):
    """Gibt (punkte, hinweis) zurück; punkte None = passt nicht."""
    name = norm(r.get("title", ""))
    nw = set(name.split())
    tw = woerter(kurztitel(w["titel"]))
    if not tw or not all(x in nw for x in tw):
        return None, "Titel passt nicht"
    na = nachname(w["autor"])
    autor_da = na and na in nw
    punkte = 50 if autor_da else 0
    hinweis = []
    if not autor_da:
        # ohne Autor nur, wenn Titel lang genug und eindeutig ist
        if len(tw) < 3:
            return None, "Autor fehlt im Namen"
        punkte -= 15
    wunsch_text = norm(" ".join(str(w[k] or "") for k in ("titel", "reihe")))
    if re.search(r"\bungekuerzt\b|\bunabridged\b", name):
        punkte += 30
    elif re.search(r"\bgekuerzt\b|\babridged\b", name):
        punkte -= 25
        hinweis.append("gekürzte Fassung")
    for verbot in ("hoerspiel", "kids", "kinder", "lesung", "leseprobe", "sample", "radio"):
        if verbot in nw and verbot not in wunsch_text:
            return None, f"{verbot} passt nicht zum Wunsch"
    sprache = (w["sprache"] or "").lower()[:2]
    if sprache == "de":
        if nw & {"german", "deutsch", "de", "ger"}:
            punkte += 10
        if nw & {"english", "englisch", "en", "eng"} and not nw & {"german", "deutsch", "de", "ger"}:
            return None, "englische Fassung"
    elif sprache == "en":
        if nw & {"german", "deutsch", "de", "ger", "ungekuerzt", "gekuerzt"}:
            return None, "deutsche Fassung"
    teil = str(w["teil"] or "").strip()
    if teil:
        zahlen = re.findall(r"\b0*(\d{1,3})\b", name)
        if teil.lstrip("0") in zahlen:
            punkte += 10
    if re.search(r"\b\d{1,2} ?(bis|-) ?\d{1,2}\b|\b(box|sammlung|collection|komplett|gesamtausgabe)\b", name):
        punkte -= 20
        hinweis.append("Sammelpaket")
    groesse_mb = (r.get("size") or 0) / 1e6
    if w["laufzeitMin"]:
        mb_min = groesse_mb / max(1, int(w["laufzeitMin"]))
        if mb_min < 0.2 or mb_min > 3.0:
            if "Sammelpaket" not in hinweis:
                return None, f"Größe passt nicht zur Laufzeit ({groesse_mb:.0f} MB)"
        else:
            punkte += 10
    elif groesse_mb < 20:
        return None, "zu klein"
    if re.search(r"\bm4b\b", name):
        punkte += 3
    punkte += min(5, (r.get("grabs") or 0) // 10)
    punkte -= min(5, (r.get("age") or 0) // 1000)
    return punkte, ", ".join(hinweis)


def indexer_ids():
    if E.indexer:
        return E.indexer
    ids = []
    for i in prowlarr("indexer"):
        if not i.get("enable") or i.get("protocol") != "usenet":
            continue
        kats = set()
        for k in i.get("capabilities", {}).get("categories", []):
            kats.add(k["id"])
            kats.update(s["id"] for s in k.get("subCategories", []))
        if kats & set(E.kategorien) or 3000 in kats:
            ids.append(i["id"])
    return ids


def suche(w):
    """Alle passenden Treffer, beste zuerst."""
    titel_k = kurztitel(w["titel"])
    anfragen = [f"{nachname(w['autor'])} {titel_k}", titel_k]
    if w["reihe"] and w["teil"]:
        anfragen.append(f"{w['reihe']} {w['teil']}")
    ids = indexer_ids()
    gesehen, treffer, gruende = set(), [], {}
    for q in dict.fromkeys(a.strip() for a in anfragen if a.strip()):
        try:
            erg = prowlarr("search", query=q, type="search", categories=E.kategorien, indexerIds=ids)
        except Exception as f:
            log("Prowlarr-Suche fehlgeschlagen:", f)
            continue
        if not isinstance(erg, list):
            continue
        for r in erg:
            if r.get("protocol") != "usenet" or r.get("guid") in gesehen:
                continue
            gesehen.add(r.get("guid"))
            p, h = bewerte(r, w)
            if p is None:
                gruende[h] = gruende.get(h, 0) + 1
            else:
                treffer.append((p, h, r))
        time.sleep(2)
    treffer.sort(key=lambda x: -x[0])
    return treffer, gruende, len(gesehen)


# ---------------------------------------------------------------- Ablauf

def dateiname(s):
    s = re.sub(r'[\\/:*?"<>|]+', " ", s or "").strip(" .")
    return re.sub(r"\s+", " ", s)[:120] or "Unbekannt"


def zielordner(w):
    autor = dateiname(re.split(r"[;,]| & ", w["autor"])[0])
    teile = [E.bibliothek, autor]
    titel = dateiname(w["titel"])
    if w["reihe"]:
        teile.append(dateiname(w["reihe"]))
        if w["teil"]:
            titel = f"{dateiname(str(w['teil']))} - {titel}"
    teile.append(titel)
    return os.path.join(*teile)


def nzb_laden(w, treffer):
    r = treffer[2]
    nzb = hole(r["downloadUrl"], zeit=120)
    if b"<nzb" not in nzb[:2000]:
        raise RuntimeError("Indexer lieferte keine NZB-Datei")
    grenze = uuid.uuid4().hex
    name = dateiname(f"{w['autor']} - {w['titel']}") + ".nzb"
    koerper = (f"--{grenze}\r\nContent-Disposition: form-data; name=\"name\"; filename=\"{name}\"\r\n"
               f"Content-Type: application/x-nzb\r\n\r\n").encode() + nzb + f"\r\n--{grenze}--\r\n".encode()
    param = urllib.parse.urlencode(dict(mode="addfile", apikey=E.sab_key, output="json",
                                        cat=E.sab_kategorie, nzbname=name[:-4]))
    antwort = json.loads(hole(f"{E.sab}/api?{param}", koerper,
                              {"Content-Type": f"multipart/form-data; boundary={grenze}"}))
    ids = antwort.get("nzo_ids") or []
    if not antwort.get("status") or not ids:
        raise RuntimeError(f"SABnzbd nahm die NZB nicht an: {antwort}")
    return ids[0]


def bearbeite_suche(w):
    wid = w["id"]
    vorhanden = abs_vorhanden(w["asin"], w["titel"], w["autor"])
    if vorhanden:
        setze(wid, status="da", absItemId=vorhanden, hinweis="war schon in der Bibliothek")
        return
    treffer, gruende, anzahl = suche(w)
    verworfen = set(json.loads(w["verworfen"]))
    treffer = [t for t in treffer if t[2].get("guid") not in verworfen]
    versuche = w["versuche"] + 1
    if not treffer:
        if anzahl == 0:
            grund = "Keine Treffer bei den Indexern"
        else:
            haeufig = sorted(gruende.items(), key=lambda x: -x[1])[:2]
            grund = f"{anzahl} Treffer, keiner passt (" + "; ".join(f"{g}: {n}" for g, n in haeufig) + ")"
        setze(wid, status="nicht_gefunden", hinweis=grund, versuche=versuche,
              naechsterVersuch=(jetzt() + timedelta(hours=E.neuversuch_h)).isoformat())
        log(f"{wid}: nicht gefunden – {grund}")
        return
    bester = treffer[0]
    try:
        nzo = nzb_laden(w, bester)
    except Exception as f:
        verworfen.add(bester[2].get("guid"))
        setze(wid, status="fehler", hinweis=f"Download ließ sich nicht starten: {f}"[:300],
              versuche=versuche, verworfen=json.dumps(sorted(verworfen)),
              naechsterVersuch=(jetzt() + timedelta(hours=1)).isoformat())
        log(f"{wid}: Fehler beim Starten:", f)
        return
    setze(wid, status="laedt", nzo=nzo, guid=bester[2].get("guid"), release=bester[2].get("title"), fortschritt=0,
          hinweis=bester[1] or None, versuche=versuche, naechsterVersuch=None)
    log(f"{wid}: lädt ({bester[0]} Punkte)")


def sab_stand():
    queue = {s["nzo_id"]: s for s in sab("queue", limit=500)["queue"]["slots"]}
    hist = {s["nzo_id"]: s for s in sab("history", limit=200, category=E.sab_kategorie)["history"]["slots"]}
    return queue, hist


def bearbeite_download(w, queue, hist):
    wid, nzo = w["id"], w["nzo"]
    if nzo in queue:
        try:
            p = int(float(queue[nzo].get("percentage", 0)))
        except ValueError:
            p = 0
        if p != w["fortschritt"]:
            setze(wid, fortschritt=p)
        return
    h = hist.get(nzo)
    if not h:
        return  # gerade zwischen Warteschlange und Verlauf (Entpacken)
    if h.get("status") == "Completed":
        setze(wid, status="einsortieren", ziel=sab_pfad(h.get("storage", "")), fortschritt=100)
        return
    if h.get("status") == "Failed":
        verworfen = set(json.loads(w["verworfen"]))
        verworfen.add(w["guid"])
        setze(wid, status="fehler", hinweis=f"Download fehlgeschlagen: {h.get('fail_message', '')}"[:300],
              verworfen=json.dumps(sorted(x for x in verworfen if x)), nzo=None,
              naechsterVersuch=jetzt().isoformat())
        log(f"{wid}: Download fehlgeschlagen")


AUDIO = {".mp3", ".m4b", ".m4a", ".flac", ".ogg", ".opus", ".aac", ".wma", ".wav"}
BEILAGEN = {".jpg", ".jpeg", ".png", ".webp", ".pdf", ".epub", ".cue"}


def einsortieren(w):
    wid, quelle = w["id"], w["ziel"]
    if w["fertigSeit"]:
        return pruefe_abs(w)
    if not quelle or not os.path.isdir(quelle):
        setze(wid, status="fehler", hinweis="Fertiger Download nicht gefunden", nzo=None,
              naechsterVersuch=jetzt().isoformat())
        return
    dateien = []
    for wurzel, _, namen in os.walk(quelle):
        for n in namen:
            endung = os.path.splitext(n)[1].lower()
            if endung in AUDIO or endung in BEILAGEN:
                if "sample" not in norm(n).split():
                    dateien.append(os.path.join(wurzel, n))
    if not any(os.path.splitext(d)[1].lower() in AUDIO for d in dateien):
        setze(wid, status="fehler", hinweis="Im Download sind keine Audiodateien", nzo=None,
              naechsterVersuch=jetzt().isoformat())
        return
    ziel = zielordner(w)
    basis, n = ziel, 2
    while os.path.exists(ziel):
        ziel, n = f"{basis} ({n})", n + 1
    # Erst in einem versteckten Arbeitsordner auf derselben Platte zusammenbauen,
    # dann mit einem Schritt an den Zielort: Audiobookshelf sieht nie halbe Bücher.
    arbeit = os.path.join(E.bibliothek, ".hoerbuch-wunsch-arbeit", wid)
    os.makedirs(arbeit, exist_ok=True)
    open(os.path.join(E.bibliothek, ".hoerbuch-wunsch-arbeit", ".ignore"), "a").close()
    mehrere_ordner = len({os.path.dirname(d) for d in dateien if os.path.splitext(d)[1].lower() in AUDIO}) > 1
    for d in sorted(dateien):
        rel = os.path.relpath(d, quelle) if mehrere_ordner else os.path.basename(d)
        z = os.path.join(arbeit, rel)
        os.makedirs(os.path.dirname(z), exist_ok=True)
        shutil.move(d, z)
    metadaten_schreiben(w, arbeit)
    os.makedirs(os.path.dirname(ziel), mode=0o2775, exist_ok=True)
    os.rename(arbeit, ziel)
    # Rest des Downloads (nfo, par2 …) liegt im Download-Ordner, nicht in der Bibliothek
    shutil.rmtree(quelle, ignore_errors=True)
    setze(wid, ziel=ziel, fertigSeit=jetzt().isoformat())
    log(f"{wid}: einsortiert")


def metadaten_schreiben(w, ordner):
    serie = []
    if w["reihe"]:
        serie = [f"{w['reihe']} #{w['teil']}" if w["teil"] else w["reihe"]]
    meta = {
        "tags": [], "chapters": [],
        "title": w["titel"], "subtitle": None,
        "authors": [a.strip() for a in re.split(r"[;,]| & ", w["autor"]) if a.strip()],
        "narrators": [a.strip() for a in re.split(r"[;,]| & ", w["sprecher"] or "") if a.strip()],
        "series": serie, "genres": [], "publishedYear": None, "publishedDate": None,
        "publisher": None, "description": None, "isbn": None,
        "asin": w["asin"] or None, "language": w["sprache"] or None,
        "explicit": False, "abridged": "gekürzte Fassung" in (w["hinweis"] or ""),
    }
    with open(os.path.join(ordner, "metadata.json"), "w") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    hat_cover = any(n.lower().startswith("cover.") for n in os.listdir(ordner))
    if w["coverUrl"] and not hat_cover and w["coverUrl"].startswith("https://"):
        try:
            bild = hole(w["coverUrl"], zeit=30)
            if len(bild) < 20_000_000:
                with open(os.path.join(ordner, "cover.jpg"), "wb") as f:
                    f.write(bild)
        except Exception as f:
            log(f"{w['id']}: Cover nicht geladen:", f)


def pruefe_abs(w):
    """Wartet, bis Audiobookshelf das Buch eingelesen hat."""
    lid = abs_item_zu_pfad(w["ziel"])
    seit = datetime.fromisoformat(w["fertigSeit"])
    if lid or jetzt() - seit > timedelta(hours=2) or not E.abs_db:
        hinweis = None if lid else "Liegt in der Bibliothek, Audiobookshelf hat es noch nicht eingelesen"
        setze(w["id"], status="da", absItemId=lid, hinweis=hinweis, nzo=None)
        push("Hörbuch ist da", f"{w['titel']} – {w['autor']}", w["id"])
        log(f"{w['id']}: da")


def arbeite_einmal():
    with db() as v:
        laufend = v.execute("SELECT * FROM wunsch WHERE status IN ('laedt','einsortieren') "
                            "AND zurueckgezogen=0").fetchall()
    if any(w["status"] == "laedt" for w in laufend):
        queue, hist = sab_stand()
        for w in laufend:
            if w["status"] == "laedt":
                bearbeite_download(w, queue, hist)
    for w in laufend:
        if w["status"] == "einsortieren":
            try:
                einsortieren(w)
            except Exception as f:
                setze(w["id"], hinweis=f"Einsortieren fehlgeschlagen: {f}"[:300])
                log(f"{w['id']}: Einsortieren fehlgeschlagen:", traceback.format_exc())
    with db() as v:
        aktiv = v.execute("SELECT count(*) FROM wunsch WHERE status IN ('laedt','einsortieren') "
                          "AND zurueckgezogen=0").fetchone()[0]
        frei = max(0, E.parallel - aktiv)
        offen = v.execute("SELECT * FROM wunsch WHERE zurueckgezogen=0 AND (status='gewuenscht' OR "
                          "(status IN ('nicht_gefunden','fehler') AND naechsterVersuch<=?)) "
                          "ORDER BY erstellt LIMIT ?", (jetzt().isoformat(), frei)).fetchall()
    for w in offen:  # gedrosselt: höchstens WUNSCH_PARALLEL gleichzeitig
        try:
            bearbeite_suche(w)
        except Exception as f:
            setze(w["id"], status="fehler", hinweis=f"Suche fehlgeschlagen: {f}"[:300],
                  naechsterVersuch=(jetzt() + timedelta(hours=1)).isoformat())
            log(f"{w['id']}: Suche fehlgeschlagen:", traceback.format_exc())


WECKER = threading.Event()


def arbeiter():
    while True:
        try:
            arbeite_einmal()
        except Exception:
            log("Arbeitslauf fehlgeschlagen:", traceback.format_exc())
        WECKER.wait(E.takt)
        WECKER.clear()


# ---------------------------------------------------------------- HTTP-Schnittstelle

class Schnittstelle(BaseHTTPRequestHandler):
    server_version = "Hoerbuchwunsch/" + VERSION
    sys_version = ""

    def log_message(self, fmt, *args):
        pass

    def antworte(self, code, daten=None):
        koerper = b"" if daten is None else json.dumps(daten, ensure_ascii=False).encode()
        self.send_response(code)
        if daten is not None:
            self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(koerper)))
        self.end_headers()
        self.wfile.write(koerper)

    def fehler(self, code, schluessel, text, **extra):
        self.antworte(code, {"fehler": schluessel, "text": text, **extra})

    def benutzer(self):
        kopf = self.headers.get("Authorization", "")
        name = benutzer_zu_token(kopf[7:].strip()) if kopf.startswith("Bearer ") else None
        if not name:
            self.fehler(401, "nicht_angemeldet", "Token fehlt oder ist ungültig")
        return name

    def koerper(self):
        laenge = int(self.headers.get("Content-Length") or 0)
        if laenge > 100_000:
            raise ValueError("zu groß")
        roh = self.rfile.read(laenge) if laenge else b"{}"
        d = json.loads(roh or b"{}")
        if not isinstance(d, dict):
            raise ValueError("kein Objekt")
        return d

    def pfad(self):
        u = urllib.parse.urlsplit(self.path)
        return [t for t in u.path.split("/") if t], urllib.parse.parse_qs(u.query)

    def do_GET(self):
        teile, abfrage = self.pfad()
        if teile == ["status"]:
            return self.antworte(200, {"ok": True, "version": VERSION})
        if teile[:1] == ["reihe"]:
            if not self.benutzer():
                return
            return self.fehler(501, "noch_nicht", "Reihen folgen kommt in Version 2")
        if teile[:1] != ["wunsch"] or len(teile) > 2:
            return self.fehler(404, "unbekannt", "Diesen Pfad gibt es nicht")
        name = self.benutzer()
        if not name:
            return
        with db() as v:
            if len(teile) == 2:
                z = sichtbarer_wunsch(v, teile[1], name)
                if not z:
                    return self.fehler(404, "unbekannt", "Diesen Wunsch gibt es nicht")
                return self.antworte(200, als_json(z))
            sql = ("SELECT w.* FROM wunsch w WHERE w.zurueckgezogen=0 AND "
                   "(w.benutzer=? OR EXISTS (SELECT 1 FROM interesse i WHERE i.wunsch=w.id AND i.benutzer=?))")
            werte = [name, name]
            status = [s for s in ",".join(abfrage.get("status", [])).split(",") if s in STATUS]
            if status:
                sql += " AND w.status IN (%s)" % ",".join("?" * len(status))
                werte += status
            zeilen = v.execute(sql + " ORDER BY w.erstellt DESC", werte).fetchall()
        self.antworte(200, {"wuensche": [als_json(z) for z in zeilen]})

    def do_POST(self):
        teile, _ = self.pfad()
        name = self.benutzer()
        if not name:
            return
        if teile[:1] == ["reihe"]:
            return self.fehler(501, "noch_nicht", "Reihen folgen kommt in Version 2")
        if len(teile) == 3 and teile[0] == "wunsch" and teile[2] == "erneut":
            with db() as v:
                z = sichtbarer_wunsch(v, teile[1], name)
            if not z:
                return self.fehler(404, "unbekannt", "Diesen Wunsch gibt es nicht")
            if z["status"] not in ("nicht_gefunden", "fehler"):
                return self.fehler(409, "laeuft_schon", "Der Wunsch wird gerade bearbeitet oder ist fertig")
            setze(z["id"], status="gewuenscht", hinweis=None, naechsterVersuch=None)
            WECKER.set()
            return self.antworte(202, {"id": z["id"], "status": "gewuenscht"})
        if teile != ["wunsch"]:
            return self.fehler(404, "unbekannt", "Diesen Pfad gibt es nicht")
        try:
            d = self.koerper()
        except (ValueError, json.JSONDecodeError):
            return self.fehler(400, "ungueltig", "Kein gültiges JSON-Objekt")
        w = {f: d.get(f) for f in FELDER}
        for f in ("asin", "titel", "autor", "sprecher", "reihe", "teil", "sprache", "coverUrl"):
            if w[f] is not None:
                w[f] = str(w[f]).strip()[:500] or None
        try:
            w["laufzeitMin"] = int(w["laufzeitMin"]) if w["laufzeitMin"] not in (None, "") else None
        except (TypeError, ValueError):
            return self.fehler(400, "ungueltig", "laufzeitMin muss eine Zahl sein")
        if not w["titel"] or not w["autor"]:
            return self.fehler(400, "ungueltig", "titel und autor sind Pflicht")
        with DB_SPERRE, db() as v:
            if w["asin"]:
                z = v.execute("SELECT * FROM wunsch WHERE upper(asin)=upper(?) AND zurueckgezogen=0 "
                              "ORDER BY erstellt DESC LIMIT 1", (w["asin"],)).fetchone()
                if z and z["status"] != "da":
                    if z["benutzer"] != name:
                        v.execute("INSERT OR IGNORE INTO interesse VALUES (?,?)", (z["id"], name))
                    return self.antworte(200, als_json(z))
        vorhanden = abs_vorhanden(w["asin"], w["titel"], w["autor"])
        if vorhanden:
            return self.fehler(409, "schon_vorhanden", "Das Hörbuch ist schon in der Bibliothek",
                               absItemId=vorhanden)
        wid = "w_" + secrets.token_hex(4)
        t = jetzt().isoformat()
        with DB_SPERRE, db() as v:
            v.execute("INSERT INTO wunsch (id, benutzer, asin, titel, autor, sprecher, reihe, teil, "
                      "laufzeitMin, sprache, coverUrl, status, erstellt, aktualisiert) "
                      "VALUES (?,?,?,?,?,?,?,?,?,?,?,'gewuenscht',?,?)",
                      (wid, name, *(w[f] for f in FELDER), t, t))
            z = v.execute("SELECT * FROM wunsch WHERE id=?", (wid,)).fetchone()
        log(f"{wid}: neuer Wunsch von {name}")
        WECKER.set()
        self.antworte(201, als_json(z))

    def do_DELETE(self):
        teile, _ = self.pfad()
        name = self.benutzer()
        if not name:
            return
        if teile[:1] == ["reihe"]:
            return self.fehler(501, "noch_nicht", "Reihen folgen kommt in Version 2")
        if len(teile) != 2 or teile[0] != "wunsch":
            return self.fehler(404, "unbekannt", "Diesen Pfad gibt es nicht")
        with DB_SPERRE, db() as v:
            z = sichtbarer_wunsch(v, teile[1], name)
            if not z:
                return self.fehler(404, "unbekannt", "Diesen Wunsch gibt es nicht")
            v.execute("DELETE FROM interesse WHERE wunsch=? AND benutzer=?", (z["id"], name))
            andere = v.execute("SELECT benutzer FROM interesse WHERE wunsch=?", (z["id"],)).fetchall()
            if z["benutzer"] == name and andere:
                # Wunsch geht an den nächsten Interessenten über
                v.execute("UPDATE wunsch SET benutzer=? WHERE id=?", (andere[0][0], z["id"]))
                v.execute("DELETE FROM interesse WHERE wunsch=? AND benutzer=?", (z["id"], andere[0][0]))
                return self.antworte(204)
            if z["benutzer"] != name:
                return self.antworte(204)
            v.execute("UPDATE wunsch SET zurueckgezogen=1, aktualisiert=? WHERE id=?",
                      (jetzt().isoformat(), z["id"]))
        if z["status"] == "laedt" and z["nzo"]:
            try:  # nur den Download abbrechen; fertige Bücher bleiben immer liegen
                sab("queue", name="delete", value=z["nzo"], del_files=1)
            except Exception as f:
                log(f"{z['id']}: Abbruch in SABnzbd fehlgeschlagen:", f)
        log(f"{z['id']}: zurückgezogen von {name}")
        self.antworte(204)


def sichtbarer_wunsch(v, wid, name):
    return v.execute("SELECT w.* FROM wunsch w WHERE w.id=? AND w.zurueckgezogen=0 AND (w.benutzer=? OR "
                     "EXISTS (SELECT 1 FROM interesse i WHERE i.wunsch=w.id AND i.benutzer=?))",
                     (wid, name, name)).fetchone()


# ---------------------------------------------------------------- Start

def main():
    global E
    befehl = sys.argv[1] if len(sys.argv) > 1 else ""
    if befehl in ("token-neu", "token-weg") and len(sys.argv) == 3:
        E = type("E", (), {"tokens": env("WUNSCH_TOKENS", "/var/lib/hoerbuch-wunsch/tokens.json")})()
        t = tokens_lesen()
        if befehl == "token-weg":
            t.pop(sys.argv[2], None)
            tokens_schreiben(t)
            return print("entfernt")
        neu = secrets.token_urlsafe(32)
        t[sys.argv[2]] = hash_token(neu)
        tokens_schreiben(t)
        return print(neu)
    E = Einstellungen()
    if befehl == "suche-test" and len(sys.argv) >= 4:
        w = {"titel": sys.argv[3], "autor": sys.argv[2], "reihe": None, "teil": None, "sprache": "de",
             "laufzeitMin": int(sys.argv[4]) if len(sys.argv) > 4 else None}
        treffer, gruende, anzahl = suche(w)
        print(f"{anzahl} Treffer, {len(treffer)} passend")
        for p, h, r in treffer[:10]:
            print(f"{p:4d}  {r.get('size', 0) / 1e6:7.0f} MB  {r.get('title')}  {h}")
        print("verworfen:", gruende)
        return
    if befehl != "dienst":
        sys.exit(__doc__)
    os.umask(0o002)
    db_anlegen()
    threading.Thread(target=arbeiter, daemon=True).start()
    server = ThreadingHTTPServer((E.bind, E.port), Schnittstelle)
    log(f"Hörbuchwunsch {VERSION} hört auf {E.bind}:{E.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
