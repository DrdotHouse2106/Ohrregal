# Hörbuchwunsch – API v1

Ein kleiner Dienst im Media-Stack. Er nimmt Hörbuch-Wünsche aus Ohrregal an, sucht sie über Prowlarr, lädt sie mit SABnzbd und sortiert sie in Audiobookshelf ein. Den Ablauf beschreibt `KONZEPT.md`, Kapitel 9.

Stand: 08.11.2026, Dienst-Version 2.5.1. Die Beschreibung kommt aus der Server-Sitzung „Heimnetz“.

## Grundsätzliches

- **Basis-URL:** Der Dienst liegt hinter demselben Reverse-Proxy wie Audiobookshelf, unter dem Pfad `/wunsch-api`: `https://<abs-adresse>/wunsch-api`. Die App kann die Adresse also aus der ABS-Adresse ableiten. Das gilt zu Hause wie unterwegs. Direkt im Heimnetz geht auch `http://<server>:8097`.
- **Auth:** `Authorization: Bearer <ABS-Token>`, also dasselbe Token, mit dem die App bei Audiobookshelf angemeldet ist. Der Dienst prüft es über `GET <ABS>/api/me` und speichert das Ergebnis 5 Minuten zwischen. Benutzer der Wunschliste ist der ABS-Benutzer (`abs:<ABS-Benutzer-ID>`). Wünschen dürfen nur aktive, nicht gesperrte ABS-Benutzer mit Zugriff auf die Hörbuch-Bibliothek. Ist das Token ungültig oder abgelaufen (ABS-Access-Tokens gelten standardmäßig 1 Stunde), kommt `401`. Die App holt dann bei ABS ein neues Token und versucht es noch einmal. Für Skripte kann der Server zusätzlich eigene Tokens ausgeben (`token-neu`, siehe README).
- **Fehlversuche:** Nach 10 abgelehnten Anmeldungen in 10 Minuten antwortet der Dienst derselben IP 15 Minuten lang mit `429 zu_viele_versuche`. Die App sollte nach einem 401 also nur einmal mit frischem ABS-Token neu versuchen und nicht in einer Schleife.
- **hinweis-Texte** sind für die Anzeige gedacht. Adressen, Pfade und Schlüssel sind daraus entfernt.
- **Format:** JSON (UTF-8), Zeiten im Format ISO 8601 mit Zeitzone.
- **Fehler:** `{"fehler": "<schluessel>", "text": "<deutscher Klartext>"}`
- **`GET /status`** (ohne Auth) liefert `{"ok": true, "version": "2.5.1"}`. Gedacht für „Verbindung testen“.

## Wunsch-Objekt

```json
{
  "id": "w_8f3a1c",
  "asin": "B0D…",
  "titel": "…",
  "autor": "…",
  "sprecher": "…",
  "reihe": "…",
  "teil": "3",
  "laufzeitMin": 612,
  "sprache": "de",
  "coverUrl": "https://…",
  "status": "gewuenscht",
  "hinweis": "Nur gekürzte Fassung gefunden",
  "fortschritt": 42,
  "absItemId": "li_…",
  "erstellt": "…",
  "aktualisiert": "…",
  "naechsterVersuch": "…",
  "versuche": 3
}
```

- `id` und `teil` sind Strings (`teil` z. B. `"1.5"`).
- `hinweis` ist optional.
- `fortschritt` (0–100) gibt es nur bei `laedt`.
- `absItemId` gibt es nur bei `da`. Damit öffnet die App das Hörbuch direkt in Audiobookshelf.
- `naechsterVersuch` gibt es nur bei `nicht_gefunden`.

### Status

| Wert | Bedeutung |
|---|---|
| `gewuenscht` | angenommen, die Suche startet gleich |
| `nicht_gefunden` | wird täglich neu versucht, Grund steht in `hinweis` |
| `laedt` | SABnzbd lädt, siehe `fortschritt` |
| `einsortieren` | wird abgelegt und in Audiobookshelf eingelesen |
| `da` | liegt in Audiobookshelf, siehe `absItemId` |
| `fehler` | z. B. Download kaputt; `hinweis` gefüllt, beim nächsten Lauf mit anderer Fassung erneut |

## Endpunkte

### `POST /wunsch`

