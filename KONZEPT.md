# Ohrregal – Konzept

**Ohrregal** ist eine App für Musik und Hörbücher von den eigenen Servern, für das **iPhone** und für **Fire TV / Android TV**:

- **Musik** aus **Navidrome** (Subsonic- bzw. OpenSubsonic-API)
- **Hörbücher** aus **Audiobookshelf**

Der Name folgt dem Muster von Quallenkino (Jellyfin → *Jelly* → Qualle): Audiobookshelf → Regal, und für die Ohren ist beides.

Vorbild für Bedienung und Gefühl ist **Apple Music**. Die Optik und Wortwahl passen zu **Quallenkino**.

---

## 1. Grundsätze

1. **Eine App für beides.** Ein Player, ein CarPlay, eine Watch-App. Beide Server sind optional.
2. **Die eigenen Daten bleiben bei dir.** Das Hörverhalten wird auf dem iPhone ausgewertet. Nach außen geht nur das, was Navidrome ohnehin tut (Scrobbling an Last.fm).
3. **Schnell auch bei großen Bibliotheken.** Ziel sind über 50.000 Titel und 10.000 Alben. Daten werden seitenweise geladen und zwischengespeichert, nie die ganze Bibliothek auf einmal.
4. **Zuverlässig vor umfangreich.** Lieber weniger Funktionen, die immer funktionieren.
5. **Minimaler Code.** Systembausteine von Apple statt eigener Nachbauten.

## 2. Feste Pflichten (Lehren aus Subsonify)

| Nr. | Pflicht | Umsetzung |
|---|---|---|
| P1 | **Zurück an dieselbe Stelle.** Nach dem Zurückgehen steht jede Seite genau dort, wo sie war, auch die seitliche Position jeder Reihe. | Ansichten bleiben im `NavigationStack` erhalten, Daten werden nicht neu geladen; Scrollposition je Reihe über `scrollPosition(id:)` gemerkt. |
| P2 | **Antippen trifft das richtige Element.** In seitlich wischenden Reihen öffnet sich genau das angetippte Cover. | Jedes Cover ist ein eigener `Button`/`NavigationLink` mit fester ID; keine Gesten auf der ganzen Reihe. |
| P3 | **Hörbuch-Position geht nie verloren.** Auch offline und auch wenn zwischendurch Musik läuft. | Position wird lokal gespeichert und nachgetragen, sobald der Server erreichbar ist. Musik-Warteschlange und Hörbuch sind getrennt. |
| P4 | **CarPlay funktioniert von Anfang an.** | Gehört zur ersten Version, nicht „später“. |

Für P1, P2 und P3 gibt es automatische Oberflächentests.

## 3. Optik und Wortwahl

**Farben (aus Quallenkino):**

| Rolle | Farbe |
|---|---|
| Hintergrund | `#0b0e14` |
| Fläche (Karten, Leisten) | `#161b24` |
| Fläche hervorgehoben | `#1f2633` |
| Akzent Blau | `#2e96e0` |
| Akzent Violett | `#7f76d6` |
| Text | `#e8eaf0` |
| Text gedämpft | `#a9b1c2` |

Verläufe laufen von Blau nach Violett, zum Beispiel beim Fortschrittsbalken und beim Knopf „Spiel etwas für mich“.

**Aufbau wie Apple Music:**

- großer Titel oben
- Reihen, die seitlich wischen
- Mini-Player über der schwebenden Tab-Leiste
- Vollbild-Player mit Farbverlauf aus dem Cover

**Wortwahl:** Deutsch, „du“, kurz. Beispiele: „Weiterhören“, „Für dich“, „Lange nicht gehört“, „Vor einem Jahr hast du …“, „Spiel etwas für mich“, „Wer hört?“.

## 4. Aufbau der App

**Tabs:** Start · Musik · Hörbücher · Suchen

Ist nur ein Server eingerichtet, fällt der andere Tab weg.

