import Kern
import SwiftUI

extension View {
    /// Ziele für Album, Künstler, Playlist und Hörbuch in jedem Tab.
    func ziele() -> some View {
        navigationDestination(for: Album.self) { AlbumView(album: $0) }
            .navigationDestination(for: Kuenstler.self) { KuenstlerView(kuenstler: $0) }
            .navigationDestination(for: Playlist.self) { PlaylistView(playlist: $0) }
            .navigationDestination(for: Hoerbuch.self) { HoerbuchView(hoerbuch: $0) }
            .navigationDestination(for: BuchTreffer.self) { TrefferView(treffer: $0) }
            .navigationDestination(for: Ziel.self) { $0.ansicht }
    }

    func miniPlayer(_ offen: Binding<Bool>) -> some View {
        safeAreaInset(edge: .bottom) { MiniPlayer(offen: offen) }
    }
}

/// Alle übrigen Seiten. Jeder Link im Stapel arbeitet mit Werten; gemischt mit Links auf feste Ansichten
/// springt SwiftUI sonst gelegentlich zurück, statt die Seite zu öffnen.
enum Ziel: Hashable {
    case kuenstler, alben, playlists, favoriten, wuensche
    case bibliothek(Bibliothek)
    case genre(Bibliothek, String)
    /// Hörbuch, von dem nur die Audiobookshelf-ID bekannt ist (z. B. fertiger Wunsch).
    case hoerbuch(String)
    case stoebern
    case kategorie(Kategorie)

    @ViewBuilder var ansicht: some View {
        switch self {
        case .kuenstler: KuenstlerListe()
        case .alben: AlbenListe()
        case .playlists: PlaylistListe()
        case .favoriten: FavoritenView()
        case .wuensche: WunschView()
        case .bibliothek(let b): BibliothekView(bibliothek: b)
        case .genre(let b, let g): BibliothekView(bibliothek: b, genre: g)
        case .hoerbuch(let id): HoerbuchLaden(id: id)
        case .stoebern: StoebernView()
        case .kategorie(let k): KategorieView(kategorie: k)
        }
    }
}

/// Immer sichtbares Suchfeld oben auf der Seite (statt des von iOS versteckten Felds).
struct Suchfeld: View {
    let prompt: String
    @Binding var text: String
    var laeuft = false
    var suchen: (() -> Void)?

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(Farben.textGedaempft)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { suchen?() }
            if laeuft {
                ProgressView()
            } else if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Farben.textGedaempft)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Farben.flaeche, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Farben.hintergrund)
    }
}

struct Cover: View {
    @Environment(\.client) private var client
    var id: String?
    /// Fertige Adresse (Hörbücher); sonst wird `id` bei Navidrome abgefragt.
    var url: URL?
    var groesse: CGFloat = 160
    var rund = false

    var body: some View {
        AsyncImage(url: url ?? client.coverURL(id, groesse: Int(groesse * 2))) { bild in
            bild.resizable().scaledToFill()
        } placeholder: {
            Farben.flaeche.overlay(Image(systemName: rund ? "music.mic" : "music.note").foregroundStyle(Farben.textGedaempft))
        }
        .frame(width: groesse, height: groesse)
        .clipShape(rund ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8)))
    }
}

struct AlbumKarte: View {
    let album: Album
    var groesse: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Cover(id: album.coverArt, groesse: groesse)
            Text(album.name).font(.subheadline).lineLimit(1)
            Text(album.artist ?? "").font(.caption).foregroundStyle(Farben.textGedaempft).lineLimit(1)
        }
        .frame(width: groesse, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Seitlich wischende Reihe. Jedes Cover ist ein eigener Link, damit genau das angetippte öffnet (P2).
struct AlbenReihe: View {
    let titel: String
    let alben: [Album]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titel).font(.title2.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(alben) { album in
                        NavigationLink(value: album) { AlbumKarte(album: album) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct KuenstlerReihe: View {
    let kuenstler: [Kuenstler]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Künstler").font(.title2.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(kuenstler) { k in
                        NavigationLink(value: k) {
                            VStack {
                                Cover(id: k.coverArt, groesse: 110, rund: true)
                                Text(k.name).font(.caption).lineLimit(1)
                            }
                            .frame(width: 110)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/// Titelliste; Antippen spielt ab diesem Titel.
struct TitelListe: View {
    @Environment(Player.self) private var player
    let titel: [Titel]
    var mitCover = true

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(titel.enumerated()), id: \.offset) { i, t in
                Button { player.spiele(titel, ab: i) } label: { TitelZeile(titel: t, mitCover: mitCover) }
                    .buttonStyle(.plain)
                    .contextMenu { RadioKnopf(titel: t) }
            }
        }
    }
}

/// „Radio ab diesem Song“: der Titel und danach ähnliche (über Last.fm).
struct RadioKnopf: View {
    @Environment(\.client) private var client
    @Environment(Player.self) private var player
    let titel: Titel

    var body: some View {
        Button("Radio ab diesem Song", systemImage: "dot.radiowaves.left.and.right") {
            Task { player.spiele(await Mixe.radio(ab: titel, client)) }
        }
    }
}

struct TitelZeile: View {
    @Environment(Player.self) private var player
    let titel: Titel
    var mitCover = true

    var body: some View {
        HStack(spacing: 12) {
            if mitCover {
                Cover(id: titel.coverArt, groesse: 48)
            } else {
                Text(titel.track.map(String.init) ?? "").font(.subheadline).foregroundStyle(Farben.textGedaempft).frame(width: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(titel.title).lineLimit(1)
                    .foregroundStyle(player.aktuell?.id == titel.id ? Farben.blau : Farben.text)
                Text(titel.artist ?? "").font(.caption).foregroundStyle(Farben.textGedaempft).lineLimit(1)
            }
            Spacer()
            Text(dauerText(titel.duration)).font(.caption).foregroundStyle(Farben.textGedaempft)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

func dauerText(_ sekunden: Int?) -> String {
    guard let s = sekunden else { return "" }
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}
