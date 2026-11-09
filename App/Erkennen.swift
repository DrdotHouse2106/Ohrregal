import Kern
import ShazamKit
import SwiftUI

/// Titel erkennen (ShazamKit): liegt er auf dem Server, abspielen oder zur Mediathek; sonst über Lidarr wünschen.
struct ErkennenView: View {
    @Environment(\.client) private var client
    @Environment(Sitzung.self) private var sitzung
    @Environment(Player.self) private var player
    @State private var laeuft = false
    @State private var erkannt: (titel: String, kuenstler: String, cover: URL?)?
    @State private var treffer: [Titel] = []
    @State private var lidarr: [LidarrAlbum]?
    @State private var meldung: String?

    var body: some View {
        List {
            Section {
                Button { Task { await erkennen() } } label: {
                    VStack(spacing: 12) {
                        Image(systemName: laeuft ? "waveform" : "shazam.logo")
                            .font(.system(size: 64))
                            .symbolEffect(.variableColor.iterative, isActive: laeuft)
                        Text(laeuft ? "Höre zu …" : "Tippen zum Erkennen").font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .foregroundStyle(.white)
                    .background(Farben.verlauf, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(laeuft)
                .listRowBackground(Color.clear)
            }
            if let meldung { Section { Text(meldung).font(.callout) } }
            if let erkannt {
                Section("Erkannt") {
                    HStack(spacing: 12) {
                        Cover(url: erkannt.cover, groesse: 64)
                        VStack(alignment: .leading) {
                            Text(erkannt.titel).font(.headline)
                            Text(erkannt.kuenstler).foregroundStyle(Farben.textGedaempft)
                        }
                    }
                }
            }
            if !treffer.isEmpty {
                Section("Auf deinem Server") {
                    ForEach(Array(treffer.enumerated()), id: \.element.id) { i, t in
                        HStack {
                            Button { player.spiele(treffer, ab: i, quelle: "Erkannt") } label: { TitelZeile(titel: t) }
                                .buttonStyle(.plain)
                            Button {
                                Task { await Mediathek.geteilt.hinzufuegen([t], client) }
                            } label: {
                                Image(systemName: Mediathek.geteilt.enthaelt(t) ? "checkmark" : "plus")
                            }
                            .buttonStyle(.bordered)
                        }
                        .contextMenu { TitelMenue(titel: t) }
                    }
                }
            } else if let lidarr {
                Section("Nicht auf deinem Server – bei Lidarr") {
                    if lidarr.isEmpty { Text("Auch bei Lidarr nicht gefunden.").foregroundStyle(Farben.textGedaempft) }
                    ForEach(lidarr) { LidarrAlbumZeile(album: $0) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Farben.hintergrund)
        .navigationTitle("Titel erkennen")
    }

    private func erkennen() async {
        laeuft = true
        defer { laeuft = false }
        meldung = nil
        erkannt = nil
        treffer = []
        lidarr = nil
        player.pause()
        switch await SHManagedSession().result() {
        case .match(let treffer):
            guard let item = treffer.mediaItems.first, let titel = item.title else { meldung = "Nicht erkannt."; return }
            let kuenstler = item.artist ?? ""
            erkannt = (titel, kuenstler, item.artworkURL)
            Protokoll.geteilt.merke("erkannt", name: titel, urheber: kuenstler)
            await suchen(titel, kuenstler)
        case .noMatch:
            meldung = "Nicht erkannt. Halte das iPhone näher an die Musik und versuche es noch einmal."
        case .error(let fehler, _):
            meldung = "Erkennen fehlgeschlagen: \(fehler.deutsch)"
        @unknown default:
            meldung = "Nicht erkannt."
        }
    }

    /// Erst in Navidrome suchen, sonst bei Lidarr (Alben und Singles mit diesem Titel).
    private func suchen(_ titel: String, _ kuenstler: String) async {
        let einfach = { (s: String) in s.lowercased().folding(options: .diacriticInsensitive, locale: nil) }
        let lieder = (try? await client.suche(titel))?.song ?? []
        treffer = lieder.filter { einfach($0.artist ?? "").contains(einfach(kuenstler)) || einfach(kuenstler).contains(einfach($0.artist ?? "-")) }
        if treffer.isEmpty {
            if sitzung.dienstDa { lidarr = (try? await sitzung.musikwunsch?.suche("\(kuenstler) \(titel)")) ?? [] }
        }
    }
}
