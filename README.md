# Ohrregal

Musik und Hörbücher von den eigenen Servern – auf dem iPhone mit dem Gefühl von Apple Music, und auf Fire TV / Android TV.

- **Musik** aus [Navidrome](https://www.navidrome.org/) (Subsonic- bzw. OpenSubsonic-API)
- **Hörbücher** aus [Audiobookshelf](https://www.audiobookshelf.org/)
- **Vorschläge** aus deinem eigenen Hörverhalten, ausgewertet auf dem iPhone
- **CarPlay** und **Apple Watch**
- **TV-App** für Fire TV und Android TV
- **Musik wünschen** über Lidarr
- Optik und Wortwahl passend zu Quallenkino

> [!NOTE]
> Das Projekt steht am Anfang. Was die App können soll und in welcher Reihenfolge, steht in [KONZEPT.md](KONZEPT.md).
>
> English version: [README.en.md](README.en.md)

## Bauen

GitHub baut und testet bei jedem Push automatisch (Reiter **Actions**). Lokal auf dem Mac:

```sh
brew install xcodegen
xcodegen          # erzeugt Ohrregal.xcodeproj
open Ohrregal.xcodeproj
```