Body: `asin`, `titel`, `autor`, `sprecher`, `reihe`, `teil`, `laufzeitMin`, `sprache`, `coverUrl`. Pflicht sind `titel` und `autor`, `asin` ist dringend empfohlen.

| Antwort | Bedeutung |
|---|---|
| `201` | neuer Wunsch, Body = Wunsch-Objekt |
| `200` | dieselbe ASIN ist schon gewünscht (auch von anderem Benutzer); bestehender Wunsch zurück, kein doppelter Download |
| `409 schon_vorhanden` | liegt schon in Audiobookshelf, mit `absItemId`. Der Server prüft das selbst, der Abgleich in der App ist nur die Vorschau. |
| `400 ungueltig` | Pflichtfelder fehlen |

### `GET /wunsch`

Liefert `{"wuensche": […]}`, nur die Wünsche des eigenen Benutzers, neueste zuerst. Mit dem optionalen Filter `?status=laedt,einsortieren` lassen sie sich eingrenzen. Solange die Liste offen ist, fragt die App alle 10–30 Sekunden neu ab.

### `GET /wunsch/{id}`

Liefert einen einzelnen Wunsch, bei unbekannter id `404`.

### `DELETE /wunsch/{id}`

Liefert `204` und zieht den Wunsch zurück. Ein laufender Download wird abgebrochen.
**Bei Status `da` wird nur der Listeneintrag entfernt, die Datei bleibt.** Aus den Medien wird nie gelöscht. Der Bestätigungstext in der App muss das deutlich sagen.

### `POST /wunsch/{id}/erneut`

Liefert `202` und startet bei `nicht_gefunden` oder `fehler` sofort eine neue Suche.

## Push-Nachrichten (ab 1.3.0)

### `POST /geraet`
Body: `{"apnsToken": "<hex>", "umgebung": "produktion" | "sandbox"}`. Antwort: `204`.
Speichert das Gerät für den angemeldeten Benutzer. Ab 2.4.1 kann dasselbe Gerät zu mehreren Anmeldungen gehören: Wer ABS und Navidrome nutzt, meldet das Gerät **mit beiden** an, einmal mit ABS-Token und einmal mit den X-Subsonic-Kopfzeilen. Hörbuch-Nachrichten gehen an `abs:…`, Musik-Nachrichten an `nd:…`, und jede Nachricht kommt nur einmal. `DELETE` meldet das Gerät nur für die jeweilige Anmeldung ab. Ein Benutzer kann mehrere Geräte haben. Ein erneuter Aufruf mit demselben Token aktualisiert den Eintrag, auch wenn das Gerät jetzt einem anderen Benutzer gehört. TestFlight und App Store melden sich mit `produktion` an, Debug-Builds aus Xcode mit `sandbox`. Bei ungültigem Body kommt `400 ungueltig`.

### `DELETE /geraet/{apnsToken}`
Antwort: `204`. Meldet das Gerät des angemeldeten Benutzers ab.

### Was der Server schickt
- Status `da`: Titel „Hörbuch ist da“, Text „<Titel> – <Autor>“
- erstes `nicht_gefunden` eines Wunsches: Titel „Hörbuch noch nicht gefunden“, Text „<Titel> – sucht weiter“

Nutzlast:
```json
{"aps": {"alert": {"title": "…", "body": "…"}, "sound": "default"}, "wunschId": "w_…", "absItemId": "…"}
```
`absItemId` ist nur dabei, wenn das Buch schon in ABS steht. Benachrichtigt werden alle Benutzer, die den Wunsch haben. Antwortet APNs mit `410`, `BadDeviceToken`, `Unregistered` oder `DeviceTokenNotForTopic`, löscht der Server das Gerät.

## Reihen folgen (ab 2.0.0)

### `POST /reihe`
Body: `{"reihe": "<Name>", "autor": "<Autor>", "asin": "<ASIN eines Teils>", "sprache": "de"}`. Pflicht sind `reihe` und `asin`.
- Der Server sucht über den Audible-Katalog die Reihe zu dieser ASIN. Hat der Teil mehrere Reihen, nimmt er die mit passendem Namen.
- Er legt sofort alle **schon erschienenen** Teile mit Nummer und in der gewünschten Sprache als Wünsche an. Pro Nummer nimmt er eine Fassung, „ungekürzt“ vor „gekürzt“. Sammelboxen wie „1-3“ lässt er aus.
- Teile, die schon in ABS liegen, werden übersprungen. Ist ein Teil schon gewünscht, auch von jemand anderem, kommt der Benutzer als Interessent dazu. Doppelt geladen wird nichts.
- Danach prüft der Server die Reihe alle 24 Stunden und wünscht neu erschienene Teile automatisch. Vorbestellungen kommen erst ab dem Erscheinungstag dazu.
- Für Teile aus einer Reihe gibt es keine Push-Nachricht „noch nicht gefunden“. „Hörbuch ist da“ kommt wie gewohnt.

