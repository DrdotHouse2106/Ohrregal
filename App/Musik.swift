import Kern
import SwiftUI

struct MusikView: View {
    var body: some View {
        List {
            NavigationLink(value: Ziel.kuenstler) { Label("Künstler", systemImage: "music.mic") }
            NavigationLink(value: Ziel.alben) { Label("Alben", systemImage: "square.stack") }
            NavigationLink(value: Ziel.playlists) { Label("Playlists", systemImage: "music.note.list") }
            NavigationLink(value: Ziel.favoriten) { Label("Gefällt mir", systemImage: "heart") }
        }
        .scrollContentBackground(.hidden)
        .background(Farben.hintergrund)
        .navigationTitle("Musik")
    }
}

struct KuenstlerListe: View {
    @Environment(\.client) private var client
    @State private var alle: [Kuenstler] = []
    @State private var filter = ""

    var body: some View {
        List(filter.isEmpty ? alle : alle.filter { $0.name.localizedCaseInsensitiveContains(filter) }) { k in
            NavigationLink(value: k) {
                HStack(spacing: 12) {
                    Cover(id: k.coverArt, groesse: 44, rund: true)
                    Text(k.name)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Farben.hintergrund)
        .navigationTitle("Künstler")
        .safeAreaInset(edge: .top) { Suchfeld(prompt: "Künstler filtern", text: $filter) }
        .task { if alle.isEmpty { alle = (try? await client.kuenstlerListe()) ?? [] } }
    }
}

struct AlbenListe: View {
    @Environment(\.client) private var client
    @State private var alben: [Album] = []
    @State private var ende = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 18) {
                ForEach(alben) { album in
                    NavigationLink(value: album) { AlbumKarte(album: album) }
                        .buttonStyle(.plain)
                        .onAppear { if album.id == alben.last?.id { Task { await nachladen() } } }
                }
            }
            .padding()
        }
        .background(Farben.hintergrund)
        .navigationTitle("Alben")
        .task { if alben.isEmpty { await nachladen() } }
    }

    /// Lädt seitenweise, damit auch zehntausend Alben flüssig bleiben.
    private func nachladen() async {
        guard !ende, let neu = try? await client.alben("alphabeticalByName", anzahl: 60, ab: alben.count) else { return }
        ende = neu.count < 60
        alben += neu.filter { n in !alben.contains { $0.id == n.id } }
    }
}

struct AlbumView: View {
    @Environment(\.client) private var client
    @Environment(Player.self) private var player
    let album: Album
    @State private var titel: [Titel] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Cover(id: album.coverArt, groesse: 260)
                    .shadow(radius: 20)
                Text(album.name).font(.title2.bold()).multilineTextAlignment(.center)
                if let name = album.artist, let id = album.artistId {
                    NavigationLink(value: Kuenstler(id: id, name: name)) {
                        Text(name).font(.title3).foregroundStyle(Farben.blau)
                    }
                }
                if let jahr = album.year { Text(String(jahr)).font(.caption).foregroundStyle(Farben.textGedaempft) }
                AbspielKnoepfe(titel: titel)
            }
            .padding()
            TitelListe(titel: titel, mitCover: false)
        }
        .background(Farben.hintergrund)
        .navigationBarTitleDisplayMode(.inline)
        .task { if titel.isEmpty { titel = (try? await client.album(album.id))?.song ?? [] } }
    }
}

struct AbspielKnoepfe: View {
    @Environment(Player.self) private var player
    let titel: [Titel]

    var body: some View {
        HStack(spacing: 14) {
            Button { player.spiele(titel) } label: {
                Label("Abspielen", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button { player.spiele(titel.shuffled()) } label: {
                Label("Zufällig", systemImage: "shuffle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
        .disabled(titel.isEmpty)
    }
}

struct KuenstlerView: View {
    @Environment(\.client) private var client
    @Environment(Player.self) private var player
    let kuenstler: Kuenstler
    @State private var alben: [Album] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Cover(id: kuenstler.coverArt ?? alben.first?.coverArt, groesse: 180, rund: true)
                Text(kuenstler.name).font(.title.bold())
                Button {
                    Task {
                        var titel: [Titel] = []
                        for album in alben.prefix(10) { titel += (try? await client.album(album.id))?.song ?? [] }
                        player.spiele(titel.shuffled())
                    }
                } label: {
                    Label("Zufällig abspielen", systemImage: "shuffle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(alben.isEmpty)
            }
            .padding()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 18) {
                ForEach(alben) { album in
                    NavigationLink(value: album) { AlbumKarte(album: album) }
                        .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(Farben.hintergrund)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if alben.isEmpty {
                alben = ((try? await client.kuenstler(kuenstler.id))?.album ?? []).sorted { ($0.year ?? 0) > ($1.year ?? 0) }
            }
        }
    }
}

struct PlaylistListe: View {
    @Environment(\.client) private var client
    @State private var playlists: [Playlist] = []

    var body: some View {
        List(playlists) { p in
            NavigationLink(value: p) {
                HStack(spacing: 12) {
                    Cover(id: p.coverArt, groesse: 52)
                    VStack(alignment: .leading) {
                        Text(p.name)
                        Text("\(p.songCount ?? 0) Titel").font(.caption).foregroundStyle(Farben.textGedaempft)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Farben.hintergrund)
        .navigationTitle("Playlists")
        .overlay { if playlists.isEmpty { ContentUnavailableView("Keine Playlists", systemImage: "music.note.list") } }
        .task { if playlists.isEmpty { playlists = (try? await client.playlists()) ?? [] } }
    }
}

struct PlaylistView: View {
    @Environment(\.client) private var client
    let playlist: Playlist
    @State private var titel: [Titel] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Cover(id: playlist.coverArt, groesse: 220)
                Text(playlist.name).font(.title2.bold())
                AbspielKnoepfe(titel: titel)
            }
            .padding()
            TitelListe(titel: titel)
        }
        .background(Farben.hintergrund)
        .navigationBarTitleDisplayMode(.inline)
        .task { if titel.isEmpty { titel = (try? await client.playlist(playlist.id))?.entry ?? [] } }
    }
}

struct FavoritenView: View {
    @Environment(\.client) private var client
    @State private var ergebnis: Suchergebnis?

    var body: some View {
        ErgebnisAnsicht(ergebnis: ergebnis)
            .navigationTitle("Gefällt mir")
            .task { if ergebnis == nil { ergebnis = try? await client.favoriten() } }
    }
}
