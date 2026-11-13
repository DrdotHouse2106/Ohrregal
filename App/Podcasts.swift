import Kern
import SwiftUI

/// Podcasts aus Audiobookshelf (Bibliotheken vom Typ „podcast“), z. B. YouTube-Kanäle als Ton.
struct PodcastReihe: View {
    let podcasts: [Hoerbuch]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Podcasts").font(.title2.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(podcasts) { p in
                        NavigationLink(value: Ziel.podcast(p)) { HoerbuchKarte(hoerbuch: p, groesse: 130) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/// Neueste ungehörte Folgen aller Podcasts; Antippen spielt sofort.
struct NeueFolgenReihe: View {
    @Environment(Sitzung.self) private var sitzung
    @Environment(Player.self) private var player
    let folgen: [Folge]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Neue Folgen").font(.title2.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(folgen) { f in
                        Button {
                            guard let id = f.libraryItemId else { return }
                            Task { await player.spiele(folge: f, podcast: id, podcastTitel: f.podcastTitel ?? "") }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Cover(url: f.libraryItemId.flatMap { sitzung.hoerbuchClient?.coverURL($0) }, groesse: 160)
                                Text(f.titel).font(.subheadline).lineLimit(2)
                                Text([f.podcastTitel, f.datum?.formatted(date: .abbreviated, time: .omitted)].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(Farben.textGedaempft).lineLimit(1)
                            }
                            .frame(width: 160, alignment: .leading)
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

/// Ein Podcast mit allen Folgen, neueste zuerst.
struct PodcastView: View {
    @Environment(Sitzung.self) private var sitzung
    @Environment(Player.self) private var player
    let podcast: Hoerbuch
    @State private var folgen: [Folge] = []
    @State private var fortschritt: [String: Double] = [:]
    @State private var fehler: String?

    var body: some View {
        List {
            HStack(spacing: 16) {
                Cover(url: sitzung.hoerbuchClient?.coverURL(podcast.id), groesse: 110)
                VStack(alignment: .leading, spacing: 4) {
                    Text(podcast.titel).font(.title3.bold())
                    if !podcast.autor.isEmpty { Text(podcast.autor).foregroundStyle(Farben.textGedaempft) }
                    Text("\(folgen.count) Folgen").font(.caption).foregroundStyle(Farben.textGedaempft)
                }
            }
            .listRowBackground(Color.clear)
            Section {
                ForEach(folgen) { f in
                    Button {
                        Task { await player.spiele(folge: f, podcast: podcast.id, podcastTitel: podcast.titel) }
                    } label: {
                        FolgenZeile(folge: f, anteil: fortschritt[f.id])
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Farben.flaeche)
                    .swipeActions { gehoertKnopf(f) }
                    .contextMenu { gehoertKnopf(f) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Farben.hintergrund)
        .navigationTitle(podcast.titel)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if let fehler, folgen.isEmpty {
                ContentUnavailableView("Folgen nicht geladen", systemImage: "wifi.exclamationmark", description: Text(fehler))
            }
        }
        .refreshable { await laden() }
        .task { await laden() }
    }

    private func gehoertKnopf(_ f: Folge) -> some View {
        let fertig = (fortschritt[f.id] ?? 0) >= 1
        return Button(fertig ? "Als ungehört markieren" : "Als gehört markieren", systemImage: fertig ? "circle" : "checkmark.circle") {
            fortschritt[f.id] = fertig ? 0 : 1
            Task { try? await sitzung.hoerbuchClient?.markiere(podcast.id, folge: f.id, gehoert: !fertig) }
        }
        .tint(Farben.blau)
    }

    private func laden() async {
        guard let abs = sitzung.hoerbuchClient else { return }
        do {
            folgen = try await abs.folgen(podcast.id)
            fortschritt = (try? await abs.folgenFortschritt()) ?? fortschritt
            fehler = nil
        } catch {
            fehler = error.deutsch
        }
    }
}

/// Folge mit Datum und Länge; rechts ungehört (Punkt), angefangen (Balken) oder gehört (Haken).
struct FolgenZeile: View {
    let folge: Folge
    let anteil: Double?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(folge.titel).lineLimit(2)
                    .foregroundStyle((anteil ?? 0) >= 1 ? Farben.textGedaempft : .primary)
                Text(info).font(.caption).foregroundStyle(Farben.textGedaempft)
            }
            Spacer()
            if let anteil, anteil >= 1 {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Farben.blau)
            } else if let anteil, anteil > 0 {
                ProgressView(value: anteil).frame(width: 36).tint(Farben.blau)
            } else {
                Image(systemName: "circle.fill").font(.caption2).foregroundStyle(Farben.blau)
            }
        }
        .contentShape(Rectangle())
    }

    private var info: String {
        var teile: [String] = []
        if let d = folge.datum { teile.append(d.formatted(date: .abbreviated, time: .omitted)) }
        if let s = folge.duration, s > 0 { teile.append("\(max(Int(s / 60), 1)) Min.") }
        return teile.joined(separator: " · ")
    }
}
