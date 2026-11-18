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
                        if let g = Fernseher.Geraet.manuell(adresse) { Task { await einrichten(g) } } else { meldung = "Bitte eine Adresse aus deinem Heimnetz eingeben, z. B. 192.168.1.20." }
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
                                                       "absServer": Adresse.aufbereiten(z.absServer)?.absoluteString ?? z.absServer, "absBenutzer": z.absBenutzer, "absPasswort": z.absPasswort],
                               warten: 95)
            meldung = "„\(g.name)“ ist eingerichtet."
        } catch {
            meldung = error.deutsch
        }
    }
}

/// QR-Code vom Fernseher („ohrregal://fernseher?ip=…&port=…&code=…“). Erst nachfragen, dann senden;
/// nur an Adressen im Heimnetz und verschlüsselt mit dem Code, den nur der echte Fernseher kennt.
struct FernseherAuftrag: Identifiable {
    let geraet: Fernseher.Geraet
    let code: String
    var id: String { geraet.id }
}

enum FernseherLink {
    /// Prüft den Link. Ungültig oder nicht im Heimnetz → Meldung, sonst ein Auftrag zur Rückfrage.
    static func pruefen(_ url: URL) -> Result<FernseherAuftrag, ServerFehler>? {
        guard url.scheme == "ohrregal", url.host == "fernseher" else { return nil }
        let werte = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func wert(_ n: String) -> String? { werte.first { $0.name == n }?.value }
        guard let ip = wert("ip"), let code = wert("code"), code.count >= 8 else { return .failure(ServerFehler("Der QR-Code ist ungültig.")) }
        guard let g = Fernseher.Geraet.manuell("\(ip):\(wert("port") ?? "47811")") else {
            return .failure(ServerFehler("Der QR-Code zeigt auf eine Adresse außerhalb deines Heimnetzes. Aus Sicherheitsgründen wird nichts gesendet."))
        }
        return .success(FernseherAuftrag(geraet: g, code: code))
    }

    @MainActor static func senden(_ a: FernseherAuftrag) async -> String {
        let z = Zugaenge.geladen()
        guard !z.server.isEmpty else { return "Bitte zuerst Ohrregal auf dem iPhone anmelden." }
        do {
            let paket = try Fernseher.verschluesseln(["geraet": "iPhone (QR-Code)",
                                                     "server": z.server, "benutzer": z.benutzer, "passwort": z.passwort,
                                                     "absServer": Adresse.aufbereiten(z.absServer)?.absoluteString ?? z.absServer,
                                                     "absBenutzer": z.absBenutzer, "absPasswort": z.absPasswort], code: a.code)
            try await Fernseher.geteilt.sende(a.geraet, "/einrichten", json: ["verschluesselt": paket], warten: 15)
            return "Der Fernseher ist eingerichtet."
        } catch {
            return error.deutsch
        }
    }
}
