import Kern
import SwiftUI

@main
struct OhrregalApp: App {
    @State private var sitzung = Sitzung()
    @State private var player = Player()

    init() {
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let client = sitzung.client {
                    Hauptansicht().environment(\.client, client)
                } else {
                    Anmeldung()
                }
            }
            .environment(sitzung)
            .environment(player)
            .tint(Farben.blau)
            .preferredColorScheme(.dark)
        }
    }
}

/// Angemeldeter Server; Zugangsdaten in UserDefaults, Passwort im Schlüsselbund.
@MainActor @Observable
final class Sitzung {
    var client: NavidromeClient?

    init() {
        let d = UserDefaults.standard
        if let text = d.string(forKey: "server"), let url = URL(string: text),
           let benutzer = d.string(forKey: "benutzer"), let passwort = Schluesselbund.lies("navidrome") {
            client = NavidromeClient(server: url, benutzer: benutzer, passwort: passwort)
        }
    }

    func anmelden(server: String, benutzer: String, passwort: String) async throws {
        // Leerzeichen am Rand fügt die iPhone-Tastatur gern selbst an (Wortvorschläge, Einfügen) – sie führen zu „falsches Passwort“.
        let benutzer = benutzer.trimmingCharacters(in: .whitespacesAndNewlines)
        let passwort = passwort.trimmingCharacters(in: .newlines)
        var text = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        // Adresse der Weboberfläche (…/app) wird auf die Server-Adresse gekürzt.
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix("/app") { text.removeLast(4) }
        guard let url = URL(string: text) else { throw ServerFehler("Die Adresse ist ungültig.") }
        let neu = NavidromeClient(server: url, benutzer: benutzer, passwort: passwort)
        try await neu.ping()
        UserDefaults.standard.set(text, forKey: "server")
        UserDefaults.standard.set(benutzer, forKey: "benutzer")
        Schluesselbund.speichere(passwort, fuer: "navidrome")
        client = neu
    }

    func abmelden() {
        Schluesselbund.loesche("navidrome")
        client = nil
    }
}

private struct ClientSchluessel: EnvironmentKey {
    static let defaultValue = NavidromeClient(server: URL(string: "http://localhost")!, benutzer: "", passwort: "")
}

extension EnvironmentValues {
    var client: NavidromeClient {
        get { self[ClientSchluessel.self] }
        set { self[ClientSchluessel.self] = newValue }
    }
}

struct Hauptansicht: View {
    @Environment(Player.self) private var player
    @Environment(\.client) private var client
    @State private var playerOffen = false

    var body: some View {
        TabView {
            NavigationStack { StartView().ziele() }
                .miniPlayer($playerOffen)
                .tabItem { Label("Start", systemImage: "house.fill") }
            NavigationStack { MusikView().ziele() }
                .miniPlayer($playerOffen)
                .tabItem { Label("Musik", systemImage: "music.note") }
            NavigationStack {
                ContentUnavailableView("Hörbücher kommen bald", systemImage: "books.vertical",
                                       description: Text("Audiobookshelf wird in Stufe 3 angebunden."))
                    .background(Farben.hintergrund)
                    .navigationTitle("Hörbücher")
            }
            .miniPlayer($playerOffen)
            .tabItem { Label("Hörbücher", systemImage: "books.vertical.fill") }
            NavigationStack { SucheView().ziele() }
                .miniPlayer($playerOffen)
                .tabItem { Label("Suchen", systemImage: "magnifyingglass") }
        }
        .sheet(isPresented: $playerOffen) { VollPlayer() }
        .task(id: client.adresse("ping")) { player.client = client }
    }
}