Antworten:
- `201` Reihen-Objekt (siehe unten)
- `200` der Benutzer folgt der Reihe schon, bestehendes Objekt
- `400 ungueltig` bei fehlender oder ungültiger ASIN bzw. Reihe
- `422 reihe_unbekannt`, wenn Audible zu dieser ASIN keine Reihe kennt
- `502 audible_nicht_erreichbar`

### `GET /reihe`
Liefert `{"reihen": [ … ]}`, nur die des eigenen Benutzers, neueste zuerst.

### `DELETE /reihe/{id}`
Antwort: `204`. Der Benutzer folgt der Reihe nicht mehr. Schon angelegte Wünsche bleiben bestehen und lassen sich einzeln zurückziehen.

### Reihen-Objekt
```json
{"id": "r_1a2b3c4d", "reihe": "<Name laut Audible>", "autor": "…", "sprache": "de",
 "erstellt": "…", "geprueft": "…",
 "teileGesamt": 5, "teileDa": 4, "teileGewuenscht": 1,
 "hinweis": "…"}
```
- `teileGesamt`: erschienene Teile in dieser Sprache
- `teileDa`: in ABS vorhanden oder Wunsch mit Status `da`
- `teileGewuenscht`: Wunsch offen, also noch nicht `da`
- `hinweis` ist optional, z. B. „Keine erschienenen Teile in dieser Sprache gefunden“
- Die Wünsche aus einer Reihe erscheinen ganz normal in `GET /wunsch`, mit `reihe` und `teil`.

## Entdecken (ab 2.1.0)

### `GET /entdecken`
Liefert `{"treffer": [ … ]}` mit höchstens 30 Vorschlägen, die besten zuerst. Mit `?neu=1` wird der Zwischenspeicher übergangen, sonst gilt er 6 Stunden je Benutzer. Abgelaufene Vorschläge liefert der Server sofort aus und erneuert sie im Hintergrund. Nach einem Neustart berechnet er sie für bekannte Benutzer vorab. Antworten dauern deshalb nur beim allerersten Aufruf bzw. mit `neu=1` mehrere Sekunden (bis etwa 10 s). Bitte einen Timeout von mindestens 30 s verwenden.

So entstehen die Vorschläge:
- **Grundlage** ist der ABS-Hörverlauf des Benutzers. Als gehört markierte oder ganz gehörte Bücher (isFinished) zählen zuerst, auch ohne Hördauer, ab 2.5.1. Wird ein Buch in ABS wieder als ungehört markiert, zählt es nicht mehr als fertig. Mit Navidrome-Anmeldung nimmt der Server den ABS-Benutzer, der auf demselben Gerät angemeldet ist (über /geraet). Der Rest dieses Punkts:, gelesen aus der ABS-Datenbank: Bücher, die fertig gehört oder mindestens 10 Minuten angehört wurden, die neuesten zuerst. Ohne Verlauf nimmt der Server die zuletzt in die Bibliothek gekommenen Bücher.
- **Kandidaten:** Audible-„Ähnliche Titel“ (sims) zu den bis zu 6 zuletzt gehörten Büchern, dazu die Bestseller der 2 häufigsten Audible-Kategorien darunter.
- **Ausgefiltert** wird alles, was nicht deutsch oder noch nicht erschienen ist, Sammelboxen, Titel, die schon in ABS liegen (auch nicht zugeordnete, erkannt über Ordnernamen) oder schon gewünscht sind, und doppelte Fassungen desselben Titels. Pro Autor gibt es höchstens 3 Vorschläge.

