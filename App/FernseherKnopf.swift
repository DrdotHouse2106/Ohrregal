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
    private var tv: Fernseher { .geteilt }

    var body: some View {
        NavigationStack {
            List {
                Section {
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
                } footer: {
                    Text(laeuft != nil
                         ? "Jetzt auf dem Fernseher „Übernehmen“ drücken."
                         : "Ohrregal auf dem Fernseher öffnen. iPhone und Fernseher müssen im selben WLAN sein. Deine Zugänge zu Navidrome und Audiobookshelf gehen nur im Heimnetz an den Fernseher.")
                }
                if let meldung { Text(meldung) }
            }
            .overlay { if tv.geraete.isEmpty { ContentUnavailableView("Suche Fernseher …", systemImage: "tv", description: Text("Ohrregal auf dem Fernseher öffnen.")) } }
            .navigationTitle("Fernseher einrichten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Fertig") { schliessen() } }
            .onAppear { tv.suchen() }
        }
    }

    private func einrichten(_ g: Fernseher.Geraet) async {
        let z = Zugaenge.geladen()
        laeuft = g.id
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
