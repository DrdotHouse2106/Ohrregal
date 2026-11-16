import Kern
import SwiftUI

/// Knopf im großen Player: Wiedergabe an Ohrregal auf dem Fernseher übergeben oder den Fernseher einrichten.
struct FernseherKnopf: View {
    @Environment(Player.self) private var player
    @State private var einrichtenOffen = false
    @State private var meldung: String?
    private var tv: Fernseher { .geteilt }

    var body: some View {
        Menu {
            if tv.geraete.isEmpty {
                Text("Kein Fernseher gefunden. Ohrregal auf dem Fernseher öffnen; iPhone und Fernseher müssen im selben WLAN sein.")
            }
            ForEach(tv.geraete) { g in
                Button("Auf „\(g.name)“ abspielen", systemImage: "play.tv") { Task { await abspielen(g) } }
            }
            Button("Fernseher einrichten …", systemImage: "key") { einrichtenOffen = true }
        } label: {
            Image(systemName: "tv").font(.title3).frame(width: 44, height: 44)
        }
        .onAppear { tv.suchen() }
        .sheet(isPresented: $einrichtenOffen) { FernseherEinrichten() }
        .alert("Fernseher", isPresented: Binding(get: { meldung != nil }, set: { if !$0 { meldung = nil } })) {
            Button("OK") {}
        } message: {
            Text(meldung ?? "")
        }
    }

    private func abspielen(_ g: Fernseher.Geraet) async {
        guard let auftrag = player.uebergabe else { meldung = "Gerade läuft nichts."; return }
        await player.abgeben()
        do {
            try await tv.sende(g, "/spielen", json: auftrag)
        } catch {
            meldung = error.deutsch
        }
    }
}

/// Fernseher einrichten ohne Tippen: Die Zugänge gehen im Heimnetz an den Fernseher, dort „Übernehmen“ drücken.
struct FernseherEinrichten: View {
    @Environment(\.dismiss) private var schliessen
    @State private var laeuft: String?
    @State private var meldung: String?
    @State private var adresse = ""
    private var tv: Fernseher { .geteilt }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Ohrregal auf dem Fernseher öffnen. iPhone und Fernseher müssen im selben WLAN sein. Dann den Fernseher hier antippen und auf dem Fernseher „Übernehmen“ drücken.")
                        .font(.callout)
                }
                Section("Gefundene Fernseher") {
                    if tv.geraete.isEmpty {
                        HStack { ProgressView(); Text("Suche …").foregroundStyle(.secondary) }
                    }
                    ForEach(tv.geraete) { g in
                        Button { Task { await einrichten(g) } } label: {
                            HStack {
                                Label(g.name, systemImage: "tv")
                                Spacer()
                                if laeuft == g.id { ProgressView() }
                            }
                        }
                        .disabled(laeuft != nil)
                    }
                }
                Section {
                    TextField("z. B. 192.168.1.20", text: $adresse)
                        .keyboardType(.numbersAndPunctuation).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button("Mit dieser Adresse verbinden") {
                        if let g = Fernseher.Geraet.manuell(adresse) { Task { await einrichten(g) } } else { meldung = "Die Adresse ist ungültig." }
                    }
                    .disabled(adresse.isEmpty || laeuft != nil)
                } header: {
                    Text("Fernseher nicht dabei?")
                } footer: {
                    Text("Die Adresse steht auf dem Fernseher auf der Anmeldeseite bzw. unter Einstellungen.")
                }
                if laeuft != nil {
                    Text("Jetzt auf dem Fernseher „Übernehmen“ drücken.").font(.headline)
                }
                if let meldung { Text(meldung) }
            }
            .navigationTitle("Fernseher einrichten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Fertig") { schliessen() } }
            .onAppear { tv.suchen() }
        }
    }

    private func einrichten(_ g: Fernseher.Geraet) async {
        let z = Zugaenge.geladen()
        laeuft = g.id
        meldung = nil
        defer { laeuft = nil }
        do {
            try await tv.sende(g, "/einrichten", json: ["geraet": "Ohrregal auf dem iPhone (\(z.benutzer))",
                                                       "server": z.server, "benutzer": z.benutzer, "passwort": z.passwort,
                                                       "absServer": z.absServer, "absBenutzer": z.absBenutzer, "absPasswort": z.absPasswort],
                               warten: 95)
            meldung = "„\(g.name)“ ist eingerichtet."
        } catch {
            meldung = error.deutsch
        }
    }
}

/// QR-Code vom Fernseher („ohrregal://fernseher?ip=…&port=…&code=…“): richtet genau diesen Fernseher ein.
/// Der Code steht nur auf dem Bildschirm, deshalb muss dort nichts mehr bestätigt werden.
enum FernseherLink {
    @MainActor static func einrichten(_ url: URL) async -> String? {
        guard url.scheme == "ohrregal", url.host == "fernseher" else { return nil }
        let werte = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func wert(_ n: String) -> String? { werte.first { $0.name == n }?.value }
        guard let ip = wert("ip"), !ip.isEmpty, let code = wert("code"),
              let g = Fernseher.Geraet.manuell("\(ip):\(wert("port") ?? "47811")") else { return "Der QR-Code ist ungültig." }
        let z = Zugaenge.geladen()
        guard !z.server.isEmpty else { return "Bitte zuerst Ohrregal auf dem iPhone anmelden." }
        do {
            try await Fernseher.geteilt.sende(g, "/einrichten", json: ["code": code, "geraet": "iPhone (QR-Code)",
                                                                  "server": z.server, "benutzer": z.benutzer, "passwort": z.passwort,
                                                                  "absServer": z.absServer, "absBenutzer": z.absBenutzer, "absPasswort": z.absPasswort],
                                              warten: 15)
            return "Der Fernseher ist eingerichtet."
        } catch {
            return error.deutsch
        }
    }
}
