# Ohrregal einrichten

Diese Anleitung ist für Menschen ohne KI-Hilfe geschrieben. Sie hat drei Teile. Lies nur, was du brauchst:

| Du willst … | Lies |
|---|---|
| die App nur **benutzen**, jemand anderes betreibt die Server | [Teil A](#teil-a--app-benutzen) |
| eigene Server für Musik und Hörbücher **vorbereiten** | [Teil B](#teil-b--server-vorbereiten) |
| die App mit deinem eigenen Apple-Konto **selbst bauen** | [Teil C](#teil-c--eigene-app-bauen) |

English version: [EINRICHTUNG.en.md](EINRICHTUNG.en.md)

---

## Teil A – App benutzen

Ohrregal ist (noch) nicht im App Store. Du bekommst die App über **TestFlight**. Das ist Apples App für Testversionen.

1. Die Person, die Ohrregal betreibt, lädt dich ein. Sie braucht dafür die E-Mail-Adresse deiner **Apple-ID**.
2. Du bekommst zwei E-Mails von Apple:
   - **„App Store Connect“**: einmal annehmen.
   - **„TestFlight“**: kommt danach, oft erst nach einigen Minuten.
3. Installiere die App **TestFlight** aus dem App Store.
4. Öffne die TestFlight-E-Mail auf dem iPhone und tippe auf **„In TestFlight anzeigen“**. Öffnest du sie am Computer, steht dort ein Code. Den gibst du in TestFlight unter **„Einlösen“** ein.
5. Installiere Ohrregal. Schalte in TestFlight bei Ohrregal **„Automatische Updates“** ein.
6. Öffne Ohrregal und trage ein, was du von der betreibenden Person bekommst:
   - **Navidrome** (Musik): Adresse, Benutzername, Passwort. Pflicht.
   - **Audiobookshelf** (Hörbücher): Adresse, Benutzername, Passwort. Optional.
7. Tippe auf **Start → Profil-Symbol oben rechts → „Mitteilungen“** und erlaube Mitteilungen.

Fertig. Später änderst du die Zugänge unter **Profil → „Zugänge“**. Bei Problemen hilft der Abschnitt „Probleme und Lösungen“ in der [README](README.md#probleme-und-lösungen).

---

## Teil B – Server vorbereiten

Ohrregal braucht **keinen eigenen Server**. Die App spricht mit Programmen, die du vielleicht schon betreibst:

| Programm | Wofür | Pflicht? |
|---|---|---|
| [Navidrome](https://www.navidrome.org/docs/installation/) | Musik | **ja** |
| [Audiobookshelf](https://www.audiobookshelf.org/docs#install) | Hörbücher und Hörspiele | nein |
| Last.fm-Anbindung in Navidrome | Mixe, „Radio ab diesem Song“, Autoplay | empfohlen |
| Server-Dienst „Hörbuchwunsch“ ([Dienst/README.md](Dienst/README.md)) | Wünschen, Entdecken, Stöbern, Reihen, Mitteilungen, Hörprotokoll | nein |
| Lidarr | Musik wünschen | nein (nur mit Dienst) |
| Prowlarr und SABnzbd | Hörbücher wünschen | nein (nur mit Dienst) |

### B1 – Navidrome

1. Navidrome installieren (siehe Link oben) und deine Musik einlesen lassen.
2. **Von außen erreichbar machen:** über einen Reverse-Proxy mit HTTPS, z. B. `https://musik.example.de`. Ohne HTTPS funktioniert Ohrregal nur im Heimnetz.
3. **Für jede Person ein eigenes Konto anlegen** (Navidrome → Benutzer). Dann hat jede ihre eigenen Lieblingstitel, Playlists, Mediathek und Vorschläge.
4. **Last.fm einrichten (empfohlen):** In der Navidrome-Konfiguration `LastFM.ApiKey` und `LastFM.Secret` eintragen. Einen API-Schlüssel gibt es kostenlos unter [last.fm/api](https://www.last.fm/api/account/create). Ohne Last.fm gibt es keine ähnlichen Titel. Die Mixe bestehen dann aus Zufallstiteln.
5. **Internetradio (optional):** Sender legst du in der Navidrome-Weboberfläche unter „Radios“ an.
6. **Wichtig:** Nutzt du eine Anmeldung über den Reverse-Proxy (z. B. Authelia), braucht jedes Konto trotzdem ein **eigenes Navidrome-Passwort**. Apps melden sich damit an.

### B2 – Audiobookshelf (optional)

1. Audiobookshelf installieren, eine Bibliothek vom Typ **„Bücher“** anlegen und Hörbücher einlesen lassen.
2. Unter derselben Art Adresse erreichbar machen wie Navidrome, z. B. `https://hoerbuch.example.de`.
3. Für jede Person ein Konto anlegen.
4. Für gute Metadaten unter Einstellungen den Anbieter **„Audible.de“** wählen.

### B3 – Server-Dienst (optional)

Für Wünschen, Entdecken, Stöbern, Reihen folgen, die Mitteilungen „Hörbuch/Album ist da“ und das Hörprotokoll. Ohne den Dienst blendet die App diese Bereiche aus. Die Einrichtung mit **Docker Compose** steht Schritt für Schritt in [Dienst/README.md](Dienst/README.md#einrichtung-mit-docker-empfohlen). Kurz zusammengefasst:

1. `docker-compose.yml` und `beispiel.env` aus `Dienst/` übernehmen, die Werte eintragen (die README sagt, wo man sie findet) und `docker compose up -d` ausführen.
2. Im Reverse-Proxy von Audiobookshelf **und** Navidrome den Pfad `/wunsch-api/` an den Dienst weiterleiten. Ohrregal sucht ihn unter Audiobookshelf-Adresse + `/wunsch-api`. Gibt es kein Audiobookshelf, unter der Navidrome-Adresse.
3. Für Mitteilungen den Apple-Push-Schlüssel (.p8) aus [Teil C, Schritt C4](#c4--push-schlüssel-für-den-dienst) hinterlegen.

---

## Teil C – Eigene App bauen

Nötig, wenn du Ohrregal mit **deinem** Apple-Konto verteilen willst, zum Beispiel für deine Familie. Du brauchst:
- ein **kostenpflichtiges Apple-Entwicklerkonto** (99 € im Jahr)
- ein **GitHub-Konto**. Gebaut wird kostenlos bei GitHub, ein Mac ist nicht nötig.

### C1 – Repository übernehmen

1. Das Repository auf GitHub **forken** (oben rechts „Fork“). Lass es **öffentlich**, sonst kosten die Mac-Rechner bei GitHub Geld.
2. In `project.yml` die Zeile `PRODUCT_BUNDLE_IDENTIFIER: de.drdothouse.Ohrregal` auf deine eigene Kennung ändern, z. B. `de.meinname.Ohrregal`. Das ist die einzige Stelle im Code. Alles andere leitet sich davon ab.

### C2 – Apple: App-ID und App anlegen

Unter [developer.apple.com](https://developer.apple.com/account):

1. **Mitgliedschaft** (Membership details): die **Team-ID** notieren (10 Zeichen).
2. **Certificates, Identifiers & Profiles → Identifiers → „+“ → App IDs → App:**
   - Bundle ID **Explicit** mit deiner Kennung aus C1
   - unter Capabilities **Push Notifications** anhaken
   - unter **App Services** **ShazamKit** anhaken (für „Titel erkennen“)
3. **CarPlay beantragen:** [developer.apple.com/contact/carplay](https://developer.apple.com/contact/carplay/), Kategorie **Audio**. Apple prüft das, und es kann einige Tage dauern. Danach an der App-ID **„CarPlay Audio App“** anhaken.
   - **Bis die Freigabe da ist**, lösche in `App/Ohrregal.entitlements` den Eintrag `com.apple.developer.carplay-audio`. Sonst lehnt Apple das Hochladen ab.

In [App Store Connect](https://appstoreconnect.apple.com/apps): **„+“ → Neue App**, Plattform iOS, deine Bundle-ID, beliebige SKU.

### C3 – GitHub mit Apple verbinden

1. App Store Connect → **Benutzer und Zugriff → Integrationen → App Store Connect API → Team-Schlüssel** → neuen Schlüssel mit Zugriff **„Admin“** anlegen.
   - **Issuer-ID** und **Schlüssel-ID** notieren.
   - Die **.p8-Datei** herunterladen. Das geht nur ein einziges Mal, also sicher aufbewahren.
2. In deinem GitHub-Fork: **Settings → Secrets and variables → Actions → New repository secret**, vier Stück:

| Name | Inhalt |
|---|---|
| `APPLE_TEAM_ID` | Team-ID aus C2 |
| `ASC_ISSUER_ID` | Issuer-ID |
| `ASC_KEY_ID` | Schlüssel-ID |
| `ASC_KEY_P8` | kompletter Inhalt der .p8-Datei, inklusive `-----BEGIN PRIVATE KEY-----` und `-----END PRIVATE KEY-----` |

3. **Actions → TestFlight → Run workflow.** Nach etwa 5 Minuten ist die App bei Apple, nach weiteren 5 bis 15 Minuten in TestFlight. Danach baut jeder Push auf `main` automatisch eine neue Version.

### C4 – Push-Schlüssel für den Dienst

Nur wenn du den Server-Dienst mit Mitteilungen betreibst:

1. developer.apple.com → **Keys → „+“**, Name z. B. „Ohrregal Push“, **Apple Push Notifications service (APNs)** anhaken, Umgebung **Sandbox & Production**.
2. Die .p8-Datei herunterladen (nur einmal möglich!) und die **Key-ID** notieren.
3. Datei, Key-ID, Team-ID und Bundle-ID beim Dienst eintragen (siehe [Dienst/README.md](Dienst/README.md)).

Das ist ein **anderer Schlüssel** als der aus C3.

### C5 – Tester einladen

App Store Connect → **Benutzer und Zugriff → „+“**:
- Rolle **„Marketing“**, nur Zugriff auf deine App.
- Nachdem die Person angenommen hat: in der App unter **TestFlight → Interne Tests** eine Gruppe anlegen (z. B. „Familie“), „Automatische Verteilung“ einschalten und die Person hinzufügen.
- Danach weiter mit [Teil A](#teil-a--app-benutzen).

### Typische Stolpersteine beim Bauen

| Meldung | Lösung |
|---|---|
| „Entitlement … not found and could not be included in profile“ | Die Funktion (CarPlay, Push) ist an der App-ID nicht angehakt (C2), oder die CarPlay-Freigabe fehlt noch. |
| „maximum number of certificates“ | Unter Certificates die alten Einträge „Created via API“ widerrufen. Der Workflow legt selbst keine neuen mehr an. |
| Upload abgelehnt wegen SDK-Version | Der Workflow baut auf `macos-26`. Bei neueren Vorgaben von Apple den Runner in `.github/workflows/*.yml` anheben. |

Lokal bauen geht auch, mit Mac und Xcode: `brew install xcodegen`, `xcodegen`, `open Ohrregal.xcodeproj`.