### Start
- **Weiterhören** – angefangene Hörbücher und zuletzt gehörte Musik
- **Für dich** – Mixe (siehe Kapitel 5)
- **Spiel etwas für mich** – großer Knopf, startet sofort einen passenden Mix
- **Radio starten** – endlose Wiedergabe ab zuletzt gehörten Songs
- **Am häufigsten gespielt**, **Lange nicht gehört**, **Neuerscheinungen**, **Kürzlich hinzugefügt**
- **Vor einem Jahr hast du …**

Die Reihenfolge der Reihen hängt von der Tageszeit ab. Leere Reihen werden ausgeblendet.

### Musik
Künstler, Alben, Titel, Genres, Jahre, Playlists, „Gefällt mir“ (Songs, Alben, Künstler), Geladen (offline), Internetradio.

### Hörbücher
Weiterhören, Bibliothek, Serien, Autoren, Sammlungen, Geladen, Fertig gehört.

### Suchen
Eine Suche über beide Server, mit Filtern: Alle · Künstler · Alben · Songs · Playlists · Hörbücher · Autoren.

### Player
- **Mini-Player:** Cover, Titel, AirPlay, Pause, Fortschritt
- **Vollbild bei Musik:** Warteschlange (verschieben, löschen), Zufall, Wiederholen, Songtexte (synchron, falls vorhanden), „Gefällt mir“, „Radio ab diesem Song“
- **Vollbild bei Hörbüchern:** Kapitel, Geschwindigkeit (0,5×–3×), Schlaf-Timer (auch „Ende des Kapitels“), 30 s zurück und vor, Lesezeichen

## 5. Vorschläge (Musik)

Die Grundlage bilden Daten von Navidrome (mit Last.fm-Anbindung) und eine lokale Auswertung auf dem iPhone.

| Reihe / Mix | Quelle |
|---|---|
| Am häufigsten gespielt | `getAlbumList2?type=frequent` |
| Zuletzt gespielt | `getAlbumList2?type=recent` |
| Kürzlich hinzugefügt / Neuerscheinungen | `getAlbumList2?type=newest` bzw. nach Jahr |
| Lange nicht gehört | lokal: früher oft gehört, seit über 60 Tagen nicht mehr |
| Radio ab Song / Künstler | `getSimilarSongs2`, ergänzt durch `getTopSongs` |
| Täglicher Mix | lokal: Top-Künstler der letzten 30 Tage + ähnliche Künstler (`getArtistInfo2`), wechselt täglich |
| Mix pro Künstler / Genre | lokal gewichtet, Grundlage `getSimilarSongs2` und `getSongsByGenre` |
| Geliked-Mix | `getStarred2`, gemischt mit ähnlichen Titeln |
| Vor einem Jahr hast du … | lokaler Hörverlauf |

**Lokale Signale:**

- **Positiv:** Komplett gehört, „Gefällt mir“, mehrfach gehört
- **Negativ:** Übersprungen in den ersten 30 Sekunden
- **Kontext:** Tageszeit und Wochentag

Diese Signale beeinflussen Reihenfolge und Auswahl. Der Hörverlauf liegt nur auf dem Gerät und lässt sich in den Einstellungen löschen.

In Musik-Mixen landen keine Hörbücher.

## 6. Server-Schnittstellen

### Navidrome (OpenSubsonic)
- **Anmeldung:** Token und Salt (`t`, `s`), Passwort im Schlüsselbund
- **Bibliothek:** `getArtists`, `getArtist`, `getAlbum`, `getAlbumList2`, `search3`, `getPlaylists`, `getStarred2`, `getGenres`
- **Wiedergabe:**
  - `stream` (optional mit `maxBitRate`/`format` für mobile Daten)
  - `getCoverArt`
  - `scrobble` (Wiedergabe gestartet und fertig gehört)
- **Zusatz:**
  - `getLyricsBySongId` (OpenSubsonic)
  - `getPlayQueue`/`savePlayQueue` (an anderen Geräten weiterhören)
  - `star`/`unstar`, `getInternetRadioStations`

