# Ohrregal

[![Buy me a coffee](https://img.shields.io/badge/☕_Buy_me_a_coffee-PayPal-0070ba?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/DrdotHouse)

> [!TIP]
> **Testers wanted!** Want to try my apps before everyone else – on iPhone, Android, Fire TV, Android TV or LG webOS? Send a short e-mail to **tester.entwickler@zockerdb.de** with your name, your devices and the e-mail address of your Apple ID or Google account. I'll add you and let you know whenever there is a new app or version to test. Your details stay private and are only used for this.

Music and audiobooks from your own servers in one iPhone app that feels like Apple Music.

- **Music** from [Navidrome](https://www.navidrome.org/) (Subsonic / OpenSubsonic API)
- **Audiobooks and radio plays** from [Audiobookshelf](https://www.audiobookshelf.org/)
- **CarPlay**, offline listening and recommendations based on your listening

Status: version 0.22 (TestFlight). The plan (in German) is in [KONZEPT.md](KONZEPT.md).

Deutsche Version: [README.md](README.md)

## Features

**Music**
- Home with greeting and “For you”: your mix and a mix per favourite artist with cover collages. Plus quick picks, recently played, most played, not heard in a while, recently added and liked albums.
- Library, search, gapless player with queue, synced lyrics, likes, AirPlay and lock screen.
- Create and edit playlists on the phone (stored in Navidrome). Radio from any song.
- **Request music** via Lidarr: missing albums on the artist page, follow artists (new albums only), new releases.

**Audiobooks**
- Continue listening, recently added, genres, libraries with search.
- Player with chapters, 15 s back and 30 s forward, speed, sleep timer. Progress is synced with Audiobookshelf.
- **Request audiobooks:** search Audible, detail page with sample, request a book or **follow a whole series**.
- **Discover** (based on your listening) and **browse** Audible categories, including radio plays.

**Everywhere**
- **CarPlay** with home, music and audiobooks.
- **Offline:** audiobooks you listen to are downloaded automatically (optionally Wi-Fi only). Albums and playlists on demand. Positions are kept offline and synced later.
- **Prepared content:** the home screen appears instantly from storage and is refreshed overnight.
- Notifications “audiobook ready” and “album ready”.
- **What Ohrregal knows about me:** view and delete your listening log.

## Server service (optional)

Requests, discover, browse, series, notifications and the listening log run through a small service next to Audiobookshelf, Navidrome, Lidarr, Prowlarr and SABnzbd. See [Dienst/README.md](Dienst/README.md) and [Dienst/API.md](Dienst/API.md) (German). Without it, music, audiobooks, CarPlay, offline listening and the on-device mixes still work.

## Privacy

Credentials stay on the iPhone (passwords in the Keychain). The listening log only goes to your own server, is used for recommendations only and can be viewed and deleted in the app. Played tracks go to Last.fm via Navidrome only if you set that up there.

## Setup

Step-by-step guide (use the app, prepare servers, build your own app): **[EINRICHTUNG.en.md](EINRICHTUNG.en.md)**.

## Build

GitHub builds, tests and uploads to TestFlight on every push (Actions tab). Locally on a Mac:

```sh
brew install xcodegen
xcodegen          # creates Ohrregal.xcodeproj
open Ohrregal.xcodeproj
```