Ein Treffer hat dieselben Felder wie bei ABS `/api/search/books` (Audible), dazu `grund`:
```json
{"title": "…", "subtitle": "…", "author": "…", "narrator": "…", "cover": "https://…", "asin": "…",
 "language": "German", "duration": 457, "series": [{"series": "…", "sequence": "1"}],
 "description": "<Klartext ohne HTML>", "publishedYear": "2015", "publisher": "…",
 "grund": "Weil du „<Titel>“ gehört hast"}
```
Mögliche `grund`-Texte: „Weil du „<Titel>“ gehört hast“, „Weil du <Autor> hörst“ (ab 2 gehörten Büchern eines Autors), „Beliebt in <Kategorie>“ und „Passt zu deiner Bibliothek: <Titel>“, wenn es keinen Hörverlauf gibt. Bei gekürzten Fassungen steht „(gekürzte Fassung)“ dahinter.
Fehler: `502 audible_nicht_erreichbar`. Eine leere Liste bedeutet, dass es nichts Passendes gibt.

## Stöbern nach Kategorie (ab 2.2.0)

### `GET /kategorien`
Liefert `{"kategorien": [{"id": "…", "name": "…", "unter": [{"id": "…", "name": "…"}]}]}` mit den obersten zwei Ebenen des Audible-Katalogs, alphabetisch sortiert und 3 Tage zwischengespeichert. Ganz vorne steht immer die Pseudo-Kategorie `{"id": "hoerspiele", "name": "Hörspiele", "unter": []}`. Audible hat keine eigene Hörspiel-Kategorie, deshalb sucht der Server dafür nach „Hörspiel“ und behält nur Titel, die Audible als Hörspiel führt.

### `GET /stoebern?kategorie=<id>&sortierung=beliebt|neu[&neu=1]`
Liefert `{"treffer": [ … ]}` mit höchstens 30 Treffern, Format wie bei `/entdecken`. Der grund lautet „Bestseller in <Kategorie>“ bzw. „Neu in <Kategorie>“. Es kommen nur deutsche, schon erschienene Titel, keine Sammelboxen, keine Erotik außerhalb der Kategorie Erotik. Was in ABS liegt oder gewünscht ist, fällt raus. Zwischengespeichert wird 6 Stunden je Kategorie und Sortierung, `neu=1` umgeht den Zwischenspeicher.
Fehler: `400 ungueltig`, `404 unbekannt` (Kategorie gibt es nicht), `502 audible_nicht_erreichbar`.
Hinweis: „neu“ braucht beim ersten Aufruf bis zu 5 Sekunden, weil Audible zuerst Vorbestellungen liefert.

## Musik wünschen über Lidarr (ab 2.4.0)

Lidarr bleibt im Heimnetz, sein Schlüssel bleibt auf dem Server.

**Auth** wahlweise wie bisher mit ABS-Token oder mit der Navidrome-Anmeldung: Kopfzeilen `X-Subsonic-U`, `X-Subsonic-T`, `X-Subsonic-S` (Token = md5(Passwort+Salt)). Der Dienst prüft sie mit `/rest/ping` bei Navidrome und speichert das 5 Minuten zwischen. Benutzer ist dann `nd:<name>`. Beide Wege gelten für alle Endpunkte, auch `/geraet`. Erreichbar ist der Dienst unter jeder Domain mit `/wunsch-api`-Weiterleitung.

**Regeln:** Es gibt nur Alben und Singles ohne Sekundärtypen (keine EPs, Live-Alben, Compilations oder Remixe). Ein neuer Künstler wird ohne Diskografie angelegt (`monitor none`, `monitorNewItems none`). Überwacht wird nur das gewünschte Album. „Folgen“ bedeutet: nur neue Alben (`monitorNewItems new`).

**Album:**
```json
{"mbid": "<foreignAlbumId>", "titel": "…", "kuenstler": "…", "kuenstlerMbid": "…", "jahr": "2003",
 "typ": "Album" | "Single", "titelAnzahl": 11, "cover": "https://…", "status": "da" | "gewuenscht" | "laedt" | "fehlt"}
```
`gewuenscht` heißt: in Lidarr überwacht, aber noch nicht vollständig. Das gilt auch, wenn das Album schon vor diesem Dienst überwacht war.