### Audiobookshelf
- **Anmeldung:** `POST /login`, Token im Schlüsselbund
- **Bibliothek:** `/api/libraries`, `/api/libraries/{id}/items`, `/api/me/items-in-progress`
- **Wiedergabe:** `POST /api/items/{id}/play`, `POST /api/session/{id}/sync`, `POST /api/session/{id}/close`
- **Fortschritt:**
  - `PATCH /api/me/progress/{id}`
  - Offline-Sitzungen über `POST /api/session/local`

## 7. Technik

- **Sprache und Oberfläche:** Swift, SwiftUI
- **Mindestversion:** iOS 17, watchOS 10
- **Wiedergabe:** AVFoundation (`AVQueuePlayer` für lückenlose Wiedergabe), `MPNowPlayingInfoCenter` und `MPRemoteCommandCenter` für Sperrbildschirm, Kopfhörer, CarPlay und Watch
- **Zwischenspeicher:** SwiftData für Bibliothek, Hörverlauf und Offline-Liste; Bilder im Dateisystem-Cache
- **Downloads:** Hintergrund-`URLSession`, optional umgewandelt (z. B. AAC 256 kbit/s)
- **CarPlay:** `CPTemplateApplicationScene` mit Tabs Start · Musik · Hörbücher · Suchen
- **Apple Watch:** Steuerung des iPhones; später eigene Offline-Wiedergabe
- **Keine Fremdbibliotheken**, solange es ohne geht

### Aufteilung im Code

```
Ohrregal/
├── App/                  iPhone-App (SwiftUI)
├── CarPlay/              CarPlay-Szene
├── Watch/                Watch-App
└── Kern/                 Swift-Paket, von allen geteilt
    ├── Server/           NavidromeClient, AudiobookshelfClient
    ├── Wiedergabe/       Player, Warteschlange, Ausgabeziele
    ├── Daten/            SwiftData-Modelle, Zwischenspeicher, Hörverlauf
    ├── Vorschlaege/      Mixe und Reihen
    └── Design/           Farben, Cover-Karte, Reihe, Mini-Player
```

### Ausgabeziele (Grundstein für den Heim-Satelliten)

Die Wiedergabe läuft über ein Protokoll `Ausgabeziel`:

```swift
protocol Ausgabeziel {
    var name: String { get }
    func spiele(_ eintrag: Eintrag, ab: TimeInterval) async throws
    func pause() async
    func weiter() async
    func springe(zu: TimeInterval) async
}
```

Erste Umsetzung: **Dieses iPhone**. AirPlay läuft über das System. Später kommt der **Heim-Satellit** dazu, zum Beispiel Snapcast, Music Assistant oder ein eigener Empfänger auf einem Raspberry Pi oder ESP32, als Ersatz für die HomePods.

## 8. Lidarr – Musik wünschen

Ohrregal zeigt, was in der Bibliothek fehlt, und gibt es mit einem Tipp an **Lidarr** weiter. Das ist dasselbe Prinzip wie die fehlenden Welt-Titel mit Jellyseerr in Quallenkino.

- **Künstlerseite:**
  - Reihe „Fehlt noch“ mit den Alben, die Lidarr kennt, die aber nicht in Navidrome liegen
  - Knopf „Wünschen“ bei jedem Album
- **Für dich – Neue Künstler:** ähnliche Künstler von Last.fm, die noch nicht in der Bibliothek sind; „Künstler hinzufügen“ legt sie in Lidarr an.
- **Neuerscheinungen deiner Künstler:** Lidarr-Kalender, auch mit Alben, die noch nicht erschienen sind
- **Suche:** Wird etwas nicht gefunden, zeigt die Suche „Bei Lidarr suchen“.
- **Status:** Bei gewünschten Alben steht „gewünscht“, „wird geladen“ oder „da“.

**Schnittstellen:**

- `GET /api/v1/artist/lookup`, `GET /api/v1/album/lookup`
- `POST /api/v1/artist` (mit `addOptions.searchForMissingAlbums`), `PUT /api/v1/album/monitor`, `POST /api/v1/command` (`AlbumSearch`)
- `GET /api/v1/calendar`, `GET /api/v1/queue`

**Erreichbarkeit und Sicherheit:**

