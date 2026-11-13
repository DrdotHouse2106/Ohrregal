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
                                Text([f.podcastTitel, FolgenZeile.info(f)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
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
                    .contextMenu {
                        gehoertKnopf(f)
                    } preview: {
                        // Langes Drücken: ganzer Titel und Beschreibung.
                        VStack(alignment: .leading, spacing: 8) {
                            Text(f.titel).font(.headline)
                            Text(FolgenZeile.info(f)).font(.caption).foregroundStyle(Farben.textGedaempft)
                            if let text = f.description, !text.isEmpty { Text(text).font(.callout).lineLimit(12) }
                        }
                        .padding()
                        .frame(width: 340, alignment: .leading)
                        .background(Farben.hintergrund)
                    }
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
                Text(Self.info(folge)).font(.caption).foregroundStyle(Farben.textGedaempft)
                Text(folge.titel).lineLimit(2)
                    .foregroundStyle((anteil ?? 0) >= 1 ? Farben.textGedaempft : .primary)
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

    /// „12. Nov. · 13 Min.“ (Jahr nur, wenn es nicht dieses ist).
    static func info(_ folge: Folge) -> String {
        var teile: [String] = []
        if let d = folge.datum {
            let diesesJahr = Calendar.current.isDate(d, equalTo: .now, toGranularity: .year)
            teile.append(d.formatted(diesesJahr ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year()))
        }
        if let s = folge.duration, s > 0 { teile.append("\(max(Int(s / 60), 1)) Min.") }
        return teile.joined(separator: " · ")
    }
}

/// Podcast im Apple-Verzeichnis suchen und über den eigenen Dienst abonnieren.
struct PodcastSucheView: View {
    @Environment(Sitzung.self) private var sitzung
    @State private var text = ""
    @State private var treffer: [PodcastTreffer] = []
    @State private var abos: [PodcastAbos.Abo] = []
    @State private var laeuft: Set<String> = []
    @State private var meldung: String?

    var body: some View {
        List {
            if let meldung { Text(meldung).font(.callout).listRowBackground(Farben.flaeche) }
            if !treffer.isEmpty {
                Section("Gefunden") {
                    ForEach(treffer) { t in
                        HStack(spacing: 12) {
                            AsyncImage(url: t.cover.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() } placeholder: { Farben.flaeche }
                                .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.titel).lineLimit(2)
                                Text([t.autor, t.genre, t.folgen.map { "\($0) Folgen" }].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(Farben.textGedaempft).lineLimit(1)
                            }
                            Spacer()
                            if let id = t.absItemId {
                                NavigationLink("Öffnen", value: Ziel.podcastNachId(id)).fixedSize()
                            } else if laeuft.contains(t.id) {
                                ProgressView()
                            } else {
                                Button("Abonnieren") { Task { await abonniere(t) } }.buttonStyle(.bordered).tint(Farben.blau)
                            }
                        }
                        .listRowBackground(Farben.flaeche)
                    }
                }
            }
            if !abos.isEmpty {
                Section {
                    ForEach(abos) { a in
                        NavigationLink(value: Ziel.podcastNachId(a.absItemId)) { Text(a.titel ?? "Podcast") }
                            .listRowBackground(Farben.flaeche)
                            .swipeActions {
                                if a.vonMir == true {
                                    Button("Keine neuen Folgen mehr laden", role: .destructive) { Task { await abbestellen(a) } }
                                }
                            }
                    }
                } header: {
                    Text("Abonniert")
                } footer: {
                    Text("Neue Folgen lädt der Server stündlich. Zum Beenden nach links wischen; vorhandene Folgen bleiben.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Farben.hintergrund)
        .navigationTitle("Podcast suchen")
        .safeAreaInset(edge: .top) { Suchfeld(prompt: "Podcast suchen", text: $text) }
        .task(id: text) {
            guard text.count >= 2, let abs = sitzung.hoerbuchClient else { treffer = []; return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do { treffer = try await abs.podcastSuche(text); meldung = nil } catch { meldung = "Suche fehlgeschlagen: \(error.deutsch)" }
        }
        .task { abos = (try? await sitzung.hoerbuchClient?.podcastAbos())?.abos ?? [] }
    }

    private func abonniere(_ t: PodcastTreffer) async {
        guard let abs = sitzung.hoerbuchClient else { return }
        laeuft.insert(t.id)
        defer { laeuft.remove(t.id) }
        do {
            let id = try await abs.abonniere(t.feedUrl)
            meldung = "„\(t.titel)“ abonniert. Die neuesten 3 Folgen kommen gleich."
            treffer = treffer.map { $0.id == t.id ? PodcastTreffer(kopie: $0, absItemId: id) : $0 }
            abos = (try? await abs.podcastAbos())?.abos ?? abos
        } catch {
            meldung = "Abonnieren fehlgeschlagen: \(error.deutsch)"
        }
    }

    private func abbestellen(_ a: PodcastAbos.Abo) async {
        do {
            try await sitzung.hoerbuchClient?.abbestellen(a.absItemId)
            abos.removeAll { $0.id == a.id }
            meldung = "Für „\(a.titel ?? "den Podcast")“ werden keine neuen Folgen mehr geladen."
        } catch {
            meldung = "Hat nicht geklappt: \(error.deutsch)"
        }
    }
}

/// Podcast, von dem nur die Audiobookshelf-ID bekannt ist.
struct PodcastNachId: View {
    @Environment(Sitzung.self) private var sitzung
    let id: String
    @State private var podcast: Hoerbuch?
    @State private var fehler: String?

    var body: some View {
        Group {
            if let podcast {
                PodcastView(podcast: podcast)
            } else if let fehler {
                ContentUnavailableView("Podcast nicht gefunden", systemImage: "exclamationmark.triangle", description: Text(fehler))
            } else {
                ProgressView()
            }
        }
        .task {
            do { podcast = try await sitzung.hoerbuchClient?.hoerbuch(id) } catch { fehler = error.deutsch }
        }
    }
}