- `GET /musik/suche?q=<Text>` liefert `{"alben": [Album]}` aus Lidarrs album/lookup. Eine leere Liste heißt „Bei Lidarr nicht gefunden“.
- `GET /musik/kuenstler?name=<Name>[&mbid=<mbid>]` liefert `{"kuenstler": {name, mbid, folgt, inLidarr}, "alben": [Album]}`, neueste zuerst. Ist der Künstler in Lidarr, kommen die Alben mit Stand aus Lidarr. Sonst kommen sie von MusicBrainz, dann alle mit Status `fehlt`/`gewuenscht` und ohne titelAnzahl. Unbekannter Künstler: `404 kein_treffer`.
- `POST /musik/wunsch` mit `{mbid, kuenstlerMbid?, titel?, kuenstler?}` liefert `201` Musikwunsch, `200` (schon gewünscht), `409 schon_vorhanden`, `404 kein_treffer` oder `400 ungueltig`. Ist der Künstler neu, kann die Antwort bis zu 60 s dauern, weil Lidarr erst seine Alben lädt.
- `GET /musik/wunsch` liefert `{"wuensche": [{id, mbid, titel, kuenstler, cover, status, hinweis?, erstellt, aktualisiert}]}`. Die Status sind dieselben wie bei Hörbüchern. `nicht_gefunden` heißt: 30 Minuten nach der Suche gab es keinen Download, nachts wird neu gesucht.
- `DELETE /musik/wunsch/{id}` liefert `204`. Wollen keine anderen Benutzer das Album, nimmt der Dienst es aus der Überwachung. Dateien werden nie gelöscht.
- `POST /musik/folgen` mit `{kuenstlerMbid, name?}` liefert `201 {"kuenstlerMbid", "folgt": true}`. `DELETE /musik/folgen/{kuenstlerMbid}` liefert `204`.
- `GET /musik/neuerscheinungen` liefert `{"alben": [Album + "erscheint": "JJJJ-MM-TT"]}`: Alben und Singles verfolgter Künstler, 30 Tage zurück und 90 Tage voraus, nach Datum sortiert.
- Push: „Album ist da“ mit Text „<Titel> – <Künstler>“ und den Zusatzfeldern `musikWunschId` und `mbid`.
- Fehler bei Störungen: `502 lidarr_nicht_erreichbar`.
- Gesucht werden höchstens 3 Alben pro Minute.

## Hörprotokoll (ab 2.5.0)

Das Hörprotokoll wird je Benutzer getrennt gespeichert und dient nur dazu, Vorschläge zuzuschneiden. Es liegt in der Datenbank des Dienstes, verlässt das Haus nicht und wird an niemanden weitergegeben. Jeder Benutzer sieht und löscht nur sein eigenes Protokoll.

### `POST /ereignisse`
Body: `{"ereignisse": [Ereignis]}`, höchstens 200 pro Aufruf, alte zuerst. Antwort: `204`. Der ganze Body darf höchstens **100 KB** groß sein, das ist die Grenze des Reverse-Proxys. Bei langen Texten also weniger Ereignisse pro Aufruf schicken. Doppelte Ereignisse (gleiche `uid`) werden ignoriert, erneutes Senden ist also gefahrlos. Ist auch nur ein Ereignis ungültig, kommt `400 ungueltig` und es wird nichts gespeichert. Der Text nennt die uid.

Ereignis:
```json
{"uid": "…", "typ": "start", "zeit": "2026-11-09T08:00:00+01:00", "art": "musik" | "hoerbuch",
 "id": "…", "titel": "…", "kuenstler": "…", "kuenstlerId": "…", "albumId": "…",
 "position": 40, "dauer": 200, "wert": "…", "quelle": "…", "geraet": "iPhone", "ausgabe": "Kopfhörer"}
```
Pflicht sind `uid`, `typ` und `zeit`. Erlaubte `typ`: start, ende, uebersprungen, gespult, pause, gefaellt, gefaellt_nicht, playlist, als_naechstes, warteschlange, radio, suche, tempo, schlaftimer, hoerbuch_fertig, hoerbuch_abgebrochen, hoerbuch_ungehoert (ab 2.5.1). Textfelder werden nach 300 Zeichen abgeschnitten.

### `GET /ereignisse?von=&bis=&limit=`
Liefert `{"ereignisse": [ … ], "gesamt": <Anzahl insgesamt>}`, neueste zuerst. `von`/`bis` als ISO-Datum, `limit` 1–5000, Standard 500. Zeiten kommen in UTC zurück.