- Lidarr ist nur im Heimnetz erreichbar und soll das auch bleiben. Die App nutzt Lidarr deshalb nur zu Hause oder über VPN.
- Wünsche von unterwegs landen in einer **Wunschliste** und werden geschickt, sobald Lidarr erreichbar ist.
- Der API-Schlüssel gibt vollen Zugriff auf Lidarr. Er liegt nur im Schlüsselbund und ist nur in den Einstellungen sichtbar. Ohne Schlüssel blendet die App alle Lidarr-Funktionen aus.

## 9. TV-App (Fire TV und Android TV)

Gleicher Name, gleiche Optik, gleiche Tabs, aber für die Fernbedienung gebaut. Gedacht für Fire TV Sticks und Android-TV-Sticks, nicht für Handys.

- **Bedienung mit dem Steuerkreuz:** große Cover, deutlicher Fokusrahmen in Quallen-Blau. P1 und P2 gelten genauso: Fokus und Position bleiben nach dem Zurückgehen erhalten.
- **Start, Musik, Hörbücher, Suchen** wie auf dem iPhone, Suche auch per Sprache, sofern die Fernbedienung das kann
- **Vollbild-Player:** großes Cover, Farbverlauf, Songtext, Bildschirmschoner mit Cover
- **Weiterhören zwischen den Geräten:** Hörbuch-Position über Audiobookshelf, Musik-Warteschlange über `savePlayQueue`/`getPlayQueue`. Was am iPhone läuft, kann am Fernseher weiterlaufen und umgekehrt.
- **Wiedergabe im Hintergrund**, Steuerung über die Fernbedienungstasten
- **Später als Ausgabeziel:** Das iPhone kann den Fernseher als Lautsprecher wählen, wie einen Heim-Satelliten.

**Technik:**

- Kotlin, Jetpack Compose for TV, Media3 (ExoPlayer) mit `MediaSessionService`
- Ab Android 7 (API 24), das deckt alle aktuellen Fire TV Sticks ab
- Gleiche Farben und Wortwahl; die Server-Zugriffe folgen Kapitel 6.
- Liegt im selben Repo im Ordner `TV/`.
- GitHub baut die APK kostenlos. Installation per „Downloader“-App über einen festen Link zur neuesten Version, ohne Entwicklerkonto.

## 10. Fahrplan

| Stufe | Inhalt |
|---|---|
| **1 – Grundversion Musik** | Anmeldung Navidrome, Bibliothek, Suche, Player mit Sperrbildschirm und AirPlay, Startseite mit Server-Reihen, Scrobbling, P1, P2, **CarPlay** |
| **2 – Vorschläge und offline** | lokaler Hörverlauf, Mixe, „Spiel etwas für mich“, Radio, Downloads, Songtexte, Weiterhören an anderen Geräten |
| **2b – Lidarr** | Fehlende Alben, neue Künstler, Wunschliste |
| **3 – Hörbücher** | Audiobookshelf, Hörbuch-Player, P3, Offline-Fortschritt, Hörbücher in CarPlay |
| **4 – Apple Watch** | Steuerung, danach eigene Offline-Wiedergabe |
| **TV-App (parallel ab Stufe 1)** | Fire TV / Android TV mit Musik und Hörbüchern, Weiterhören zwischen den Geräten |
| **6 – Heim-Satellit** | weitere Ausgabeziele, Raumauswahl |
| **später** | Widgets, Siri-Kurzbefehle, Equalizer, Crossfade, „Wer hört?“ |

## 11. Voraussetzungen

- Mac mit aktuellem Xcode zum Bauen
- Apple-Entwicklerkonto (vorhanden; für Gerät, TestFlight, CarPlay)
- **CarPlay-Freigabe** (Audio) bei Apple beantragen, möglichst früh
- Für die TV-App: nichts Zusätzliches; GitHub baut die APK. Amazon- und Google-Play-Entwicklerkonto sind vorhanden, falls die App später in die Stores soll.
- Optional: Lidarr-API-Schlüssel
- Navidrome mit Last.fm-Anbindung, optional Audiobookshelf
