# Hörbuchwunsch – API v1

Ein kleiner Dienst im Media-Stack. Er nimmt Hörbuch-Wünsche aus Ohrregal an, sucht sie über Prowlarr, lädt sie mit SABnzbd und sortiert sie in Audiobookshelf ein. Den Ablauf beschreibt `KONZEPT.md`, Kapitel 9.

Stand: 08.11.2026, Dienst-Version 1.3.0. Die Beschreibung kommt aus der Server-Sitzung „Heimnetz“.

## Grundsätzliches

- **Basis-URL:** Der Dienst liegt hinter demselben Reverse-Proxy wie Audiobookshelf, unter dem Pfad `/wunsch-api`: `https://<abs-adresse>/wunsch-api`. Die App kann die Adresse also aus der ABS-Adresse ableiten. Das gilt zu Hause wie unterwegs. Direkt im Heimnetz geht auch `http://<server>:8097`.
- **Auth:** `Authorization: Bearer <ABS-Token>`, also dasselbe Token, mit dem die App bei Audiobookshelf angemeldet ist. Der Dienst prüft es über `GET <ABS>/api/me` und speichert das Ergebnis 5 Minuten zwischen. Benutzer der Wunschliste ist der ABS-Benutzer (`abs:<ABS-Benutzer-ID>`). Wünschen dürfen nur aktive, nicht gesperrte ABS-Benutzer mit Zugriff auf die Hörbuch-Bibliothek. Ist das Token ungültig oder abgelaufen (ABS-Access-Tokens gelten standardmäßig 1 Stunde), kommt `401`. Die App holt dann bei ABS ein neues Token und versucht es noch einmal. Für Skripte kann der Server zusätzlich eigene Tokens ausgeben (`token-neu`, siehe README).
- **Fehlversuche:** Nach 10 abgelehnten Anmeldungen in 10 Minuten antwortet der Dienst derselben IP 15 Minuten lang mit `429 zu_viele_versuche`. Die App sollte nach einem 401 also nur einmal mit frischem ABS-Token neu versuchen und nicht in einer Schleife.
- **hinweis-Texte** sind für die Anzeige gedacht. Adressen, Pfade und Schlüssel sind daraus entfernt.
- **Format:** JSON (UTF-8), Zeiten im Format ISO 8601 mit Zeitzone.
- **Fehler:** `{"fehler": "<schluessel>", "text": "<deutscher Klartext>"}`
- **`GET /status`** (ohne Auth) liefert `{"ok": true, "version": "1.3.0"}`. Gedacht für „Verbindung testen“.

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
Speichert das Gerät für den angemeldeten Benutzer. Ein Benutzer kann mehrere Geräte haben. Ein erneuter Aufruf mit demselben Token aktualisiert den Eintrag, auch wenn das Gerät jetzt einem anderen Benutzer gehört. TestFlight und App Store melden sich mit `produktion` an, Debug-Builds aus Xcode mit `sandbox`. Bei ungültigem Body kommt `400 ungueltig`.

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

## Reihen folgen (Version 2, noch nicht verfügbar)

Bis dahin antworten diese Endpunkte mit `501 noch_nicht`.

- `POST /reihe` mit `{reihe, autor, asin (eines Teils), sprache}` liefert `201 {"id": "r_…", "reihe": …, "autor": …, "erstellt": …}`. Der Server prüft dann täglich, ob es bei Audible neue Teile gibt, und legt sie als Wunsch an.
- `GET /reihe` liefert `{"reihen": […]}`.
- `DELETE /reihe/{id}` liefert `204`.

## Bewertung der Treffer (Server)

Gesucht wird in Prowlarr in der Hörbuch-Kategorie mit „Autor Titel“. Findet das nichts, probiert der Server Varianten, z. B. ohne Untertitel oder mit Reihe und Teil.

- Titel und Autor müssen passen. Bei Reihen muss auch die Teilnummer stimmen.
- „Ungekürzt“ geht vor. Eine gekürzte Fassung nimmt der Server nur notfalls und schreibt dann einen Hinweis.
- Hörspiele, Kinderfassungen und Lesungen werden nicht verwechselt, es sei denn, der Wunsch legt sie nahe.
- Die Größe muss zur Laufzeit passen (MP3/M4B etwa 0,3–2 MB pro Minute).
- Bei `sprache=de` muss die Fassung deutsch sein.
- Ein Sammelpaket mit mehreren Teilen nimmt der Server nur, wenn es kein Einzelpaket gibt.

Danach lädt SABnzbd. Der Server legt die Dateien als `Autor/Reihe/Titel` ab, lässt Audiobookshelf neu einlesen und ordnet das Hörbuch per ASIN zu. Dann setzt er den Status `da` und schickt eine Push-Nachricht über ntfy.
