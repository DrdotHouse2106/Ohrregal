# Ohrregal TV

Ohrregal für **Fire TV** und **Android TV** (z. B. waipu.tv-Stick): Musik aus Navidrome, Hörbücher und Podcasts aus Audiobookshelf, Radio. Bedienung mit der Fernbedienung, Wiedergabe läuft auch beim Bildschirmschoner weiter.

## Installieren

1. Auf dem Stick die App **„Downloader“** installieren (Amazon Appstore bzw. Google Play).
2. Einstellungen → Mein Fire TV (bzw. Geräteeinstellungen) → Entwickleroptionen → **Apps unbekannter Herkunft** für „Downloader“ erlauben.
   Fehlen die Entwickleroptionen: Einstellungen → Mein Fire TV → Info → 7× auf den Gerätenamen drücken.
3. In Downloader diese Adresse eingeben:
   `https://github.com/DrdotHouse2106/Ohrregal/releases/download/tv/ohrregal-tv.apk`
4. Installieren, öffnen, Navidrome und (optional) Audiobookshelf eintragen.

**Updates:** Die direkt installierte App schaut beim Start nach einer neuen Version, lädt sie im Hintergrund und zeigt oben „Neue Version installieren“. Beim ersten Mal fragt Android, ob Ohrregal Apps installieren darf. Die Zugänge bleiben erhalten.
Die Fassungen aus dem Amazon Appstore und von Google Play haben keinen eigenen Updater, dort aktualisiert der Store.

## Vom iPhone auf den Fernseher

Ohrregal auf dem Fernseher öffnen. Auf dem iPhone im großen Player auf das **Fernseher-Symbol** tippen:
- **Fernseher einrichten** (auch unter Start → Profilsymbol): Das iPhone schickt die Zugänge im Heimnetz, auf dem Fernseher nur noch „Übernehmen“ drücken. Tippen mit der Fernbedienung entfällt.
- **Auf dem Fernseher abspielen:** Der Fernseher spielt weiter, was auf dem iPhone lief (Musik ab derselben Stelle, Hörbuch und Podcast an der gespeicherten Stelle, Radio). Das iPhone hält an.

Technik: Die TV-App meldet sich im Heimnetz als `_ohrregal._tcp` und nimmt kleine HTTP-Anfragen an (`/status`, `/spielen`, `/steuern`, `/einrichten` mit Code). Gestreamt wird direkt vom eigenen Server.

## Bauen

GitHub baut bei jedem Push in `TV/` (Reiter **Actions → TV-App**) und legt die APK im Release „tv“ ab.
Dafür braucht das Repo zwei Secrets (einmalig): `TV_KEYSTORE_B64` (Signierschlüssel, Base64) und `TV_KEYSTORE_PASSWORT`.
Der Schlüssel muss immer derselbe bleiben, sonst lässt sich ein Update nicht über die alte Version installieren.

Lokal: `cd TV && gradle assembleDebug` (Android-SDK nötig, Pfad in `local.properties`).

Technik: Kotlin, Jetpack Compose for TV, Media3 (ExoPlayer) mit MediaSessionService, ab Android 5.1 (auch Fire TV Stick 2. Generation).
