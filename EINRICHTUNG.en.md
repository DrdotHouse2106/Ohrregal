# Setting up Ohrregal

Written for people without AI help. Three parts – read only what you need:

| You want to … | Read |
|---|---|
| just **use** the app, someone else runs the servers | [Part A](#part-a--use-the-app) |
| **prepare** your own servers for music and audiobooks | [Part B](#part-b--prepare-the-servers) |
| **build** the app with your own Apple account | [Part C](#part-c--build-your-own-app) |

Deutsche Version: [EINRICHTUNG.md](EINRICHTUNG.md)

## Part A – Use the app

Ohrregal is not in the App Store (yet); it is distributed via **TestFlight**.

1. The person running Ohrregal invites you with the e-mail address of your **Apple ID**.
2. Accept the **App Store Connect** e-mail; a **TestFlight** e-mail follows.
3. Install **TestFlight** from the App Store, open the TestFlight e-mail on the iPhone and tap **“View in TestFlight”** (on a computer the e-mail shows a code for **“Redeem”**).
4. Install Ohrregal and turn on **automatic updates** in TestFlight.
5. Open Ohrregal and enter **Navidrome** (required) and **Audiobookshelf** (optional): address, user name, password.
6. **Home → profile icon → “Mitteilungen”** and allow notifications.

## Part B – Prepare the servers

| Software | Purpose | Required? |
|---|---|---|
| [Navidrome](https://www.navidrome.org/docs/installation/) | music | **yes** |
| [Audiobookshelf](https://www.audiobookshelf.org/docs#install) | audiobooks, radio plays | no |
| Last.fm in Navidrome (`LastFM.ApiKey`, `LastFM.Secret`) | mixes, radio, autoplay | recommended |
| service “Hörbuchwunsch” ([Dienst/README.md](Dienst/README.md), German) | requests, discover, browse, series, notifications, listening log | no |
| Lidarr / Prowlarr + SABnzbd | requesting music / audiobooks | no (service only) |

- Make Navidrome and Audiobookshelf reachable via HTTPS through a reverse proxy.
- One account per person, each with its **own Navidrome password** (also when using proxy authentication).
- Internet radio stations are added in the Navidrome web UI.
- The optional service is expected at the Audiobookshelf address + `/wunsch-api` (otherwise the Navidrome address).

## Part C – Build your own app

You need a paid **Apple Developer account** and a **GitHub account** (building is free on GitHub, no Mac needed).

1. **Fork** the repository (keep it public) and change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` – the only place in the code.
2. **Apple:** note your **Team ID**; create an explicit **App ID** with **Push Notifications** and **ShazamKit** (App Services); request **CarPlay Audio** at [developer.apple.com/contact/carplay](https://developer.apple.com/contact/carplay/) and enable it on the App ID once approved (until then remove `com.apple.developer.carplay-audio` from `App/Ohrregal.entitlements`); create the app in App Store Connect.
3. **GitHub ↔ Apple:** create an App Store Connect API team key with **Admin** access; add the secrets `APPLE_TEAM_ID`, `ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_KEY_P8` (full .p8 content); run **Actions → TestFlight**.
4. **Push key for the service** (optional): Keys → APNs key (Sandbox & Production); give the .p8, Key ID, Team ID and bundle ID to the service. This is a different key from step 3.
5. **Testers:** App Store Connect user with role “Marketing”, then add them to an internal TestFlight group with automatic distribution.

Common errors: “Entitlement … not found” → capability not enabled on the App ID or CarPlay not yet approved; “maximum number of certificates” → revoke old “Created via API” certificates.
