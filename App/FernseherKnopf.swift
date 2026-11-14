import Kern
import SwiftUI

/// Knopf im großen Player: Wiedergabe an Ohrregal auf dem Fernseher übergeben oder den Fernseher einrichten.
struct FernseherKnopf: View {
    @Environment(Player.self) private var player
    @State private var einrichten: Fernseher.Geraet?
    @State private var code = ""
    @State private var meldung: String?
    private var tv: Fernseher { .geteilt }

    var body: some View {
        Menu {
            if tv.geraete.isEmpty {
                Text("Kein Fernseher gefunden. Ohrregal auf dem Fernseher öffnen; iPhone und Fernseher müssen im selben WLAN sein.")
            }
            ForEach(tv.geraete) { g in
                Section(g.name) {
                    Button("Auf dem Fernseher abspielen", systemImage: "play.tv") { Task { await abspielen(g) } }
                    Button("Fernseher einrichten", systemImage: "key") { code = ""; einrichten = g }
                }
            }
        } label: {
            Image(systemName: "tv").font(.title3).frame(width: 44, height: 44)
        }
        .onAppear { tv.suchen() }
        .alert("Fernseher einrichten", isPresented: Binding(get: { einrichten != nil }, set: { if !$0 { einrichten = nil } })) {
            TextField("Code", text: $code).keyboardType(.numberPad)
            Button("Einrichten") { if let g = einrichten { Task { await einrichtenSenden(g) } } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Den Code zeigt Ohrregal auf dem Fernseher (Anmeldung bzw. Einstellungen). Deine Zugänge zu Navidrome und Audiobookshelf werden dabei im Heimnetz an den Fernseher übertragen.")
        }
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

    private func einrichtenSenden(_ g: Fernseher.Geraet) async {
        let z = Zugaenge.geladen()
        do {
            try await tv.sende(g, "/einrichten", json: ["code": code.trimmingCharacters(in: .whitespaces),
                                                       "server": z.server, "benutzer": z.benutzer, "passwort": z.passwort,
                                                       "absServer": z.absServer, "absBenutzer": z.absBenutzer, "absPasswort": z.absPasswort])
            meldung = "Der Fernseher ist eingerichtet."
        } catch {
            meldung = error.deutsch
        }
    }
}
