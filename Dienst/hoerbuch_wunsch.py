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
import subprocess
import tempfile
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

VERSION = "2.4.1"


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
        # Push direkt in die App über Apple (APNs, Token-Auth mit .p8-Schlüssel)
        self.apns_schluessel = env("APNS_SCHLUESSEL", "")
        self.apns_key_id = env("APNS_KEY_ID", "")
        self.apns_team_id = env("APNS_TEAM_ID", "")
        self.apns_topic = env("APNS_TOPIC", "")
        self.audible = env("AUDIBLE_API", "https://api.audible.de").rstrip("/")
        # Ruhezeiten: Vorrechnen und Nebenarbeiten nur nachts und wenn niemand streamt
        self.jellyfin = env("JELLYFIN_URL", "").rstrip("/")
        self.jellyfin_key = env("JELLYFIN_KEY", "")
        self.nacht_von = int(env("NACHT_VON", "3"))
        self.nacht_bis = int(env("NACHT_BIS", "6"))
        self.zeitzone = env("ZEITZONE", "Europe/Berlin")
        self.lidarr = env("LIDARR_URL", "").rstrip("/")
        self.lidarr_key = env("LIDARR_KEY", "")
        self.lidarr_ordner = env("LIDARR_ORDNER", "")
        self.lidarr_qualitaet = int(env("LIDARR_QUALITAETSPROFIL", "1"))
        self.lidarr_metadaten = int(env("LIDARR_METADATENPROFIL", "1"))
        self.navidrome = env("NAVIDROME_URL", "").rstrip("/")
        self.vorrat = env("WUNSCH_VORRAT", os.path.join(os.path.dirname(self.datenbank), "vorrat.json"))
        self.parallel = int(env("WUNSCH_PARALLEL", "2"))
        self.takt = int(env("WUNSCH_TAKT_SEKUNDEN", "60"))
        self.neuversuch_h = int(env("WUNSCH_NEUVERSUCH_STUNDEN", "24"))
        # Reverse-Proxys, deren X-Forwarded-For/X-Real-IP geglaubt wird (für die Fehlversuchssperre)
        self.proxys = {p.strip() for p in env("WUNSCH_PROXYS", "").split(",") if p.strip()}


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
        CREATE TABLE IF NOT EXISTS geraet (
          token TEXT NOT NULL, benutzer TEXT NOT NULL, umgebung TEXT NOT NULL,
          erstellt TEXT NOT NULL, aktualisiert TEXT NOT NULL, PRIMARY KEY (token, benutzer));
        CREATE TABLE IF NOT EXISTS interesse (
          wunsch TEXT NOT NULL, benutzer TEXT NOT NULL, PRIMARY KEY (wunsch, benutzer));
        CREATE TABLE IF NOT EXISTS reihe (
          id TEXT PRIMARY KEY, benutzer TEXT NOT NULL, reiheAsin TEXT NOT NULL,
          reihe TEXT NOT NULL, autor TEXT, sprache TEXT, erstellt TEXT NOT NULL,
          geprueft TEXT, hinweis TEXT, zurueckgezogen INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS musik_wunsch (
          id TEXT PRIMARY KEY, benutzer TEXT NOT NULL, mbid TEXT NOT NULL, kuenstlerMbid TEXT,
          titel TEXT, kuenstler TEXT, cover TEXT, status TEXT NOT NULL, hinweis TEXT,
          lidarrId INTEGER, gesucht TEXT, erstellt TEXT NOT NULL, aktualisiert TEXT NOT NULL,
          zurueckgezogen INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS reihe_teil (
          reihe TEXT NOT NULL, asin TEXT NOT NULL, teil TEXT, titel TEXT,
          inAbs INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (reihe, asin));
        """)
        spalten = {z[1] for z in v.execute("PRAGMA table_info(wunsch)")}
        if "ausReihe" not in spalten:
            v.execute("ALTER TABLE wunsch ADD COLUMN ausReihe TEXT")
        # Ein Gerät kann zu mehreren Anmeldungen gehören (ABS und Navidrome)
        pk = [z[1] for z in v.execute("PRAGMA table_info(geraet)") if z[5]]
        if pk == ["token"]:
            v.executescript("""
            ALTER TABLE geraet RENAME TO geraet_alt;
            CREATE TABLE geraet (
              token TEXT NOT NULL, benutzer TEXT NOT NULL, umgebung TEXT NOT NULL,
              erstellt TEXT NOT NULL, aktualisiert TEXT NOT NULL, PRIMARY KEY (token, benutzer));
            INSERT INTO geraet SELECT token, benutzer, umgebung, erstellt, aktualisiert FROM geraet_alt;
            DROP TABLE geraet_alt;
            """)
        if "hoerspiel" not in spalten:
            v.execute("ALTER TABLE wunsch ADD COLUMN hoerspiel INTEGER")


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
        d["hinweis"] = bereinigt(z["hinweis"])
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


APNS_HOST = {"produktion": "https://api.push.apple.com", "sandbox": "https://api.sandbox.push.apple.com"}
APNS_JWT = {"wert": None, "zeit": 0}


def b64url(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def der_zu_roh(der):
    """ECDSA-Signatur von DER (openssl) in r||s (JWT ES256) umwandeln."""
    def lies(i):
        assert der[i] == 0x02
        n = der[i + 1]
        return der[i + 2:i + 2 + n], i + 2 + n
    i = 2 if der[1] < 0x80 else 3
    r, i = lies(i)
    s_, _ = lies(i)
    return r.lstrip(b"\0").rjust(32, b"\0") + s_.lstrip(b"\0").rjust(32, b"\0")


def apns_jwt():
    if APNS_JWT["wert"] and time.time() - APNS_JWT["zeit"] < 40 * 60:
        return APNS_JWT["wert"]
    kopf = b64url(json.dumps({"alg": "ES256", "kid": E.apns_key_id}).encode())
    inhalt = b64url(json.dumps({"iss": E.apns_team_id, "iat": int(time.time())}).encode())
    signiert = f"{kopf}.{inhalt}".encode()
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", E.apns_schluessel],
                         input=signiert, capture_output=True, check=True).stdout
    APNS_JWT.update(wert=f"{kopf}.{inhalt}.{b64url(der_zu_roh(der))}", zeit=time.time())
    return APNS_JWT["wert"]


def apns_senden(geraet, umgebung, nutzlast):
    """Gibt (HTTP-Code, Grund) zurück. HTTP/2 über curl, weil Python es nicht eingebaut hat."""
    with tempfile.NamedTemporaryFile("w", suffix=".json") as f:
        json.dump(nutzlast, f, ensure_ascii=False)
        f.flush()
        a = subprocess.run(
            ["curl", "-s", "--http2", "-m", "20", "-w", "\n%{http_code}",
             "-H", "authorization: bearer " + apns_jwt(), "-H", "apns-topic: " + E.apns_topic,
             "-H", "apns-push-type: alert", "-H", "apns-priority: 10",
             "--data-binary", "@" + f.name,
             f"{APNS_HOST.get(umgebung, APNS_HOST['produktion'])}/3/device/{geraet}"],
            capture_output=True, text=True)
    *koerper, code = (a.stdout or "\n0").rsplit("\n", 1)
    grund = ""
    try:
        grund = json.loads(koerper[0]).get("reason", "") if koerper and koerper[0] else ""
    except ValueError:
        pass
    return int(code or 0), grund


def melden(w, art):
    """Push an alle Geräte der Benutzer, die diesen Wunsch haben."""
    if art == "da":
        titel, text = "Hörbuch ist da", f"{w['titel']} – {w['autor']}"
    else:
        titel, text = "Hörbuch noch nicht gefunden", f"{w['titel']} – sucht weiter"
    push(titel, text)
    if not (E.apns_schluessel and E.apns_key_id and E.apns_team_id and E.apns_topic):
        return
    with db() as v:
        z = v.execute("SELECT absItemId FROM wunsch WHERE id=?", (w["id"],)).fetchone()
        benutzer = [w["benutzer"]] + [r[0] for r in v.execute(
            "SELECT benutzer FROM interesse WHERE wunsch=?", (w["id"],))]
        geraete = v.execute("SELECT DISTINCT token, umgebung FROM geraet WHERE benutzer IN (%s)"
                            % ",".join("?" * len(benutzer)), benutzer).fetchall()
    nutzlast = {"aps": {"alert": {"title": titel, "body": text}, "sound": "default"}, "wunschId": w["id"]}
    if z and z[0]:
        nutzlast["absItemId"] = z[0]
    for token, umgebung in geraete:
        try:
            code, grund = apns_senden(token, umgebung, nutzlast)
        except Exception as f:
            log(f"{w['id']}: APNs fehlgeschlagen:", f)
            continue
        if code == 410 or grund in ("BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"):
            with DB_SPERRE, db() as v:
                v.execute("DELETE FROM geraet WHERE token=?", (token,))
            log(f"{w['id']}: Gerät abgemeldet ({grund or code})")
        elif code != 200:
            log(f"{w['id']}: APNs {code} {grund}")
            if code == 403:
                APNS_JWT["wert"] = None


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
        tw = set(woerter(kurztitel(titel)))
        for lid, t, a, rel in v.execute("SELECT id, title, authorNamesFirstLast, relPath FROM libraryItems "
                                        "WHERE mediaType='book' AND isMissing=0"):
            if norm(t or "") == nt and na and na in norm(a or ""):
                return lid
            # Nicht zugeordnete Bücher: Titelwörter und Autor im Ordnernamen bzw. Titel
            alles = set(norm(f"{t} {a} {rel}").split())
            if na and na in alles and tw and tw <= alles and len(" ".join(tw)) >= 5:
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
    s = (s or "").replace("???", " fragezeichen ").replace("!!!", " ausrufezeichen ").translate(UMLAUTE)
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
    zahlen = re.findall(r"\b0*(\d{1,4})\b", name)
    hoerspiel = bool(w["hoerspiel"]) if "hoerspiel" in w.keys() else False
    tw = woerter(kurztitel(w["titel"]))
    titel_ok = bool(tw) and all(x in nw for x in tw)
    teil = str(w["teil"] or "").strip()
    rw = woerter(w["reihe"]) if w["reihe"] else []
    # Folgen einer Reihe (z. B. Hörspielserien): Reihenname + Folgennummer genügen
    reihe_ok = bool(rw and teil and all(x in nw for x in rw) and teil.lstrip("0") in zahlen)
    if not titel_ok and not reihe_ok:
        return None, "Titel passt nicht"
    na = nachname(w["autor"])
    autor_da = na and na in nw
    punkte = 50 if autor_da else (40 if reihe_ok else 0)
    hinweis = []
    if not autor_da and not reihe_ok:
        # ohne Autor nur, wenn Titel lang genug und eindeutig ist
        if len(tw) < 3:
            return None, "Autor fehlt im Namen"
        punkte -= 15
    wunsch_text = norm(" ".join(str(w[k] or "") for k in ("titel", "reihe")))
    if hoerspiel:
        # Laut Audible ein Hörspiel: Hörspiel-Fassungen bevorzugen, „ungekürzt“ spielt keine Rolle
        if "hoerspiel" in nw:
            punkte += 20
        if titel_ok and reihe_ok:
            punkte += 10
    elif re.search(r"\bungekuerzt\b|\bunabridged\b", name):
        punkte += 30
    elif re.search(r"\bgekuerzt\b|\babridged\b", name):
        punkte -= 25
        hinweis.append("gekürzte Fassung")
    verbote = ("kids", "leseprobe", "sample") if hoerspiel else \
        ("hoerspiel", "kids", "kinder", "lesung", "leseprobe", "sample", "radio")
    for verbot in verbote:
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
    if teil and teil.lstrip("0") in zahlen:
        punkte += 10
    if re.search(r"\b\d{1,2} ?(bis|-) ?\d{1,2}\b|\b(box|sammlung|collection|komplett|gesamtausgabe)\b", name):
        punkte -= 20
        hinweis.append("Sammelpaket")
    groesse_mb = (r.get("size") or 0) / 1e6
    if w["laufzeitMin"]:
        mb_min = groesse_mb / max(1, int(w["laufzeitMin"]))
        verlustfrei = bool(nw & {"flac", "wav", "alac"})
        if mb_min < 0.2 or mb_min > (10.0 if verlustfrei else 3.0):
            if "Sammelpaket" not in hinweis:
                return None, f"Größe passt nicht zur Laufzeit ({groesse_mb:.0f} MB)"
        else:
            punkte += 10
    elif groesse_mb < 20:
        return None, "zu klein"
    if nw & {"flac", "wav", "alac"}:
        punkte -= 5  # verlustfrei geht, aber kleinere Fassungen zuerst
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
        anfragen.append(f"{norm(w['reihe'])} {w['teil']}")
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
    if w["hoerspiel"] is None:
        hs = audible_hoerspiel(w["asin"], w["titel"])
        setze(wid, hoerspiel=hs)
        with db() as v:
            w = v.execute("SELECT * FROM wunsch WHERE id=?", (wid,)).fetchone()
    vorhanden = abs_vorhanden(w["asin"], w["titel"], w["autor"])
    if vorhanden:
        setze(wid, status="da", absItemId=vorhanden, hinweis="war schon in der Bibliothek")
        melden(w, "da")
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
        if w["status"] == "gewuenscht" and w["versuche"] == 0 and not w["ausReihe"]:
            melden(w, "nicht_gefunden")  # nur beim ersten Mal, nicht für jeden Teil einer Reihe
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
        melden(w, "da")
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
        if ruhig():
            offen = v.execute("SELECT * FROM wunsch WHERE zurueckgezogen=0 AND (status='gewuenscht' OR "
                              "(status IN ('nicht_gefunden','fehler') AND naechsterVersuch<=?)) "
                              "ORDER BY ausReihe IS NOT NULL, erstellt LIMIT ?",
                              (jetzt().isoformat(), frei)).fetchall()
        else:  # tagsüber oder während gestreamt wird: nur ausdrückliche, neue Wünsche
            offen = v.execute("SELECT * FROM wunsch WHERE zurueckgezogen=0 AND status='gewuenscht' "
                              "AND ausReihe IS NULL ORDER BY erstellt LIMIT ?", (frei,)).fetchall()
    for w in offen:  # gedrosselt: höchstens WUNSCH_PARALLEL gleichzeitig
        try:
            bearbeite_suche(w)
        except Exception as f:
            setze(w["id"], status="fehler", hinweis=f"Suche fehlgeschlagen: {f}"[:300],
                  naechsterVersuch=(jetzt() + timedelta(hours=1)).isoformat())
            log(f"{w['id']}: Suche fehlgeschlagen:", traceback.format_exc())


# ---------------------------------------------------------------- Reihen folgen (Audible-Katalog)

SPRACHEN = {"de": "german", "en": "english", "fr": "french", "es": "spanish", "it": "italian"}
REIHE_PRUEFEN_STUNDEN = 24


def audible(pfad, **param):
    url = f"{E.audible}/1.0/catalog/{pfad}?" + urllib.parse.urlencode(param)
    return json.loads(hole(url, kopf={"Accept": "application/json"}, zeit=30))


def echte_autoren(p):
    rollen = re.compile(r"(?i)translat|übersetz|uebersetz|illustr|herausgeb|editor|bearbeit|adapt")
    namen = [a.get("name", "") for a in p.get("authors") or []]
    echt = [re.sub(r"\s*[-–—]\s*$", "", n).strip() for n in namen if n and not rollen.search(n)]
    return echt or [n for n in namen if n][:1]


def ist_hoerspiel(p):
    """Audible kennzeichnet Hörspiele als content_type „Performance“ bzw. format „original_recording“."""
    return int((p.get("content_type") or "").lower() == "performance"
               or (p.get("format_type") or "").lower() == "original_recording"
               or "hoerspiel" in norm(f"{p.get('title')} {p.get('subtitle')}").split())


def audible_hoerspiel(asin, titel):
    if asin:
        try:
            p = audible(f"products/{asin}", response_groups="product_attrs,product_desc").get("product") or {}
            if p:
                return ist_hoerspiel(p)
        except Exception as f:
            log("Audible-Format nicht abrufbar:", f)
    return int("hoerspiel" in norm(titel).split())


def reihe_von_asin(asin, reihe_name):
    """Audible-ASIN der Reihe zu einem Teil (bei mehreren die mit passendem Namen)."""
    p = audible(f"products/{asin}", response_groups="series").get("product") or {}
    reihen = p.get("series") or []
    if not reihen:
        return None, None
    passend = [x for x in reihen if norm(x.get("title")) == norm(reihe_name)] or reihen
    return passend[0].get("asin"), passend[0].get("title")


def reihe_teile(reihe_asin, sprache):
    """Erschienene Teile der Reihe in der gewünschten Sprache, je Teilnummer einer."""
    rel = (audible(f"products/{reihe_asin}", response_groups="relationships").get("product") or {}) \
        .get("relationships") or []
    kinder = [x for x in rel if x.get("relationship_type") == "series"
              and x.get("relationship_to_product") == "child" and x.get("asin")]
    produkte = []
    for i in range(0, len(kinder), 40):
        asins = ",".join(x["asin"] for x in kinder[i:i + 40])
        produkte += audible("products", asins=asins, response_groups=
                            "product_desc,contributors,media,product_attrs,series").get("products") or []
    nummer = {x["asin"]: (x.get("sequence") or "").strip() for x in kinder}
    sprache_lang = SPRACHEN.get((sprache or "de")[:2], "")
    heute = jetzt().date().isoformat()
    beste = {}
    for p in produkte:
        teil = nummer.get(p.get("asin"), "")
        if not re.fullmatch(r"\d+(\.\d+)?", teil):
            continue  # Sammelboxen wie „1-3“ und Teile ohne Nummer überspringen
        if sprache_lang and (p.get("language") or "").lower() != sprache_lang:
            continue
        if (p.get("release_date") or "9999") > heute:
            continue  # noch nicht erschienen, kommt bei einer späteren Prüfung
        rang = (p.get("format_type") == "unabridged", p.get("runtime_length_min") or 0)
        if teil not in beste or rang > beste[teil][0]:
            beste[teil] = (rang, p)
    teile = []
    for teil, (_, p) in sorted(beste.items(), key=lambda x: float(x[0])):
        teile.append({
            "asin": p["asin"], "teil": teil, "titel": p.get("title"),
            "autor": ", ".join(echte_autoren(p)),
            "sprecher": ", ".join(a.get("name", "") for a in p.get("narrators") or []) or None,
            "laufzeitMin": p.get("runtime_length_min"), "sprache": (sprache or "de")[:2],
            "coverUrl": (p.get("product_images") or {}).get("500"),
            "hoerspiel": ist_hoerspiel(p),
        })
    return teile


def reihe_abgleichen(r):
    """Legt fehlende Teile als Wünsche an; Teile in ABS werden übersprungen."""
    try:
        teile = reihe_teile(r["reiheAsin"], r["sprache"])
    except Exception as f:
        with DB_SPERRE, db() as v:
            v.execute("UPDATE reihe SET geprueft=?, hinweis=? WHERE id=?",
                      (jetzt().isoformat(), "Audible gerade nicht erreichbar", r["id"]))
        log(f"{r['id']}: Audible-Abfrage fehlgeschlagen:", f)
        return
    neu = 0
    for t in teile:
        in_abs = 1 if abs_vorhanden(t["asin"], t["titel"], t["autor"]) else 0
        with DB_SPERRE, db() as v:
            v.execute("INSERT INTO reihe_teil VALUES (?,?,?,?,?) ON CONFLICT(reihe, asin) DO UPDATE SET "
                      "teil=excluded.teil, titel=excluded.titel, inAbs=excluded.inAbs",
                      (r["id"], t["asin"], t["teil"], t["titel"], in_abs))
            if in_abs:
                continue
            z = v.execute("SELECT id, benutzer FROM wunsch WHERE upper(asin)=upper(?) AND zurueckgezogen=0",
                          (t["asin"],)).fetchone()
            if z:
                if z["benutzer"] != r["benutzer"]:
                    v.execute("INSERT OR IGNORE INTO interesse VALUES (?,?)", (z["id"], r["benutzer"]))
                continue
            wid, zeit = "w_" + secrets.token_hex(4), jetzt().isoformat()
            v.execute("INSERT INTO wunsch (id, benutzer, asin, titel, autor, sprecher, reihe, teil, "
                      "laufzeitMin, sprache, coverUrl, status, erstellt, aktualisiert, ausReihe, hoerspiel) "
                      "VALUES (?,?,?,?,?,?,?,?,?,?,?,'gewuenscht',?,?,?,?)",
                      (wid, r["benutzer"], t["asin"], t["titel"], t["autor"] or r["autor"], t["sprecher"],
                       r["reihe"], t["teil"], t["laufzeitMin"], t["sprache"], t["coverUrl"],
                       zeit, zeit, r["id"], t["hoerspiel"]))
            neu += 1
    with DB_SPERRE, db() as v:
        v.execute("UPDATE reihe SET geprueft=?, hinweis=? WHERE id=?",
                  (jetzt().isoformat(), None if teile else "Keine erschienenen Teile in dieser Sprache gefunden",
                   r["id"]))
    if neu:
        log(f"{r['id']}: {neu} Teile neu gewünscht")
        WECKER.set()


def reihe_json(v, r):
    zahlen = v.execute(
        "SELECT count(*), "
        " sum(CASE WHEN t.inAbs=1 OR w.status='da' THEN 1 ELSE 0 END), "
        " sum(CASE WHEN t.inAbs=0 AND w.id IS NOT NULL AND w.status!='da' THEN 1 ELSE 0 END) "
        "FROM reihe_teil t LEFT JOIN wunsch w ON upper(w.asin)=upper(t.asin) AND w.zurueckgezogen=0 "
        "WHERE t.reihe=?", (r["id"],)).fetchone()
    d = {"id": r["id"], "reihe": r["reihe"], "autor": r["autor"], "sprache": r["sprache"],
         "erstellt": iso(datetime.fromisoformat(r["erstellt"])),
         "teileGesamt": zahlen[0] or 0, "teileDa": zahlen[1] or 0, "teileGewuenscht": zahlen[2] or 0}
    if r["geprueft"]:
        d["geprueft"] = iso(datetime.fromisoformat(r["geprueft"]))
    if r["hinweis"]:
        d["hinweis"] = r["hinweis"]
    return d


def reihen_pruefen():
    if not ruhig():
        return
    grenze = (jetzt() - timedelta(hours=REIHE_PRUEFEN_STUNDEN)).isoformat()
    with db() as v:
        faellig = v.execute("SELECT * FROM reihe WHERE zurueckgezogen=0 AND (geprueft IS NULL OR geprueft<?) "
                            "ORDER BY geprueft LIMIT 5", (grenze,)).fetchall()
    for r in faellig:  # gedrosselt: höchstens 5 Reihen pro Lauf
        reihe_abgleichen(r)
        time.sleep(2)


# ---------------------------------------------------------------- Entdecken (Hörverlauf + Audible)

ENTDECKEN_CACHE = {}
ENTDECKEN_SPERRE = threading.Lock()
ENTDECKEN_STUNDEN = 6
AUDIBLE_DETAILS = "product_desc,product_extended_attrs,product_attrs,contributors,media,series,category_ladders"


def hoerverlauf(abs_id):
    """Zuletzt gehörte Bücher des ABS-Benutzers mit ASIN, Autoren und Sprechern (nur lesend aus der ABS-DB)."""
    v = abs_db()
    if not v:
        return []
    try:
        zeilen = v.execute(
            "SELECT b.id, b.asin, b.title, b.narrators, mp.isFinished, mp.currentTime, mp.duration, mp.updatedAt "
            "FROM mediaProgresses mp JOIN books b ON b.id=mp.mediaItemId "
            "WHERE mp.userId=? AND mp.mediaItemType='book' AND (mp.isFinished=1 OR mp.currentTime>600) "
            "ORDER BY mp.updatedAt DESC LIMIT 40", (abs_id,)).fetchall()
        buecher = []
        for bid, asin, titel, sprecher, fertig, zeit, dauer, _ in zeilen:
            autoren = [a for (a,) in v.execute(
                "SELECT a.name FROM bookAuthors ba JOIN authors a ON a.id=ba.authorId WHERE ba.bookId=?", (bid,))]
            try:
                sprecher = json.loads(sprecher or "[]")
            except ValueError:
                sprecher = []
            buecher.append({"asin": asin, "titel": titel, "autoren": autoren, "sprecher": sprecher,
                            "fertig": bool(fertig)})
        if not buecher:  # noch nichts gehört: die zuletzt in die Bibliothek gekommenen Bücher
            for asin, titel in v.execute(
                    "SELECT b.asin, b.title FROM libraryItems li JOIN books b ON b.id=li.mediaId "
                    "WHERE b.asin IS NOT NULL AND b.asin!='' AND li.isMissing=0 "
                    "ORDER BY li.createdAt DESC LIMIT 6"):
                buecher.append({"asin": asin, "titel": titel, "autoren": [], "sprecher": [], "neu": True})
        return buecher
    finally:
        v.close()


def ohne_html(t):
    t = re.sub(r"<br\s*/?>|</p>", "\n", t or "")
    t = re.sub(r"<[^>]+>", "", t)
    for a, b in (("&amp;", "&"), ("&quot;", '"'), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")):
        t = t.replace(a, b)
    return re.sub(r"\n{3,}", "\n\n", t).strip()


def als_suchtreffer(p, grund):
    """Felder wie ABS /api/search/books (Audible-Anbieter), plus grund."""
    jahr = (p.get("release_date") or p.get("issue_date") or "")[:4] or None
    sprache = p.get("language") or None
    return {
        "title": p.get("title"), "subtitle": p.get("subtitle"),
        "author": ", ".join(echte_autoren(p)) or None,
        "narrator": ", ".join(a.get("name", "") for a in p.get("narrators") or []) or None,
        "cover": (p.get("product_images") or {}).get("500"),
        "asin": p.get("asin"), "language": sprache.capitalize() if sprache else None,
        "duration": p.get("runtime_length_min"),
        "series": [{"series": x.get("title"), "sequence": x.get("sequence") or None} for x in p.get("series") or []],
        "description": ohne_html(p.get("publisher_summary") or p.get("merchandising_summary")),
        "publishedYear": jahr, "publisher": p.get("publisher_name"),
        "grund": grund,
    }


def entdecken(benutzer):
    if not benutzer.startswith("abs:"):
        return []
    verlauf = hoerverlauf(benutzer[4:])
    autoren_zahl = {}
    for b in verlauf:
        for a in b["autoren"]:
            autoren_zahl[norm(a)] = (autoren_zahl.get(norm(a), (0, a))[0] + 1, a)
    lieblingsautoren = {k: v[1] for k, v in autoren_zahl.items() if v[0] >= 2}
    saat = [b for b in verlauf if b["asin"]][:6]
    kandidaten = {}  # asin -> [punkte, grund, produkt]

    def dazu(p, punkte, grund):
        a = p.get("asin")
        if not a:
            return
        if a in kandidaten:
            kandidaten[a][0] += punkte
        else:
            kandidaten[a] = [punkte, grund, p]

    kategorien = {}
    for i, b in enumerate(saat):
        try:
            sims = audible(f"products/{b['asin']}/sims", similarity_type="RawSimilarities", num_results=25,
                           response_groups="product_desc,product_attrs,contributors,series,category_ladders")
        except Exception as f:
            log("Audible-Ähnliche nicht abrufbar:", f)
            continue
        grund = ("Passt zu deiner Bibliothek: " if b.get("neu") else "Weil du „") + (b["titel"] or "")
        grund = grund if b.get("neu") else grund + "“ gehört hast"
        for rang, p in enumerate(sims.get("similar_products") or []):
            dazu(p, max(1, 25 - rang) * (1.0 - i * 0.02), grund)
            for l in p.get("category_ladders") or []:
                if l.get("ladder"):
                    k = l["ladder"][-1]
                    kategorien[k["id"]] = (kategorien.get(k["id"], (0, k["name"]))[0] + 1, k["name"])
        time.sleep(0.5)
    for kid, (_, name) in sorted(kategorien.items(), key=lambda x: -x[1][0])[:2]:
        try:
            best = audible("products", category_id=kid, products_sort_by="BestSellers", num_results=25,
                           response_groups="product_desc,product_attrs,contributors,series")
        except Exception as f:
            log("Audible-Bestseller nicht abrufbar:", f)
            continue
        for rang, p in enumerate(best.get("products") or []):
            dazu(p, max(1, 15 - rang) * 0.6, f"Beliebt in {name}")
        time.sleep(0.5)

    heute = jetzt().date().isoformat()
    with db() as v:
        gewuenscht = {(z[0] or "").upper() for z in v.execute("SELECT asin FROM wunsch WHERE zurueckgezogen=0")}
    gesehen_titel, auswahl, je_autor = set(), [], {}
    for a, (punkte, grund, p) in sorted(kandidaten.items(), key=lambda x: -x[1][0]):
        if (p.get("language") or "").lower() != "german" or (p.get("release_date") or "9999") > heute:
            continue
        if any("-" in (x.get("sequence") or "") for x in p.get("series") or []):
            continue  # Sammelbox
        if re.search(r"(?i)\b(sammelband|box|bundle|gesamtausgabe|teile? \d+\s*[-–]\s*\d+)\b", p.get("title") or ""):
            continue
        autoren = echte_autoren(p)
        schluessel = norm(kurztitel(p.get("title"))) + "|" + (nachname(autoren[0]) if autoren else "")
        if a.upper() in gewuenscht or schluessel in gesehen_titel:
            continue
        erster = nachname(autoren[0]) if autoren else ""
        if je_autor.get(erster, 0) >= 3:
            continue  # Abwechslung: höchstens 3 Vorschläge je Autor
        if abs_vorhanden(a, p.get("title"), autoren[0] if autoren else ""):
            continue
        gesehen_titel.add(schluessel)
        je_autor[erster] = je_autor.get(erster, 0) + 1
        for au in autoren:
            if norm(au) in lieblingsautoren:
                grund = f"Weil du {lieblingsautoren[norm(au)]} hörst"
                break
        auswahl.append((a, grund))
        if len(auswahl) >= 30:
            break
    details = {}
    asins = [a for a, _ in auswahl]
    for i in range(0, len(asins), 40):
        try:
            for p in audible("products", asins=",".join(asins[i:i + 40]),
                             response_groups=AUDIBLE_DETAILS).get("products") or []:
                details[p["asin"]] = p
        except Exception as f:
            log("Audible-Details nicht abrufbar:", f)
    treffer = []
    for a, grund in auswahl:
        p = details.get(a) or kandidaten[a][2]
        if p.get("format_type") == "abridged":
            grund += " (gekürzte Fassung)"
        treffer.append(als_suchtreffer(p, grund))
    return treffer


ENTDECKEN_LAEUFT = set()


def entdecken_neu_berechnen(benutzer):
    try:
        treffer = entdecken(benutzer)
        with ENTDECKEN_SPERRE:
            ENTDECKEN_CACHE[benutzer] = (time.time() + ENTDECKEN_STUNDEN * 3600, treffer)
        return treffer
    finally:
        with ENTDECKEN_SPERRE:
            ENTDECKEN_LAEUFT.discard(benutzer)


def entdecken_zwischengespeichert(benutzer, neu=False):
    """Vorhandene Vorschläge werden immer ausgeliefert; neu gerechnet nur, wenn keine da sind oder neu=1."""
    with ENTDECKEN_SPERRE:
        z = ENTDECKEN_CACHE.get(benutzer)
        if z and not neu:
            return z[1]  # tagsüber nur ausliefern, erneuert wird nachts
        ENTDECKEN_LAEUFT.add(benutzer)
    t = entdecken_neu_berechnen(benutzer)
    threading.Thread(target=vorrat_speichern, daemon=True).start()
    return t


def entdecken_vorwaermen():
    """Nach dem Start die Vorschläge bekannter Benutzer berechnen, damit die App nicht warten muss."""
    time.sleep(10)
    with db() as v:
        benutzer = [z[0] for z in v.execute("SELECT DISTINCT benutzer FROM wunsch WHERE benutzer LIKE 'abs:%' "
                                            "UNION SELECT benutzer FROM geraet UNION SELECT benutzer FROM reihe")]
    for b in benutzer:
        try:
            with ENTDECKEN_SPERRE:
                if b in ENTDECKEN_CACHE or b in ENTDECKEN_LAEUFT:
                    continue
            if not leerlauf():
                return
            with ENTDECKEN_SPERRE:
                ENTDECKEN_LAEUFT.add(b)
            entdecken_neu_berechnen(b)
        except Exception:
            log("Vorwärmen fehlgeschlagen:", traceback.format_exc())
        time.sleep(2)


# ---------------------------------------------------------------- Stöbern nach Kategorie

KATEGORIEN = {"zeit": 0, "daten": None}
STOEBERN_CACHE = {}
HOERSPIELE_ID = "hoerspiele"


def kategorien():
    if KATEGORIEN["daten"] and KATEGORIEN["zeit"]:  # erneuert nur das nächtliche Vorrechnen
        return KATEGORIEN["daten"]
    roh = audible("categories", categories_num_levels=2).get("categories") or []
    daten = [{"id": HOERSPIELE_ID, "name": "Hörspiele", "unter": []}]
    for k in sorted(roh, key=lambda x: x.get("name") or ""):
        daten.append({"id": k["id"], "name": k.get("name"),
                      "unter": sorted(({"id": u["id"], "name": u.get("name")} for u in k.get("children") or []),
                                      key=lambda x: x["name"] or "")})
    KATEGORIEN.update(zeit=time.time(), daten=daten)
    return daten


def kategorie_name(kid):
    for k in kategorien():
        if k["id"] == kid:
            return k["name"]
        for u in k["unter"]:
            if u["id"] == kid:
                return u["name"]
    return None


def stoebern(kid, sortierung):
    name = kategorie_name(kid)
    if not name:
        return None
    sortiert = {"beliebt": "BestSellers", "neu": "-ReleaseDate"}[sortierung]
    heute = jetzt().date().isoformat()
    with db() as v:
        gewuenscht = {(z[0] or "").upper() for z in v.execute("SELECT asin FROM wunsch WHERE zurueckgezogen=0")}
    treffer, gesehen = [], set()
    # Audible kann nicht nach Sprache filtern, und „neu“ beginnt mit Vorbestellungen: mehrere Seiten
    for seite in range(1, 6 if sortierung == "beliebt" else 21):
        param = dict(products_sort_by=sortiert, num_results=50, page=seite,
                     response_groups="product_attrs,product_desc,contributors,series")
        if kid == HOERSPIELE_ID:
            param["keywords"] = "Hörspiel"
        else:
            param["category_id"] = kid
        produkte = audible("products", **param).get("products") or []
        for p in produkte:
            if (p.get("language") or "").lower() != "german" or (p.get("release_date") or "9999") > heute:
                continue
            if p.get("is_adult_product") and "erotik" not in norm(name):
                continue
            if kid == HOERSPIELE_ID and not ist_hoerspiel(p):
                continue
            if any("-" in (x.get("sequence") or "") for x in p.get("series") or []):
                continue
            autoren = echte_autoren(p)
            schluessel = norm(kurztitel(p.get("title"))) + "|" + (nachname(autoren[0]) if autoren else "")
            if (p.get("asin") or "").upper() in gewuenscht or schluessel in gesehen:
                continue
            gesehen.add(schluessel)
            if abs_vorhanden(p.get("asin"), p.get("title"), autoren[0] if autoren else ""):
                continue
            treffer.append(p["asin"])
            if len(treffer) >= 30:
                break
        if len(treffer) >= 30 or len(produkte) < 50:
            break
        time.sleep(0.3)
    details = {}
    if treffer:
        for p in audible("products", asins=",".join(treffer), response_groups=AUDIBLE_DETAILS).get("products") or []:
            details[p["asin"]] = p
    grund = ("Bestseller in " if sortierung == "beliebt" else "Neu in ") + name
    return [als_suchtreffer(details[a], grund) for a in treffer if a in details]


def stoebern_zwischengespeichert(kid, sortierung, neu=False):
    schluessel = (kid, sortierung)
    z = STOEBERN_CACHE.get(schluessel)
    if z and not neu:
        return z[1]
    t = stoebern(kid, sortierung)
    if t is not None:
        if len(STOEBERN_CACHE) > 400:
            STOEBERN_CACHE.clear()
        STOEBERN_CACHE[schluessel] = (time.time() + 6 * 3600, t)
        threading.Thread(target=vorrat_speichern, daemon=True).start()
    return t


# ---------------------------------------------------------------- Musik wünschen (Lidarr)

def push_an(benutzer, titel, text, extra):
    """APNs-Nachricht an alle Geräte dieser Benutzer."""
    if not (E.apns_schluessel and E.apns_key_id and E.apns_team_id and E.apns_topic) or not benutzer:
        return
    with db() as v:
        geraete = v.execute("SELECT DISTINCT token, umgebung FROM geraet WHERE benutzer IN (%s)"
                            % ",".join("?" * len(benutzer)), benutzer).fetchall()
    nutzlast = {"aps": {"alert": {"title": titel, "body": text}, "sound": "default"}, **extra}
    for token, umgebung in geraete:
        try:
            code, grund = apns_senden(token, umgebung, nutzlast)
        except Exception as f:
            log("APNs fehlgeschlagen:", f)
            continue
        if code == 410 or grund in ("BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"):
            with DB_SPERRE, db() as v:
                v.execute("DELETE FROM geraet WHERE token=?", (token,))
        elif code != 200:
            log(f"APNs {code} {grund}")


def lidarr(pfad, daten=None, methode=None, **param):
    teile = []
    for k, w in param.items():
        for x in (w if isinstance(w, list) else [w]):
            teile.append((k, x))
    url = f"{E.lidarr}/api/v1/{pfad}" + ("?" + urllib.parse.urlencode(teile) if teile else "")
    kopf = {"X-Api-Key": E.lidarr_key, "Content-Type": "application/json"}
    roh = hole(url, json.dumps(daten).encode() if daten is not None else None, kopf, zeit=120, methode=methode)
    return json.loads(roh) if roh else None


MUSIK_TYPEN = ("Album", "Single")  # Regel des Benutzers: nur Alben und Singles
MB_SPERRE = threading.Lock()
MB_ZEIT = [0.0]


def musicbrainz(pfad, **param):
    """MusicBrainz höchstens 1 Anfrage pro Sekunde, allgemeiner Client-Name ohne Kontaktdaten."""
    with MB_SPERRE:
        warte = 1.1 - (time.time() - MB_ZEIT[0])
        if warte > 0:
            time.sleep(warte)
        MB_ZEIT[0] = time.time()
    param["fmt"] = "json"
    url = f"https://musicbrainz.org/ws/2/{pfad}?" + urllib.parse.urlencode(param)
    return json.loads(hole(url, kopf={"User-Agent": f"Hoerbuchwunsch/{VERSION} (+https://github.com/DrdotHouse2106/Ohrregal)",
                                      "Accept": "application/json"}, zeit=30))


def album_cover(a):
    if a.get("remoteCover"):
        return a["remoteCover"]
    for b in a.get("images") or []:
        if b.get("coverType") == "cover":
            return b.get("remoteUrl") or b.get("url")
    return None


def album_status(a, queue_ids, gewuenscht_mbids):
    st = a.get("statistics") or {}
    if st.get("trackFileCount") and st.get("trackFileCount", 0) >= (st.get("totalTrackCount") or st.get("trackCount") or 1):
        return "da"
    if a.get("id") in queue_ids:
        return "laedt"
    if a.get("foreignAlbumId") in gewuenscht_mbids or (a.get("id") and a.get("monitored")):
        return "gewuenscht"
    return "fehlt"


def album_json(a, queue_ids=(), gewuenscht=()):
    kuenstler = a.get("artist") or {}
    return {"mbid": a.get("foreignAlbumId"), "titel": a.get("title"),
            "kuenstler": kuenstler.get("artistName") or a.get("artistName"),
            "kuenstlerMbid": kuenstler.get("foreignArtistId"),
            "jahr": (a.get("releaseDate") or "")[:4] or None, "typ": a.get("albumType"),
            "titelAnzahl": (a.get("statistics") or {}).get("totalTrackCount") or
            sum(len(r.get("tracks") or []) or (r.get("trackCount") or 0) for r in (a.get("releases") or [])[:1]) or None,
            "cover": album_cover(a), "status": album_status(a, queue_ids, gewuenscht)}


def lidarr_queue_ids():
    try:
        d = lidarr("queue", pageSize=500)
        return {x.get("albumId") for x in d.get("records") or [] if x.get("albumId")}
    except Exception:
        return set()


def musik_gewuenscht():
    with db() as v:
        return {z[0] for z in v.execute("SELECT mbid FROM musik_wunsch WHERE zurueckgezogen=0 AND status!='da'")}


def lidarr_album(mbid):
    a = lidarr("album", foreignAlbumId=mbid)
    return a[0] if a else None


def musik_suche(q):
    roh = lidarr("album/lookup", term=q) or []
    queue, gew = lidarr_queue_ids(), musik_gewuenscht()
    alben = []
    for a in roh:
        if a.get("albumType") not in MUSIK_TYPEN or a.get("secondaryTypes"):
            continue
        if a.get("id"):  # schon in Lidarr: echten Stand mit Statistik holen
            try:
                a = {**lidarr(f"album/{a['id']}"), "remoteCover": album_cover(a)}
            except Exception:
                pass
        alben.append(album_json(a, queue, gew))
    return alben


def lidarr_kuenstler(mbid):
    a = lidarr("artist", mbId=mbid) or []
    a = [x for x in a if x.get("foreignArtistId") == mbid]
    return a[0] if a else None


def musik_kuenstler(name, mbid):
    if not mbid:
        treffer = lidarr("artist/lookup", term=name) or []
        if not treffer:
            return None
        mbid = treffer[0].get("foreignArtistId")
        name = treffer[0].get("artistName") or name
    k = lidarr_kuenstler(mbid)
    queue, gew = lidarr_queue_ids(), musik_gewuenscht()
    alben = []
    if k:
        for a in lidarr("album", artistId=k["id"]) or []:
            if a.get("albumType") in MUSIK_TYPEN and not a.get("secondaryTypes"):
                alben.append(album_json({**a, "artist": k}, queue, gew))
        info = {"name": k["artistName"], "mbid": mbid, "inLidarr": True,
                "folgt": k.get("monitored") and k.get("monitorNewItems") in ("all", "new")}
    else:
        rg, offset = [], 0
        while True:
            d = musicbrainz("release-group", artist=mbid, type="album|single", limit=100, offset=offset)
            rg += d.get("release-groups") or []
            offset += 100
            if offset >= (d.get("release-group-count") or 0) or offset >= 400:
                break
        for g in rg:
            if g.get("secondary-types"):
                continue
            alben.append({"mbid": g["id"], "titel": g.get("title"), "kuenstler": name, "kuenstlerMbid": mbid,
                          "jahr": (g.get("first-release-date") or "")[:4] or None, "typ": g.get("primary-type"),
                          "titelAnzahl": None, "cover": f"https://coverartarchive.org/release-group/{g['id']}/front-500",
                          "status": "gewuenscht" if g["id"] in gew else "fehlt"})
        info = {"name": name, "mbid": mbid, "inLidarr": False, "folgt": False}
    alben.sort(key=lambda x: x["jahr"] or "", reverse=True)
    return {"kuenstler": info, "alben": alben}


def kuenstler_anlegen(mbid, neue_alben):
    """Künstler ohne Diskografie anlegen: nichts überwacht, nur auf Wunsch neue Alben."""
    treffer = lidarr("artist/lookup", term=f"lidarr:{mbid}") or []
    if not treffer:
        raise RuntimeError("Künstler bei Lidarr nicht gefunden")
    k = treffer[0]
    k.update(qualityProfileId=E.lidarr_qualitaet, metadataProfileId=E.lidarr_metadaten,
             rootFolderPath=E.lidarr_ordner, monitored=True,
             monitorNewItems="new" if neue_alben else "none",
             addOptions={"monitor": "none", "searchForMissingAlbums": False})
    return lidarr("artist", k, methode="POST")


def musik_wunsch_anlegen(name, d):
    mbid = str(d.get("mbid") or "").strip().lower()
    if not re.fullmatch(r"[0-9a-f-]{36}", mbid):
        return 400, {"fehler": "ungueltig", "text": "mbid (MusicBrainz-ID des Albums) ist Pflicht"}
    with DB_SPERRE, db() as v:
        z = v.execute("SELECT * FROM musik_wunsch WHERE mbid=? AND benutzer=? AND zurueckgezogen=0",
                      (mbid, name)).fetchone()
    if z:
        return 200, musik_wunsch_json(z)
    a = lidarr_album(mbid)
    if a and album_status(a, (), ()) == "da":
        return 409, {"fehler": "schon_vorhanden", "text": "Das Album ist schon in der Bibliothek"}
    if not a:
        km = str(d.get("kuenstlerMbid") or "").strip().lower()
        if not km:
            treffer = [x for x in lidarr("album/lookup", term=f"lidarr:{mbid}") or [] if x.get("foreignAlbumId") == mbid]
            km = ((treffer[0].get("artist") or {}).get("foreignArtistId") if treffer else "") or ""
        if not km:
            return 404, {"fehler": "kein_treffer", "text": "Bei Lidarr nicht gefunden"}
        if not lidarr_kuenstler(km):
            kuenstler_anlegen(km, neue_alben=False)
            for _ in range(30):  # Lidarr lädt die Alben des neuen Künstlers nach
                time.sleep(2)
                a = lidarr_album(mbid)
                if a:
                    break
        if not a:
            treffer = [x for x in lidarr("album/lookup", term=f"lidarr:{mbid}") or [] if x.get("foreignAlbumId") == mbid]
            if not treffer:
                return 404, {"fehler": "kein_treffer", "text": "Bei Lidarr nicht gefunden"}
            k = lidarr_kuenstler(km)
            neu = {**treffer[0], "artistId": k["id"], "artist": k, "monitored": True,
                   "addOptions": {"searchForNewAlbum": False}}
            a = lidarr("album", neu, methode="POST")
    lidarr("album/monitor", {"albumIds": [a["id"]], "monitored": True}, methode="PUT")
    wid, t = "m_" + secrets.token_hex(4), jetzt().isoformat()
    k = a.get("artist") or {}
    with DB_SPERRE, db() as v:
        v.execute("INSERT INTO musik_wunsch (id, benutzer, mbid, kuenstlerMbid, titel, kuenstler, cover, status, "
                  "lidarrId, erstellt, aktualisiert) VALUES (?,?,?,?,?,?,?,'gewuenscht',?,?,?)",
                  (wid, name, mbid, k.get("foreignArtistId") or d.get("kuenstlerMbid"),
                   a.get("title") or d.get("titel"), k.get("artistName") or d.get("kuenstler"),
                   album_cover(a), a["id"], t, t))
        z = v.execute("SELECT * FROM musik_wunsch WHERE id=?", (wid,)).fetchone()
    log(f"{wid}: Album gewünscht von {name}")
    WECKER.set()
    return 201, musik_wunsch_json(z)


def musik_wunsch_json(z):
    d = {k: z[k] for k in ("id", "mbid", "titel", "kuenstler", "cover", "status")}
    if z["hinweis"]:
        d["hinweis"] = bereinigt(z["hinweis"])
    d["erstellt"] = iso(datetime.fromisoformat(z["erstellt"]))
    d["aktualisiert"] = iso(datetime.fromisoformat(z["aktualisiert"]))
    return d


def musik_setze(wid, **werte):
    werte["aktualisiert"] = jetzt().isoformat()
    with DB_SPERRE, db() as v:
        v.execute("UPDATE musik_wunsch SET " + ", ".join(f"{k}=?" for k in werte) + " WHERE id=?",
                  (*werte.values(), wid))


def musik_arbeiten():
    """Stand der Musik-Wünsche nachführen; Suchen gedrosselt, Neuversuche nur in der Ruhezeit."""
    if not (E.lidarr and E.lidarr_key):
        return
    with db() as v:
        offen = v.execute("SELECT * FROM musik_wunsch WHERE zurueckgezogen=0 AND status!='da'").fetchall()
    if not offen:
        return
    queue = {}
    try:
        for x in lidarr("queue", pageSize=500).get("records") or []:
            if x.get("albumId"):
                queue[x["albumId"]] = x
    except Exception as f:
        log("Lidarr-Warteschlange nicht abrufbar:", f)
        return
    suchen = 0
    for w in offen:
        try:
            a = lidarr(f"album/{w['lidarrId']}")
        except urllib.error.HTTPError as f:
            if f.code == 404:
                musik_setze(w["id"], status="fehler", hinweis="Album ist nicht mehr in Lidarr")
            continue
        except Exception:
            continue
        if album_status(a, (), ()) == "da":
            musik_setze(w["id"], status="da", hinweis=None)
            push_an([w["benutzer"]], "Album ist da", f"{w['titel']} – {w['kuenstler']}",
                    {"musikWunschId": w["id"], "mbid": w["mbid"]})
            log(f"{w['id']}: Album da")
            continue
        q = queue.get(w["lidarrId"])
        if q:
            st = "einsortieren" if (q.get("trackedDownloadState") or "").startswith("import") else "laedt"
            hinweis = None
            if q.get("trackedDownloadState") == "importFailed":
                st, hinweis = "fehler", "Import in Lidarr fehlgeschlagen"
            if st != w["status"] or hinweis != w["hinweis"]:
                musik_setze(w["id"], status=st, hinweis=hinweis)
            continue
        faellig = not w["gesucht"] or (
            ruhig() and datetime.fromisoformat(w["gesucht"]) < jetzt() - timedelta(hours=24))
        if faellig and suchen < 3:
            lidarr("command", {"name": "AlbumSearch", "albumIds": [w["lidarrId"]]}, methode="POST")
            musik_setze(w["id"], gesucht=jetzt().isoformat(),
                        status="gewuenscht" if not w["gesucht"] else w["status"])
            suchen += 1
        elif w["gesucht"] and w["status"] in ("gewuenscht", "laedt") and \
                datetime.fromisoformat(w["gesucht"]) < jetzt() - timedelta(minutes=30):
            musik_setze(w["id"], status="nicht_gefunden", hinweis="Kein passender Download gefunden, sucht nachts erneut")


def musik_folgen(name, d, folgen):
    km = str(d.get("kuenstlerMbid") or "").strip().lower()
    if not re.fullmatch(r"[0-9a-f-]{36}", km):
        return 400, {"fehler": "ungueltig", "text": "kuenstlerMbid ist Pflicht"}
    k = lidarr_kuenstler(km)
    if not k:
        if not folgen:
            return 204, None
        kuenstler_anlegen(km, neue_alben=True)
        log(f"Künstler neu angelegt, folgt neuen Alben ({name})")
        return 201, {"kuenstlerMbid": km, "folgt": True}
    k.update(monitored=True, monitorNewItems="new" if folgen else "none")
    lidarr(f"artist/{k['id']}", k, methode="PUT")
    log(f"Künstler {'folgen' if folgen else 'nicht mehr folgen'} ({name})")
    return (201, {"kuenstlerMbid": km, "folgt": True}) if folgen else (204, None)


def musik_neuerscheinungen():
    heute = jetzt().date()
    ein = lidarr("calendar", start=(heute - timedelta(days=30)).isoformat(),
                 end=(heute + timedelta(days=90)).isoformat(), unmonitored="true", includeArtist="true") or []
    queue, gew = lidarr_queue_ids(), musik_gewuenscht()
    alben = []
    for a in ein:
        if a.get("albumType") in MUSIK_TYPEN and not a.get("secondaryTypes") \
                and (a.get("artist") or {}).get("monitorNewItems") in ("all", "new"):
            j = album_json(a, queue, gew)
            j["erscheint"] = (a.get("releaseDate") or "")[:10] or None
            alben.append(j)
    alben.sort(key=lambda x: x["erscheint"] or "")
    return alben


ND_CACHE = {}


def navidrome_benutzer(u, t, s_):
    if not (E.navidrome and u and t and s_):
        return None
    h = hash_token(f"{u}|{t}|{s_}")
    z = ND_CACHE.get(h)
    if z and z[1] > time.time():
        return z[0]
    try:
        d = json.loads(hole(f"{E.navidrome}/rest/ping?" + urllib.parse.urlencode(
            dict(u=u, t=t, s=s_, v="1.16.1", c="hoerbuchwunsch", f="json")), zeit=10))
    except Exception as f:
        log("Navidrome nicht erreichbar:", f)
        return None
    if (d.get("subsonic-response") or {}).get("status") != "ok":
        return None
    name = "nd:" + u
    if len(ND_CACHE) > 1000:
        ND_CACHE.clear()
    ND_CACHE[h] = (name, time.time() + 300)
    return name


# ---------------------------------------------------------------- Ruhezeiten und Vorrat

LEERLAUF = {"zeit": 0, "wert": True, "grund": ""}


def leerlauf():
    """Niemand streamt bei Jellyfin oder hört bei ABS, keine Aufnahme läuft (1 Minute zwischengespeichert)."""
    if time.time() - LEERLAUF["zeit"] < 60:
        return LEERLAUF["wert"]
    grund = ""
    if E.jellyfin and E.jellyfin_key:
        kopf = {"Authorization": f'MediaBrowser Token="{E.jellyfin_key}"'}
        try:
            for x in json.loads(hole(E.jellyfin + "/Sessions?activeWithinSeconds=300", kopf=kopf, zeit=10)):
                if x.get("NowPlayingItem") and not (x.get("PlayState") or {}).get("IsPaused"):
                    grund = "Jellyfin streamt"
            if not grund:
                timer = json.loads(hole(E.jellyfin + "/LiveTv/Timers", kopf=kopf, zeit=10)).get("Items") or []
                if any(t.get("Status") == "InProgress" for t in timer):
                    grund = "Aufnahme läuft"
        except Exception as f:
            log("Jellyfin-Sitzungen nicht abrufbar:", f)
    v = abs_db()
    if v and not grund:
        try:
            grenze = (jetzt() - timedelta(minutes=3)).strftime("%Y-%m-%d %H:%M:%S")
            if v.execute("SELECT count(*) FROM playbackSessions WHERE updatedAt>?", (grenze,)).fetchone()[0]:
                grund = "Audiobookshelf spielt"
        except sqlite3.Error:
            pass
        finally:
            v.close()
    LEERLAUF.update(zeit=time.time(), wert=not grund, grund=grund)
    return not grund


def nachts():
    try:
        from zoneinfo import ZoneInfo
        stunde = datetime.now(ZoneInfo(E.zeitzone)).hour
    except Exception:
        stunde = datetime.now().hour
    return E.nacht_von <= stunde < E.nacht_bis


def ruhig():
    return nachts() and leerlauf()


VORRAT_SPERRE = threading.Lock()


def vorrat_speichern():
    with VORRAT_SPERRE:
        daten = {"entdecken": ENTDECKEN_CACHE.copy(),
                 "stoebern": {f"{k[0]}|{k[1]}": v for k, v in STOEBERN_CACHE.items()},
                 "kategorien": KATEGORIEN, "nacht": VORRECHNEN}
        tmp = E.vorrat + ".neu"
        with open(tmp, "w") as f:
            json.dump(daten, f, ensure_ascii=False)
        os.replace(tmp, E.vorrat)


def vorrat_laden():
    try:
        with open(E.vorrat) as f:
            d = json.load(f)
    except (FileNotFoundError, ValueError):
        return
    ENTDECKEN_CACHE.update({k: tuple(v) for k, v in d.get("entdecken", {}).items()})
    for k, v in d.get("stoebern", {}).items():
        kid, sortierung = k.split("|", 1)
        STOEBERN_CACHE[(kid, sortierung)] = tuple(v)
    if d.get("kategorien", {}).get("daten"):
        KATEGORIEN.update(d["kategorien"])
    VORRECHNEN.update(d.get("nacht", {}))
    log(f"Vorrat geladen: {len(ENTDECKEN_CACHE)} Benutzer, {len(STOEBERN_CACHE)} Stöber-Listen")


VORRECHNEN = {"datum": "", "erledigt": []}


def vorrechnen():
    """Einmal pro Nacht im Leerlauf alles neu berechnen; bei Streaming unterbrechen und später weitermachen."""
    if not ruhig():
        return
    heute = jetzt().astimezone().date().isoformat()
    if VORRECHNEN["datum"] != heute:
        VORRECHNEN.update(datum=heute, erledigt=[], fertig=False)
    if VORRECHNEN.get("fertig"):
        return
    aufgaben = [("kategorien", "")]
    with db() as v:
        for (b,) in v.execute("SELECT DISTINCT benutzer FROM wunsch WHERE benutzer LIKE 'abs:%' "
                              "UNION SELECT benutzer FROM geraet UNION SELECT benutzer FROM reihe"):
            aufgaben.append(("entdecken", b))
    try:
        oben = [k["id"] for k in kategorien()]
    except Exception:
        oben = []
    gefragt = [k[0] for k in STOEBERN_CACHE]
    for kid in dict.fromkeys(oben + gefragt):
        for sortierung in ("beliebt", "neu"):
            aufgaben.append(("stoebern", f"{kid}|{sortierung}"))
    for art, ziel in aufgaben:
        name = f"{art}:{ziel}"
        if name in VORRECHNEN["erledigt"]:
            continue
        if not leerlauf():
            log(f"Vorrechnen unterbrochen ({LEERLAUF['grund']}), {len(VORRECHNEN['erledigt'])} erledigt")
            vorrat_speichern()
            return
        try:
            if art == "kategorien":
                KATEGORIEN["zeit"] = 0
                kategorien()
            elif art == "entdecken":
                entdecken_neu_berechnen(ziel)
            else:
                kid, sortierung = ziel.split("|", 1)
                stoebern_zwischengespeichert(kid, sortierung, neu=True)
        except Exception as f:
            log(f"Vorrechnen {name} fehlgeschlagen:", f)
        VORRECHNEN["erledigt"].append(name)
        time.sleep(2)
    VORRECHNEN["fertig"] = True
    vorrat_speichern()
    log(f"Vorrechnen fertig: {len(aufgaben)} Aufgaben")


WECKER = threading.Event()


def arbeiter():
    while True:
        try:
            arbeite_einmal()
        except Exception:
            log("Arbeitslauf fehlgeschlagen:", traceback.format_exc())
        try:
            reihen_pruefen()
        except Exception:
            log("Reihen-Prüfung fehlgeschlagen:", traceback.format_exc())
        try:
            musik_arbeiten()
        except Exception:
            log("Musik-Wünsche fehlgeschlagen:", traceback.format_exc())
        try:
            vorrechnen()
        except Exception:
            log("Vorrechnen fehlgeschlagen:", traceback.format_exc())
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
        pfad = urllib.parse.urlsplit(self.path).path
        if pfad != "/status":  # kurzes Zugriffsprotokoll ohne Token und ohne Abfrageparameter außer neu
            neu = "?neu=1" if "neu=1" in self.path else ""
            dauer = time.time() - getattr(self, "_start", time.time())
            mehr = ""
            if isinstance(daten, dict):
                for k in ("treffer", "wuensche", "reihen", "kategorien"):
                    if k in daten:
                        mehr = f" {len(daten[k])} {k}"
                if "fehler" in daten:
                    mehr = " " + daten["fehler"]
            log(f"{self.command} {pfad}{neu} {code}{mehr} {dauer:.1f}s {self.absender()}")
        self.send_response(code)
        if daten is not None:
            self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(koerper)))
        self.end_headers()
        self.wfile.write(koerper)

    def fehler(self, code, schluessel, text, **extra):
        self.antworte(code, {"fehler": schluessel, "text": text, **extra})

    def absender(self):
        ip = self.client_address[0]
        if ip in E.proxys:
            weiter = self.headers.get("X-Real-IP") or \
                (self.headers.get("X-Forwarded-For") or "").split(",")[-1].strip()
            ip = weiter or ip
        return ip

    def benutzer(self):
        ip = self.absender()
        if gesperrt(ip):
            self.fehler(429, "zu_viele_versuche", "Zu viele Fehlversuche, bitte später erneut versuchen")
            return None
        kopf = self.headers.get("Authorization", "")
        name = benutzer_zu_token(kopf[7:].strip()) if kopf.startswith("Bearer ") else None
        if not name and self.headers.get("X-Subsonic-U"):
            name = navidrome_benutzer(self.headers.get("X-Subsonic-U"), self.headers.get("X-Subsonic-T"),
                                      self.headers.get("X-Subsonic-S"))
        if not name:
            fehlversuch(ip)
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

    def handle_one_request(self):
        self._start = time.time()
        super().handle_one_request()

    def do_GET(self):
        teile, abfrage = self.pfad()
        if teile == ["status"]:
            return self.antworte(200, {"ok": True, "version": VERSION})
        if teile[:1] == ["musik"]:
            name = self.benutzer()
            if not name:
                return
            return self.musik_get(teile, abfrage, name)
        if teile in (["kategorien"], ["stoebern"]):
            name = self.benutzer()
            if not name:
                return
            try:
                if teile == ["kategorien"]:
                    return self.antworte(200, {"kategorien": kategorien()})
                kid = abfrage.get("kategorie", [""])[0]
                sortierung = abfrage.get("sortierung", ["beliebt"])[0]
                if sortierung not in ("beliebt", "neu") or not re.fullmatch(r"[a-z0-9]{1,20}", kid):
                    return self.fehler(400, "ungueltig", "kategorie und sortierung (beliebt|neu) nötig")
                neu = abfrage.get("neu", [""])[0] in ("1", "true")
                t = stoebern_zwischengespeichert(kid, sortierung, neu)
                if t is None:
                    return self.fehler(404, "unbekannt", "Diese Kategorie gibt es nicht")
                return self.antworte(200, {"treffer": t})
            except Exception:
                log("Stöbern fehlgeschlagen:", traceback.format_exc())
                return self.fehler(502, "audible_nicht_erreichbar", "Audible ist gerade nicht erreichbar")
        if teile == ["entdecken"]:
            name = self.benutzer()
            if not name:
                return
            neu = abfrage.get("neu", [""])[0] in ("1", "true")
            try:
                return self.antworte(200, {"treffer": entdecken_zwischengespeichert(name, neu)})
            except Exception:
                log("Entdecken fehlgeschlagen:", traceback.format_exc())
                return self.fehler(502, "audible_nicht_erreichbar", "Vorschläge gerade nicht abrufbar")
        if teile == ["reihe"]:
            name = self.benutzer()
            if not name:
                return
            with db() as v:
                reihen = v.execute("SELECT * FROM reihe WHERE benutzer=? AND zurueckgezogen=0 "
                                   "ORDER BY erstellt DESC", (name,)).fetchall()
                return self.antworte(200, {"reihen": [reihe_json(v, r) for r in reihen]})
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
        if teile == ["reihe"]:
            return self.reihe_folgen(name)
        if teile[:1] == ["musik"]:
            try:
                d = self.koerper()
            except (ValueError, json.JSONDecodeError):
                return self.fehler(400, "ungueltig", "Kein gültiges JSON-Objekt")
            try:
                if teile == ["musik", "wunsch"]:
                    code, daten = musik_wunsch_anlegen(name, d)
                elif teile == ["musik", "folgen"]:
                    code, daten = musik_folgen(name, d, True)
                else:
                    return self.fehler(404, "unbekannt", "Diesen Pfad gibt es nicht")
            except Exception:
                log("Musik fehlgeschlagen:", traceback.format_exc())
                return self.fehler(502, "lidarr_nicht_erreichbar", "Lidarr ist gerade nicht erreichbar")
            return self.antworte(code, daten)
        if teile == ["geraet"]:
            try:
                d = self.koerper()
            except (ValueError, json.JSONDecodeError):
                return self.fehler(400, "ungueltig", "Kein gültiges JSON-Objekt")
            token = str(d.get("apnsToken") or "").strip().lower()
            umgebung = d.get("umgebung") or "produktion"
            if not re.fullmatch(r"[0-9a-f]{32,200}", token) or umgebung not in APNS_HOST:
                return self.fehler(400, "ungueltig", "apnsToken (hex) und umgebung (produktion|sandbox) nötig")
            t = jetzt().isoformat()
            with DB_SPERRE, db() as v:
                v.execute("INSERT INTO geraet VALUES (?,?,?,?,?) ON CONFLICT(token, benutzer) DO UPDATE SET "
                          "umgebung=excluded.umgebung, aktualisiert=excluded.aktualisiert",
                          (token, name, umgebung, t, t))
            return self.antworte(204)
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

    def musik_get(self, teile, abfrage, name):
        q = lambda k: (abfrage.get(k, [""])[0] or "").strip()
        try:
            if teile == ["musik", "suche"]:
                if len(q("q")) < 2:
                    return self.fehler(400, "ungueltig", "q (mindestens 2 Zeichen) nötig")
                alben = musik_suche(q("q")[:200])
                return self.antworte(200, {"alben": alben})
            if teile == ["musik", "kuenstler"]:
                if not q("name") and not q("mbid"):
                    return self.fehler(400, "ungueltig", "name oder mbid nötig")
                d = musik_kuenstler(q("name")[:200], q("mbid").lower() or None)
                if not d:
                    return self.fehler(404, "kein_treffer", "Bei Lidarr nicht gefunden")
                return self.antworte(200, d)
            if teile == ["musik", "neuerscheinungen"]:
                return self.antworte(200, {"alben": musik_neuerscheinungen()})
            if teile == ["musik", "wunsch"]:
                with db() as v:
                    zeilen = v.execute("SELECT * FROM musik_wunsch WHERE benutzer=? AND zurueckgezogen=0 "
                                       "ORDER BY erstellt DESC", (name,)).fetchall()
                return self.antworte(200, {"wuensche": [musik_wunsch_json(z) for z in zeilen]})
        except Exception:
            log("Musik fehlgeschlagen:", traceback.format_exc())
            return self.fehler(502, "lidarr_nicht_erreichbar", "Lidarr bzw. MusicBrainz gerade nicht erreichbar")
        return self.fehler(404, "unbekannt", "Diesen Pfad gibt es nicht")

    def reihe_folgen(self, name):
        try:
            d = self.koerper()
        except (ValueError, json.JSONDecodeError):
            return self.fehler(400, "ungueltig", "Kein gültiges JSON-Objekt")
        asin = str(d.get("asin") or "").strip().upper()
        reihe_name = str(d.get("reihe") or "").strip()[:300]
        sprache = (str(d.get("sprache") or "de").strip().lower() or "de")[:2]
        if not re.fullmatch(r"[A-Z0-9]{10}", asin) or not reihe_name:
            return self.fehler(400, "ungueltig", "reihe und asin (eines Teils) sind Pflicht")
        try:
            reihe_asin, audible_name = reihe_von_asin(asin, reihe_name)
        except Exception as f:
            log("Audible nicht erreichbar:", f)
            return self.fehler(502, "audible_nicht_erreichbar", "Audible ist gerade nicht erreichbar")
        if not reihe_asin:
            return self.fehler(422, "reihe_unbekannt", "Audible kennt zu diesem Hörbuch keine Reihe")
        with DB_SPERRE, db() as v:
            z = v.execute("SELECT * FROM reihe WHERE benutzer=? AND reiheAsin=? AND zurueckgezogen=0",
                          (name, reihe_asin)).fetchone()
            if z:
                return self.antworte(200, reihe_json(v, z))
            rid = "r_" + secrets.token_hex(4)
            v.execute("INSERT INTO reihe (id, benutzer, reiheAsin, reihe, autor, sprache, erstellt) "
                      "VALUES (?,?,?,?,?,?,?)",
                      (rid, name, reihe_asin, audible_name or reihe_name,
                       str(d.get("autor") or "").strip()[:300] or None, sprache, jetzt().isoformat()))
            r_ = v.execute("SELECT * FROM reihe WHERE id=?", (rid,)).fetchone()
        log(f"{rid}: {name} folgt einer Reihe")
        reihe_abgleichen(r_)
        with db() as v:
            r_ = v.execute("SELECT * FROM reihe WHERE id=?", (rid,)).fetchone()
            return self.antworte(201, reihe_json(v, r_))

    def do_DELETE(self):
        teile, _ = self.pfad()
        name = self.benutzer()
        if not name:
            return
        if len(teile) == 3 and teile[:2] == ["musik", "folgen"]:
            try:
                code, daten = musik_folgen(name, {"kuenstlerMbid": teile[2]}, False)
            except Exception:
                log("Musik fehlgeschlagen:", traceback.format_exc())
                return self.fehler(502, "lidarr_nicht_erreichbar", "Lidarr ist gerade nicht erreichbar")
            return self.antworte(code, daten)
        if len(teile) == 3 and teile[:2] == ["musik", "wunsch"]:
            with DB_SPERRE, db() as v:
                z = v.execute("SELECT * FROM musik_wunsch WHERE id=? AND benutzer=? AND zurueckgezogen=0",
                              (teile[2], name)).fetchone()
                if not z:
                    return self.fehler(404, "unbekannt", "Diesen Wunsch gibt es nicht")
                v.execute("UPDATE musik_wunsch SET zurueckgezogen=1, aktualisiert=? WHERE id=?",
                          (jetzt().isoformat(), z["id"]))
                andere = v.execute("SELECT count(*) FROM musik_wunsch WHERE lidarrId=? AND zurueckgezogen=0",
                                   (z["lidarrId"],)).fetchone()[0]
            if z["status"] != "da" and not andere:
                try:  # nur aus der Überwachung nehmen, Dateien bleiben immer liegen
                    lidarr("album/monitor", {"albumIds": [z["lidarrId"]], "monitored": False}, methode="PUT")
                except Exception as f:
                    log(f"{z['id']}: Überwachung nicht beendet:", f)
            log(f"{z['id']}: Musikwunsch zurückgezogen von {name}")
            return self.antworte(204)
        if len(teile) == 2 and teile[0] == "reihe":
            with DB_SPERRE, db() as v:
                v.execute("UPDATE reihe SET zurueckgezogen=1 WHERE id=? AND benutzer=?", (teile[1], name))
            return self.antworte(204)  # bereits angelegte Wünsche bleiben bestehen
        if len(teile) == 2 and teile[0] == "geraet":
            with DB_SPERRE, db() as v:
                v.execute("DELETE FROM geraet WHERE token=? AND benutzer=?", (teile[1].lower(), name))
            return self.antworte(204)
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


FEHLVERSUCHE = {}
FEHL_SPERRE = threading.Lock()
FEHL_GRENZE, FEHL_FENSTER, FEHL_DAUER = 10, 600, 900


def fehlversuch(ip):
    t = time.time()
    with FEHL_SPERRE:
        liste = [x for x in FEHLVERSUCHE.get(ip, []) if x > t - FEHL_FENSTER] + [t]
        FEHLVERSUCHE[ip] = liste
        if len(FEHLVERSUCHE) > 10000:
            FEHLVERSUCHE.clear()
    if len(liste) == FEHL_GRENZE:
        log(f"Fehlversuche: {ip} für {FEHL_DAUER // 60} Minuten gesperrt")


def gesperrt(ip):
    with FEHL_SPERRE:
        liste = FEHLVERSUCHE.get(ip, [])
        return len(liste) >= FEHL_GRENZE and liste[-1] > time.time() - FEHL_DAUER


def bereinigt(text):
    """Keine Server-Details nach außen: Schlüssel, Adressen und Pfade entfernen."""
    text = re.sub(r"(?i)(api_?key|token)=[^&\s'\"]+", r"\1=…", text)
    text = re.sub(r"https?://[^\s'\"]+", "…", text)
    text = re.sub(r"(?<![\w.])/(?:[\w.\- ]+/)+[\w.\- ]*", "…", text)
    return re.sub(r"\b\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?\b", "…", text)


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
    vorrat_laden()
    threading.Thread(target=arbeiter, daemon=True).start()
    threading.Thread(target=entdecken_vorwaermen, daemon=True).start()
    server = ThreadingHTTPServer((E.bind, E.port), Schnittstelle)
    log(f"Hörbuchwunsch {VERSION} hört auf {E.bind}:{E.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
