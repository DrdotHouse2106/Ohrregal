# CLAUDE.md – Ohrregal

Claude ist für die Entwicklung von Ohrregal zuständig (iPhone-App, CarPlay, TV und Wunsch-Dienst).

## Für jede Sitzung

1. Zuerst `KONZEPT.md` lesen (Grundsätze, feste Pflichten P1–P4, Optik und Wortwahl).
2. Direkt auf `main` committen und pushen, keine Branches. Jeder Push baut über GitHub Actions („Bauen und testen“, TestFlight). Nach dem Push das Ergebnis von „Bauen und testen“ prüfen, denn hier gibt es kein Xcode.
3. Stand und offene Punkte im privaten Wissens-Repo pflegen, nicht hier (das Repo ist öffentlich).

## Regeln

- Deutsch in Oberfläche, Code-Kommentaren und Doku. Möglichst wenig Code, Systembausteine von Apple statt Nachbauten.
- Keine Schlüssel, Adressen oder persönlichen Daten ins Repo.
- Ohrwurm (Musiksammlung) erreicht die App nur über den Wunsch-Dienst (`Dienst/hoerbuch_wunsch.py`, Weiterleitung `/ohrwurm/…` mit Liste erlaubter Aufrufe). Neue Ohrwurm-Aufrufe dort freischalten und die Version erhöhen.
- Den Dienst auf dem Server spielt eine eigene Sitzung im Heimnetz ein; von hier aus einen fertigen Prompt dafür liefern.