### `DELETE /ereignisse[?bis=]`
Antwort: `204`. Ohne `bis` wird das ganze Protokoll des Benutzers gelöscht, mit `bis` alles bis zu diesem Zeitpunkt.

Hinweis: Ereignisse mit X-Subsonic-Anmeldung landen bei `nd:<name>`, mit ABS-Token bei `abs:<id>`. Die App sollte für beide Arten dieselbe Anmeldung verwenden (X-Subsonic, wenn vorhanden), sonst ist das Protokoll auf zwei Benutzer verteilt.

Das Profil (`GET /profil`), die Nutzung in `/entdecken`, `/musik/fuerdich` und der Status „abgebrochen nach 30 Tagen“ kommen in einer späteren Version.

## Ruhezeiten und Vorrat (ab 2.3.0)

Der Server rechnet nur, wenn es nicht stört, und liefert sonst aus seinem Vorrat aus:
- **Nachtfenster** 3–6 Uhr (einstellbar). Dazu muss **Leerlauf** sein: kein laufender, nicht pausierter Jellyfin-Stream, keine Live-TV-Aufnahme, keine ABS-Wiedergabe in den letzten 3 Minuten. Wird gestreamt, unterbricht der Server und macht später weiter.
- **Nachts neu berechnet:** `/kategorien`, `/entdecken` für alle bekannten Benutzer und `/stoebern` (beliebt und neu) für alle Hauptkategorien, „Hörspiele“ und jede Unterkategorie, die die App schon einmal abgefragt hat. Der Vorrat liegt auf der Platte und übersteht Neustarts.
- **Tagsüber:** Vorhandenes wird immer ausgeliefert, egal wie alt. Neu gerechnet wird nur mit `neu=1` oder wenn für diese Abfrage noch nichts da ist.
- **Wünsche:** Neue, ausdrückliche Wünsche werden sofort gesucht und geladen. Teile aus „Reihe folgen“, der tägliche Neuversuch bei `nicht_gefunden` und Neuversuche nach `fehler` laufen nur in der Ruhezeit. „Erneut suchen“ (`POST /wunsch/{id}/erneut`) gilt als ausdrücklich und läuft sofort.
- Die tägliche Prüfung der Reihen läuft ebenfalls nur in der Ruhezeit.

## Bewertung der Treffer (Server)

**Hörspiele (ab 2.2.0):** Ob ein Wunsch ein Hörspiel ist, entscheidet Audible (content_type „Performance“ oder format_type „original_recording“). Ohne ASIN entscheidet „Hörspiel“ im Titel. Bei Hörspielen bevorzugt der Server Hörspiel-Releases, „ungekürzt“ spielt keine Rolle, und Hörspiel-, Lesungs-, Radio- und Kinder-Fassungen werden nicht aussortiert. Folgen von Reihen wie Hörspielserien passen auch nur über Reihenname und Folgennummer, ohne Titel. „???“ und „!!!“ zählen als „Fragezeichen“ bzw. „Ausrufezeichen“. Verlustfreie Releases (FLAC) sind erlaubt, bei gleicher Eignung kommen aber kleinere Fassungen zuerst.

Gesucht wird in Prowlarr in der Hörbuch-Kategorie mit „Autor Titel“. Findet das nichts, probiert der Server Varianten, z. B. ohne Untertitel oder mit Reihe und Teil.

- Titel und Autor müssen passen. Bei Reihen muss auch die Teilnummer stimmen.
- „Ungekürzt“ geht vor. Eine gekürzte Fassung nimmt der Server nur notfalls und schreibt dann einen Hinweis.
- Hörspiele, Kinderfassungen und Lesungen werden nicht verwechselt, es sei denn, der Wunsch legt sie nahe.
- Die Größe muss zur Laufzeit passen (MP3/M4B etwa 0,3–2 MB pro Minute).
- Bei `sprache=de` muss die Fassung deutsch sein.
- Ein Sammelpaket mit mehreren Teilen nimmt der Server nur, wenn es kein Einzelpaket gibt.

Danach lädt SABnzbd. Der Server legt die Dateien als `Autor/Reihe/Titel` ab, lässt Audiobookshelf neu einlesen und ordnet das Hörbuch per ASIN zu. Dann setzt er den Status `da` und schickt eine Push-Nachricht an Ohrregal (siehe „Push-Nachrichten“).
