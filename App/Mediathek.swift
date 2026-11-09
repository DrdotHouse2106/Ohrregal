import Kern
import SwiftUI

/// „Meine Mediathek“ wie bei Apple Music: die persönliche Auswahl aus der Server-Bibliothek.
/// Liegt als Playlist „Meine Mediathek“ in Navidrome; damit gilt sie auf allen Geräten und in jeder Subsonic-App.
@MainActor @Observable
final class Mediathek {
    static let geteilt = Mediathek()
    static let name = "Meine Mediathek"

    private(set) var titel: [Titel] = []
    private(set) var geladen = false
    private var playlistId: String?

    func enthaelt(_ t: Titel) -> Bool { titel.contains { $0.id == t.id } }
    func enthaeltAlle(_ liste: [Titel]) -> Bool { !liste.isEmpty && liste.allSatisfy(enthaelt) }

    func laden(_ client: NavidromeClient) async {
        guard let id = try? await playlist(client, anlegen: false) else { geladen = true; return }
        titel = (try? await client.playlist(id))?.entry ?? titel
        geladen = true
    }

    func hinzufuegen(_ neu: [Titel], _ client: NavidromeClient) async {
        let fehlend = neu.filter { !enthaelt($0) }
        guard !fehlend.isEmpty, let id = try? await playlist(client, anlegen: true) else { return }
        titel += fehlend
        fehlend.forEach { Protokoll.geteilt.merke("mediathek_hinzu", titel: $0) }
        if (try? await client.zurPlaylist(id, titel: fehlend.map(\.id))) == nil { await laden(client) }
    }

    func entfernen(_ weg: [Titel], _ client: NavidromeClient) async {
        guard let id = playlistId else { return }
        let ids = Set(weg.map(\.id))
        let stellen = titel.enumerated().filter { ids.contains($0.element.id) }.map(\.offset)
        guard !stellen.isEmpty else { return }
        titel.removeAll { ids.contains($0.id) }
        weg.forEach { Protokoll.geteilt.merke("mediathek_weg", titel: $0) }
        try? await client.ausPlaylist(id, stellen: stellen)
        await laden(client)
    }

    private func playlist(_ client: NavidromeClient, anlegen: Bool) async throws -> String? {
        if let playlistId { return playlistId }
        if let vorhanden = try await client.playlists().first(where: { $0.name == Self.name }) {
            playlistId = vorhanden.id
        } else if anlegen {
            playlistId = try await client.neuePlaylist(Self.name)?.id
        }
        return playlistId
    }

    /// Alben der Mediathek, gebildet aus ihren Titeln.
    var alben: [(id: String, name: String, kuenstler: String, cover: String?)] {
        var gesehen = Set<String>()
        return titel.compactMap { t in
            guard let id = t.albumId, gesehen.insert(id).inserted else { return nil }
            return (id, t.album ?? "", t.artist ?? "", t.coverArt)
        }
        .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var kuenstler: [Kuenstler] {
        var gesehen = Set<String>()
        return titel.compactMap { t in
            guard let id = t.artistId, gesehen.insert(id).inserted else { return nil }
            return Kuenstler(id: id, name: t.artist ?? "")
        }
        .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}

/// „+ Mediathek“ für Alben und Playlists.
struct MediathekKnopf: View {
    @Environment(\.client) private var client
    let titel: [Titel]

    var body: some View {
        let drin = Mediathek.geteilt.enthaeltAlle(titel)
        Button {
            Task {
                if drin { await Mediathek.geteilt.entfernen(titel, client) } else { await Mediathek.geteilt.hinzufuegen(titel, client) }
            }
        } label: {
            Image(systemName: drin ? "checkmark" : "plus").frame(width: 24, height: 24)
        }
        .buttonStyle(.bordered)
        .disabled(titel.isEmpty)
        .accessibilityLabel(drin ? "Aus der Mediathek entfernen" : "Zur Mediathek hinzufügen")
    }
}

/// Inhalt der Mediathek: Titel, Alben oder Künstler.
struct MediathekView: View {
    @Environment(\.client) private var client
    @Environment(Player.self) private var player
    let art: Art
    @State private var filter = ""

    enum Art: String, Hashable { case titel = "Titel", alben = "Alben", kuenstler = "Künstler" }

    var body: some View {
        let m = Mediathek.geteilt
        List {
            switch art {
            case .titel:
                let liste = m.titel.filter { filter.isEmpty || $0.title.localizedCaseInsensitiveContains(filter) || ($0.artist ?? "").localizedCaseInsensitiveContains(filter) }
                    .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
                ForEach(Array(liste.enumerated()), id: \.element.id) { i, t in
                    Button { player.spiele(liste, ab: i, quelle: "Mediathek") } label: { TitelZeile(titel: t) }
                        .buttonStyle(.plain)
                        .contextMenu { TitelMenue(titel: t) }
                        .swipeActions { Button("Entfernen", role: .destructive) { Task { await m.entfernen([t], client) } } }
                }
            case .alben:
                ForEach(m.alben.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) || $0.kuenstler.localizedCaseInsensitiveContains(filter) }, id: \.id) { a in
                    NavigationLink(value: Ziel.albumNachId(a.id)) {
                        HStack(spacing: 12) {
                            Cover(id: a.cover, groesse: 52)
                            VStack(alignment: .leading) {
                                Text(a.name).lineLimit(1)
                                Text(a.kuenstler).font(.caption).foregroundStyle(Farben.textGedaempft).lineLimit(1)
                            }
                        }
                    }
                }
            case .kuenstler:
                ForEach(m.kuenstler.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }) { k in
                    NavigationLink(value: k) { Text(k.name) }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Farben.hintergrund)
        .safeAreaInset(edge: .top) { Suchfeld(prompt: "In der Mediathek filtern", text: $filter) }
        .navigationTitle(art.rawValue)
        .overlay {
            if m.geladen && m.titel.isEmpty {
                ContentUnavailableView("Mediathek ist leer", systemImage: "plus.circle",
                                       description: Text("Füge Titel über das Menü (langes Drücken) oder Alben mit + hinzu."))
            }
        }
        .refreshable { await m.laden(client) }
        .task { if !m.geladen { await m.laden(client) } }
    }
}

/// Lädt ein Album über seine ID (z. B. aus der Mediathek).
struct AlbumNachId: View {
    @Environment(\.client) private var client
    let id: String
    @State private var album: Album?

    var body: some View {
        Group {
            if let album { AlbumView(album: album) } else { ProgressView() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Farben.hintergrund)
        .task { album = try? await client.album(id) }
    }
}
