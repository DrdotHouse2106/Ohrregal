import Kern
import SwiftUI

/// Gemeinsam für iPhone und CarPlay; CarPlay kann die App auch ohne iPhone-Oberfläche starten.
@MainActor let geteilterPlayer = Player()
@MainActor let geteilteSitzung = Sitzung()

@main
struct OhrregalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var sitzung = geteilteSitzung
    @State private var player = geteilterPlayer
    @State private var linkMeldung: String?
    @State private var linkAuftrag: FernseherAuftrag?

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
            // QR-Code vom Fernseher mit der Kamera gescannt.
            // Vor dem Senden immer nachfragen und die Zieladresse zeigen.
            .onOpenURL { url in
                switch FernseherLink.pruefen(url) {
                case .success(let auftrag): linkAuftrag = auftrag
                case .failure(let fehler): linkMeldung = fehler.deutsch
                case nil: break
                }
            }
            .alert("Fernseher einrichten?", isPresented: Binding(get: { linkAuftrag != nil }, set: { if !$0 { linkAuftrag = nil } }),
                   presenting: linkAuftrag) { a in
                Button("Senden") { Task { linkMeldung = await FernseherLink.senden(a) } }
                Button("Abbrechen", role: .cancel) {}
            } message: { a in
                Text("Deine Zugänge zu Navidrome und Audiobookshelf werden verschlüsselt an den Fernseher \(a.geraet.adresse) in deinem Heimnetz gesendet.")
            }
            .alert("Fernseher", isPresented: Binding(get: { linkMeldung != nil }, set: { if !$0 { linkMeldung = nil } })) {
                Button("OK") {}
            } message: {
                Text(linkMeldung ?? "")
            }
            .tint(Farben.blau)
            .preferredColorScheme(.dark)
        }
    }
}

/// Angemeldeter Server; Zugangsdaten in UserDefaults, Passwort im Schlüsselbund.
@MainActor @Observable
final class Sitzung {
    var client: NavidromeClient? { didSet { geteilterPlayer.client = client } }
    var hoerbuchClient: AudiobookshelfClient? { didSet { geteilterPlayer.hoerbuchClient = hoerbuchClient } }
    /// Ziel nach dem Antippen einer Push-Nachricht.
    var sprung: Sprung?
    /// Titel, für die gerade eine Playlist gewählt wird.
    var playlistFuer: [Titel]?
    /// Ist ein eigener Wunsch-Dienst eingerichtet? Nur dann gibt es Wünschen, Stöbern, Entdecken, Mitteilungen und Hörprotokoll.
    var dienstDa = UserDefaults.standard.bool(forKey: "dienstDa")
    /// Ohrwurm bzw. Lidarr am Dienst eingerichtet? Nur dann gibt es Musikwünsche. Meldet der Dienst nichts (ältere Fassung),
    /// gilt beides als nicht da: Ohne Erweiterung auf dem Server zeigt die App keine Musikwünsche (auch für die App-Prüfung).
    var ohrwurmDa = UserDefaults.standard.bool(forKey: "ohrwurmDa")
    var lidarrDa = UserDefaults.standard.bool(forKey: "lidarrDa")

    /// Fragt `/wunsch-api/status` ab (ohne Anmeldung). Ohne Antwort bleibt der letzte bekannte Stand.
    func dienstPruefen() async {
        guard let basis = musikwunsch?.basis else { dienstDa = false; return }
        struct Status: Decodable { let ok: Bool; let ohrwurm: Bool?; let lidarr: Bool? }
        do {
            let (daten, antwort) = try await URLSession.shared.data(from: basis.appending(path: "status"))
            let status = (antwort as? HTTPURLResponse)?.statusCode == 200 ? try? JSONDecoder().decode(Status.self, from: daten) : nil
            dienstDa = status?.ok ?? false
            ohrwurmDa = dienstDa && status?.ohrwurm == true
            lidarrDa = dienstDa && status?.lidarr == true
            UserDefaults.standard.set(dienstDa, forKey: "dienstDa")
            UserDefaults.standard.set(ohrwurmDa, forKey: "ohrwurmDa")
            UserDefaults.standard.set(lidarrDa, forKey: "lidarrDa")
        } catch {}
    }

    enum Sprung: Equatable {
        case hoerbuch(String)
        case wuensche
        case musikwuensche
    }

    init() {
        let d = UserDefaults.standard
        if let text = d.string(forKey: "server"), let url = URL(string: text),
           let benutzer = d.string(forKey: "benutzer"), let passwort = Schluesselbund.lies("navidrome") ?? Self.demoPasswort {
            client = NavidromeClient(server: url, benutzer: benutzer, passwort: passwort)
        }
        ladeHoerbuch()
        // Hörprotokoll geht an den eigenen Server (Wunsch-Dienst), angemeldet mit dem Navidrome-Konto.
        Protokoll.geteilt.senden = { ereignisse in
            // Ohne eigenen Dienst bleibt das Protokoll auf dem iPhone.
            guard geteilteSitzung.dienstDa else { return .spaeter }
            return await geteilteSitzung.musikwunsch?.sendeEreignisse(ereignisse) ?? .spaeter
        }
        Task {
            await dienstPruefen()
            await Protokoll.geteilt.abschicken()
        }
        // Beobachter greifen im eigenen init nicht; daher hier ausdrücklich.
        geteilterPlayer.client = client
        geteilterPlayer.hoerbuchClient = hoerbuchClient
    }

