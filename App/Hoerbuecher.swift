import AVFoundation
import Kern
import SwiftUI

struct HoerbuecherView: View {
    @Environment(Sitzung.self) private var sitzung
    @State private var angefangen: [Hoerbuch] = []
    @State private var bibliotheken: [Bibliothek] = []
    @State private var neu: [Hoerbuch] = []
    @State private var entdecken: [BuchTreffer] = []
    @State private var genres: [(Bibliothek, String)] = []
    @State private var fehler: String?

    var body: some View {
        Group {
            if let abs = sitzung.hoerbuchClient {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if !angefangen.isEmpty {
                            HoerbuchReihe(titel: "Weiterhören", hoerbuecher: angefangen) { h in
                                angefangen.removeAll { $0.id == h.id }
                                Task { try? await abs.ausWeiterhoerenEntfernen(h.id) }
                            }
                        }
                        if !entdecken.isEmpty {
                            EntdeckenReihe(treffer: entdecken)
                        }
                        if !neu.isEmpty {
                            HoerbuchReihe(titel: "Kürzlich hinzugefügt", hoerbuecher: neu)
                        }
                        if !genres.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Genres").font(.title2.bold()).padding(.horizontal)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHGrid(rows: [GridItem(.fixed(40)), GridItem(.fixed(40))], spacing: 10) {
                                        ForEach(genres, id: \.1) { b, g in
                                            NavigationLink(value: Ziel.genre(b, g)) {
                                                Text(g).font(.subheadline)
                                                    .padding(.horizontal, 14).frame(height: 36)
                                                    .background(Farben.flaeche, in: Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        VStack(spacing: 0) {
                            ForEach(bibliotheken) { b in
                                NavigationLink(value: Ziel.bibliothek(b)) {
                                    Zeile(text: b.name, symbol: "books.vertical")
                                }
                            }
                            NavigationLink(value: Ziel.stoebern) {
                                Zeile(text: "Stöbern", symbol: "square.grid.2x2")
                            }
                            NavigationLink(value: Ziel.wuensche) {
                                Zeile(text: "Hörbuch wünschen", symbol: "sparkles")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical)
                }
                .refreshable { await laden(abs, neu: true) }
                .task { if bibliotheken.isEmpty { await laden(abs) } }
                .overlay {
                    if let fehler, bibliotheken.isEmpty {
                        ContentUnavailableView("Audiobookshelf nicht erreichbar", systemImage: "wifi.exclamationmark", description: Text(fehler))
                    }
                }
            } else {
                ContentUnavailableView("Keine Hörbücher eingerichtet", systemImage: "books.vertical",
                                       description: Text("Trag Audiobookshelf unter Start → Profil → Zugänge ein."))
            }
        }
        .background(Farben.hintergrund)
        .navigationTitle("Hörbücher")
    }

    private func laden(_ abs: AudiobookshelfClient, neu nachladen: Bool = false) async {
        do {
            bibliotheken = try await abs.bibliotheken()
            angefangen = try await abs.angefangen()
            // Neu und Genres aus allen Hörbuch-Bibliotheken.
            var neuAlle: [Hoerbuch] = []
            var genresAlle: [(Bibliothek, String)] = []
            for b in bibliotheken {
                neuAlle += (try? await abs.hoerbuecher(in: b.id, seite: 0, anzahl: 20, neuesteZuerst: true)) ?? []
                for g in (try? await abs.genres(in: b.id)) ?? [] where !genresAlle.contains(where: { $0.1 == g }) {
                    genresAlle.append((b, g))
                }
            }
            neu = Array(neuAlle.prefix(20))
            entdecken = await abs.entdecken(neu: nachladen)
            genres = genresAlle
            fehler = nil
        } catch {
            fehler = error.localizedDescription
        }
    }
}

/// Vorschläge von Audible; Antippen öffnet die Detailseite zum Wünschen.
struct EntdeckenReihe: View {
    let treffer: [BuchTreffer]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Entdecken").font(.title2.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(treffer) { t in
                        NavigationLink(value: t) {
                            VStack(alignment: .leading, spacing: 4) {
                                Cover(url: t.cover.flatMap(URL.init(string:)), groesse: 160)
                                Text(t.title ?? "").font(.subheadline).lineLimit(1)
                                Text(t.grund ?? t.author ?? "").font(.caption).foregroundStyle(Farben.textGedaempft).lineLimit(2)
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

private struct Zeile: View {
    let text: String
    let symbol: String

    var body: some View {
        HStack {
            Label(text, systemImage: symbol)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Farben.textGedaempft)
        }
        .padding()
        .contentShape(Rectangle())
    }
}

struct HoerbuchKarte: View {
    @Environment(Sitzung.self) private var sitzung
    let hoerbuch: Hoerbuch
    var groesse: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Cover(url: sitzung.hoerbuchClient?.coverURL(hoerbuch.id), groesse: groesse)
            Text(hoerbuch.titel).font(.subheadline).lineLimit(1)
            Text(hoerbuch.autor).font(.caption).foregroundStyle(Farben.textGedaempft).lineLimit(1)
        }
        .frame(width: groesse, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct HoerbuchReihe: View {
    let titel: String
    let hoerbuecher: [Hoerbuch]
    /// Wenn gesetzt, bietet langes Drücken „Aus Weiterhören entfernen“ an.
    var entfernen: ((Hoerbuch) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titel).font(.title2.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(hoerbuecher) { h in
                        NavigationLink(value: h) { HoerbuchKarte(hoerbuch: h) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if let entfernen {
                                    Button("Aus „Weiterhören“ entfernen", systemImage: "eye.slash") { entfernen(h) }
                                }
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct BibliothekView: View {
    @Environment(Sitzung.self) private var sitzung
    let bibliothek: Bibliothek
    var genre: String?
    @State private var hoerbuecher: [Hoerbuch] = []
    @State private var ende = false
    @State private var text = ""
    @State private var treffer: [Hoerbuch]?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 18) {
                ForEach(treffer ?? hoerbuecher) { h in
                    NavigationLink(value: h) { HoerbuchKarte(hoerbuch: h) }
                        .buttonStyle(.plain)
                        .onAppear { if treffer == nil, h.id == hoerbuecher.last?.id { Task { await nachladen() } } }
                }
            }
            .padding()
        }
        .background(Farben.hintergrund)
        .navigationTitle(genre ?? bibliothek.name)
        .safeAreaInset(edge: .top) { Suchfeld(prompt: "Titel, Autor, Sprecher", text: $text) }
        .task(id: text) {
            guard text.count >= 2, let abs = sitzung.hoerbuchClient else { treffer = nil; return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            treffer = try? await abs.suche(in: bibliothek.id, nach: text)
        }
        .task { if hoerbuecher.isEmpty { await nachladen() } }
    }

    private func nachladen() async {
        guard !ende, let abs = sitzung.hoerbuchClient,
              let neu = try? await abs.hoerbuecher(in: bibliothek.id, seite: hoerbuecher.count / 60, genre: genre) else { return }
        ende = neu.count < 60
        hoerbuecher += neu.filter { n in !hoerbuecher.contains { $0.id == n.id } }
    }
}

struct HoerbuchView: View {
    @Environment(Sitzung.self) private var sitzung
    @Environment(Player.self) private var player
    let hoerbuch: Hoerbuch
    @State private var startet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Cover(url: sitzung.hoerbuchClient?.coverURL(hoerbuch.id), groesse: 260)
                    .shadow(radius: 20)
                Text(hoerbuch.titel).font(.title2.bold()).multilineTextAlignment(.center)
                Text(hoerbuch.autor).font(.title3).foregroundStyle(Farben.blau)
                if let sprecher = hoerbuch.media.metadata.narratorName, !sprecher.isEmpty {
                    Text("Gelesen von \(sprecher)").font(.subheadline).foregroundStyle(Farben.textGedaempft)
                }
                if let reihe = hoerbuch.media.metadata.seriesName, !reihe.isEmpty {
                    Text(reihe).font(.subheadline).foregroundStyle(Farben.textGedaempft)
                }
                if let dauer = hoerbuch.media.duration {
                    Text(stundenText(dauer)).font(.caption).foregroundStyle(Farben.textGedaempft)
                }
                Button {
                    startet = true
                    Task {
                        await player.spiele(hoerbuch: hoerbuch)
                        startet = false
                    }
                } label: {
                    HStack {
                        if startet { ProgressView() } else { Image(systemName: "play.fill") }
                        Text(player.anzeige?.titel == hoerbuch.titel && player.istHoerbuch ? "Läuft" : "Abspielen")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(startet)
                if let fehler = player.fehler {
                    Text(fehler).font(.caption).foregroundStyle(.red)
                }
                if let text = hoerbuch.media.metadata.description, !text.isEmpty {
                    Text(text).font(.callout).foregroundStyle(Farben.textGedaempft).padding(.top)
                }
            }
            .padding()
        }
        .background(Farben.hintergrund)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { player.fehler = nil }
    }
}

func stundenText(_ sekunden: Double) -> String {
    let minuten = Int(sekunden / 60)
    return minuten >= 60 ? "\(minuten / 60) Std. \(minuten % 60) Min." : "\(minuten) Min."
}

// MARK: Wünschen

/// Hörbücher bei Audible suchen und über den Dienst „Hörbuchwunsch“ laden lassen.
struct WunschView: View {
    @Environment(Sitzung.self) private var sitzung
    @State private var text = ""
    @State private var treffer: [BuchTreffer] = []
    @State private var wuensche: [Wunsch] = []
    @State private var reihen: [GefolgteReihe] = []
    @State private var meldung: String?
    @State private var zurueckziehen: Wunsch?
    @State private var sucht = false

    var body: some View {
        List {
            if let meldung {
                Section { Text(meldung).font(.callout) }
            }
            if !treffer.isEmpty {
                Section("Treffer bei Audible") {
                    // Antippen öffnet die Details; erst dort wird gewünscht oder der Reihe gefolgt.
                    ForEach(treffer) { t in
                        NavigationLink(value: t) {
                            HStack(spacing: 12) {
                                Cover(url: t.cover.flatMap(URL.init(string:)), groesse: 56)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title ?? "").lineLimit(2)
                                    Text(t.author ?? "").font(.caption).foregroundStyle(Farben.textGedaempft)
                                    if let reihe = t.reihenText {
                                        Text(reihe).font(.caption).foregroundStyle(Farben.textGedaempft)
                                    }
                                    if let w = wunsch(zu: t) {
                                        Label("Gewünscht · \(w.statusText)", systemImage: "checkmark.circle.fill")
                                            .font(.caption).foregroundStyle(Farben.blau)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if !reihen.isEmpty {
                Section("Reihen, denen du folgst") {
                    ForEach(reihen) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.reihe)
                            Text([r.autor, r.stand].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(Farben.textGedaempft)
                            if let hinweis = r.hinweis { Text(hinweis).font(.caption2).foregroundStyle(Farben.textGedaempft) }
                        }
                        .swipeActions {
                            Button("Nicht mehr folgen", role: .destructive) {
                                Task {
                                    try? await sitzung.hoerbuchClient?.reiheEntfolgen(r.id)
                                    await liste()
                                }
                            }
                        }
                    }
                }
            }
            Section("Meine Wünsche") {
                if wuensche.isEmpty {
                    Text("Noch keine Wünsche.").foregroundStyle(Farben.textGedaempft)
                }
                ForEach(wuensche) { w in
                    Group {
                        // Fertige Wünsche öffnen das Hörbuch.
                        if let id = w.absItemId, w.status == "da" {
                            NavigationLink(value: Ziel.hoerbuch(id)) { WunschZeile(wunsch: w) }
                        } else {
                            WunschZeile(wunsch: w)
                        }
                    }
                    .swipeActions {
                        Button("Entfernen", role: .destructive) { zurueckziehen = w }
                        if w.status == "nicht_gefunden" || w.status == "fehler" {
                            Button("Erneut suchen") { Task { await erneut(w) } }.tint(Farben.blau)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Farben.hintergrund)
        .safeAreaInset(edge: .top) {
            Suchfeld(prompt: "Titel oder Autor bei Audible suchen", text: $text, laeuft: sucht) { Task { await suchen() } }
        }
        .navigationTitle("Hörbuch wünschen")
        .confirmationDialog("Wunsch entfernen?", isPresented: Binding(get: { zurueckziehen != nil }, set: { if !$0 { zurueckziehen = nil } }),
                            titleVisibility: .visible, presenting: zurueckziehen) { w in
            Button("Entfernen", role: .destructive) { Task { await entfernen(w) } }
        } message: { w in
            Text(w.status == "da"
                 ? "Der Eintrag verschwindet aus deiner Liste. Das Hörbuch bleibt in Audiobookshelf."
                 : "Der Wunsch wird zurückgezogen; ein laufender Download wird abgebrochen.")
        }
        .task {
            // Liste aktualisieren, solange sie offen ist.
            while !Task.isCancelled {
                await liste()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private func wunsch(zu t: BuchTreffer) -> Wunsch? {
        guard let asin = t.asin else { return nil }
        return wuensche.first { $0.asin == asin }
    }

    private func suchen() async {
        guard let abs = sitzung.hoerbuchClient, !text.isEmpty else { return }
        sucht = true
        defer { sucht = false }
        do {
            treffer = try await abs.sucheBuecher(text)
            meldung = treffer.isEmpty ? "Bei Audible nichts gefunden." : nil
        } catch {
            meldung = "Suche fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func liste() async {
        guard let abs = sitzung.hoerbuchClient else { return }
        do {
            wuensche = try await abs.wuensche()
        } catch {
            meldung = "Wunsch-Dienst nicht erreichbar: \(error.localizedDescription)"
        }
        reihen = (try? await abs.reihen()) ?? []
    }

    private func entfernen(_ w: Wunsch) async {
        try? await sitzung.hoerbuchClient?.zurueckziehen(w.id)
        await liste()
    }

    private func erneut(_ w: Wunsch) async {
        do {
            try await sitzung.hoerbuchClient?.erneutSuchen(w.id)
        } catch {
            meldung = error.localizedDescription
        }
        await liste()
    }
}

struct WunschZeile: View {
    let wunsch: Wunsch

    var body: some View {
        HStack(spacing: 12) {
            Cover(url: wunsch.coverUrl.flatMap(URL.init(string:)), groesse: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(wunsch.titel).lineLimit(1)
                Text(wunsch.statusText).font(.caption)
                    .foregroundStyle(wunsch.status == "da" ? Farben.blau : wunsch.status == "fehler" ? .red : Farben.textGedaempft)
                if let hinweis = wunsch.hinweis { Text(hinweis).font(.caption2).foregroundStyle(Farben.textGedaempft) }
            }
        }
    }
}

/// Lädt ein Hörbuch über seine ID und zeigt dann die normale Detailseite.
struct HoerbuchLaden: View {
    @Environment(Sitzung.self) private var sitzung
    let id: String
    @State private var hoerbuch: Hoerbuch?
    @State private var fehler: String?

    var body: some View {
        Group {
            if let hoerbuch {
                HoerbuchView(hoerbuch: hoerbuch)
            } else if let fehler {
                ContentUnavailableView("Hörbuch nicht gefunden", systemImage: "books.vertical", description: Text(fehler))
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Farben.hintergrund)
        .task {
            guard hoerbuch == nil, let abs = sitzung.hoerbuchClient else { return }
            do { hoerbuch = try await abs.hoerbuch(id) } catch { fehler = error.localizedDescription }
        }
    }
}

extension BuchTreffer {
    var reihenText: String? {
        guard let reihe = series?.first?.series else { return nil }
        return [reihe, series?.first?.sequence.map { "Teil \($0)" }].compactMap { $0 }.joined(separator: " – ")
    }
}

/// Details eines Audible-Treffers: erst lesen, dann wünschen oder der Reihe folgen.
struct TrefferView: View {
    @Environment(Sitzung.self) private var sitzung
    @Environment(Player.self) private var player
    let treffer: BuchTreffer
    @State private var probe: AVPlayer?
    @State private var probeLaeuft = false
    @State private var meldung: String?
    @State private var laeuft = false
    @State private var wunsch: Wunsch?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Cover(url: treffer.cover.flatMap(URL.init(string:)), groesse: 220)
                    .shadow(radius: 20)
                Text(treffer.title ?? "").font(.title2.bold()).multilineTextAlignment(.center)
                if let untertitel = treffer.subtitle, !untertitel.isEmpty {
                    Text(untertitel).font(.subheadline).multilineTextAlignment(.center)
                }
                Text(treffer.author ?? "").font(.title3).foregroundStyle(Farben.blau)
                if let sprecher = treffer.narrator, !sprecher.isEmpty {
                    Text("Gelesen von \(sprecher)").font(.subheadline).foregroundStyle(Farben.textGedaempft)
                }
                if let reihe = treffer.reihenText {
                    Text(reihe).font(.subheadline).foregroundStyle(Farben.textGedaempft)
                }
                Text([treffer.duration.map { stundenText($0 * 60) }, treffer.publishedYear, treffer.publisher]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Farben.textGedaempft)

                VStack(spacing: 10) {
                    if let wunsch, wunsch.status == "da", let id = wunsch.absItemId {
                        NavigationLink(value: Ziel.hoerbuch(id)) {
                            Label("Jetzt anhören", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else if let wunsch {
                        Label("Gewünscht · \(wunsch.statusText)", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Farben.flaeche, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(Farben.blau)
                    } else {
                        Button { Task { await wuenschen() } } label: {
                            Label("Wünschen", systemImage: "sparkles").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if treffer.asin != nil {
                        Button { Task { await hoerprobe() } } label: {
                            Label(probeLaeuft ? "Hörprobe stoppen" : "Hörprobe", systemImage: probeLaeuft ? "stop.fill" : "headphones")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    if treffer.series?.first?.series != nil {
                        Button { Task { await folgen() } } label: {
                            Label("Ganze Reihe folgen", systemImage: "books.vertical").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .controlSize(.large)
                .disabled(laeuft)
                .padding(.top, 6)

                if let meldung { Text(meldung).font(.callout).multilineTextAlignment(.center) }

                if let text = treffer.beschreibung, !text.isEmpty {
                    Text(text).font(.callout).foregroundStyle(Farben.textGedaempft).padding(.top)
                }
            }
            .padding()
        }
        .background(Farben.hintergrund)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { probe?.pause() }
        .task {
            // Stand eines vorhandenen Wunsches anzeigen und aktuell halten.
            guard let asin = treffer.asin, let abs = sitzung.hoerbuchClient else { return }
            while !Task.isCancelled {
                if let w = (try? await abs.wuensche())?.first(where: { $0.asin == asin }) { wunsch = w }
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    /// Hörprobe von Audible; die eigene Wiedergabe wird dafür angehalten.
    private func hoerprobe() async {
        if probeLaeuft {
            probe?.pause()
            probeLaeuft = false
            return
        }
        guard let asin = treffer.asin, let url = await AudibleKatalog.hoerprobe(asin) else {
            meldung = "Für dieses Hörbuch gibt es keine Hörprobe."
            return
        }
        player.pause()
        probe = AVPlayer(url: url)
        probe?.play()
        probeLaeuft = true
    }

    private func wuenschen() async {
        guard let abs = sitzung.hoerbuchClient else { return }
        laeuft = true
        defer { laeuft = false }
        do {
            switch try await abs.wuensche(treffer) {
            case .angenommen(let w):
                wunsch = w
                meldung = "Du bekommst Bescheid, sobald es da ist."
                await Benachrichtigungen.erlaubnisHolen()
            case .schonVorhanden:
                meldung = "Ist schon in deiner Bibliothek."
            }
        } catch {
            meldung = "Wünschen fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func folgen() async {
        guard let abs = sitzung.hoerbuchClient else { return }
        laeuft = true
        defer { laeuft = false }
        do {
            try await abs.folgeReihe(treffer)
            meldung = "Du folgst der Reihe. Fehlende Teile sind gewünscht, neue kommen automatisch dazu. Es laden höchstens zwei gleichzeitig."
            await Benachrichtigungen.erlaubnisHolen()
        } catch {
            meldung = error.localizedDescription
        }
    }
}