    /// Audiobookshelf ist optional; ohne Zugang bleibt der Tab „Hörbücher“ leer.
    func ladeHoerbuch() {
        let d = UserDefaults.standard
        hoerbuchClient = nil
        guard let text = d.string(forKey: "absServer"), !text.isEmpty, let benutzer = d.string(forKey: "absBenutzer"),
              let passwort = Schluesselbund.lies("audiobookshelf") ?? Self.demoPasswort, let url = Adresse.aufbereiten(text) else { return }
        hoerbuchClient = AudiobookshelfClient(server: url, benutzer: benutzer.trimmingCharacters(in: .whitespacesAndNewlines),
                                              passwort: passwort.trimmingCharacters(in: .newlines))
        // Offline gehörte Stellen nachtragen, sobald der Server erreichbar ist.
        if let abs = hoerbuchClient { Task { await Offline.geteilt.nachtragen(abs) } }
    }

    /// Nur für die App-Store-Bildschirmfotos im Simulator (Startargument `-demoPasswort`).
    #if DEBUG
    static let demoPasswort = UserDefaults.standard.string(forKey: "demoPasswort")
    #else
    static let demoPasswort: String? = nil
    #endif

    func anmelden(server: String, benutzer: String, passwort: String) async throws {
        // Leerzeichen am Rand fügt die iPhone-Tastatur gern selbst an (Wortvorschläge, Einfügen) – sie führen zu „falsches Passwort“.
        let benutzer = benutzer.trimmingCharacters(in: .whitespacesAndNewlines)
        let passwort = passwort.trimmingCharacters(in: .newlines)
        // https:// ergänzen bzw. statt http:// nehmen, Adresse der Weboberfläche (…/app) kürzen.
        guard let url = Adresse.aufbereiten(server) else { throw ServerFehler("Die Adresse ist ungültig.") }
        let text = url.absoluteString
        let neu = NavidromeClient(server: url, benutzer: benutzer, passwort: passwort)
        try await neu.ping()
        UserDefaults.standard.set(text, forKey: "server")
        UserDefaults.standard.set(benutzer, forKey: "benutzer")
        Schluesselbund.speichere(passwort, fuer: "navidrome")
        client = neu
    }

    func abmelden() {
        let abs = hoerbuchClient, dienst = musikwunsch
        Task { await Benachrichtigungen.geraetAbmelden(abs, dienst) }
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
    @Environment(\.scenePhase) private var phase
    @Environment(Sitzung.self) private var sitzung
    @Environment(Player.self) private var player
    @Environment(\.client) private var client
    @State private var playerOffen = false
    @State private var tab = UserDefaults.standard.integer(forKey: "startTab")
    @State private var hoerbuchPfad = NavigationPath()
    @State private var musikPfad = NavigationPath()

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { StartView().ziele() }
                .miniPlayer($playerOffen)
                .tabItem { Label("Start", systemImage: "house.fill") }
                .tag(0)
            NavigationStack(path: $musikPfad) { MusikView().ziele() }
                .miniPlayer($playerOffen)
                .tabItem { Label("Musik", systemImage: "music.note") }
                .tag(1)
            NavigationStack(path: $hoerbuchPfad) { HoerbuecherView().ziele() }
                .miniPlayer($playerOffen)
                .tabItem { Label("Hörbücher", systemImage: "books.vertical.fill") }
                .tag(2)
            NavigationStack { SucheView().ziele() }
                .miniPlayer($playerOffen)
                .tabItem { Label("Suchen", systemImage: "magnifyingglass") }
                .tag(3)
        }
        .miniPlayerInTabLeiste($playerOffen, aktiv: player.anzeige != nil)
        .sheet(isPresented: $playerOffen) { VollPlayer() }
        // Nach einer Timer-Nacht: wo weiterhören?
        .confirmationDialog("Gestern bist du eingeschlafen. Wo weiterhören?",
                            isPresented: Binding(get: { player.schlafFrage != nil }, set: { if !$0 { player.schlafFrageBeantworten(nil) } }),
                            titleVisibility: .visible, presenting: player.schlafFrage) { n in
            Button("Ab Timer gestellt (\(n.gestelltUm.formatted(date: .omitted, time: .shortened))) · \(dauerText(Int(n.gestellt)))") { player.schlafFrageBeantworten(n.gestellt) }
            if let ab = n.abgeschaltet {
                Button("5 Minuten vor dem Abschalten · \(dauerText(Int(max(ab - 300, 0))))") { player.schlafFrageBeantworten(max(ab - 300, 0)) }
                Button("Wo der Timer abgeschaltet hat · \(dauerText(Int(ab)))") { player.schlafFrageBeantworten(nil) }
            }
        }
        .sheet(isPresented: Binding(get: { sitzung.playlistFuer != nil }, set: { if !$0 { sitzung.playlistFuer = nil } })) {
            PlaylistAuswahl(titel: sitzung.playlistFuer ?? [])
        }
        .onChange(of: sitzung.sprung) { springen() }
        .onChange(of: phase) { if phase == .background { Task { await Protokoll.geteilt.abschicken() } } }
        .onAppear { springen() }
        .task(id: client.adresse("ping")) {
            player.client = client
            player.hoerbuchClient = sitzung.hoerbuchClient
        }
    }

    /// Öffnet nach einer Push-Nachricht das Hörbuch bzw. „Meine Wünsche“.
    private func springen() {
        guard let ziel = sitzung.sprung else { return }
        sitzung.sprung = nil
        if ziel == .musikwuensche {
            guard sitzung.lidarrDa || sitzung.ohrwurmDa else { return }
            tab = 1
            musikPfad = NavigationPath([sitzung.lidarrDa ? Ziel.musikwuensche("") : Ziel.ohrwurm("")])
            return
        }
        tab = 2
        var pfad = NavigationPath()
        if case .hoerbuch(let id) = ziel { pfad.append(Ziel.hoerbuch(id)) } else { pfad.append(Ziel.wuensche) }
        hoerbuchPfad = pfad
    }
}
