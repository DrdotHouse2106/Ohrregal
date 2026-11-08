import Kern
import SwiftUI

struct HoerbuecherView: View {
    @Environment(Sitzung.self) private var sitzung
    @State private var angefangen: [Hoerbuch] = []
    @State private var bibliotheken: [Bibliothek] = []
    @State private var fehler: String?

    var body: some View {
        Group {
            if let abs = sitzung.hoerbuchClient {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if !angefangen.isEmpty {
                            HoerbuchReihe(titel: "Weiterhören", hoerbuecher: angefangen)
                        }
                        VStack(spacing: 0) {
                            ForEach(bibliotheken) { b in
                                NavigationLink(value: Ziel.bibliothek(b)) {
                                    Zeile(text: b.name, symbol: "books.vertical")
                                }
                            }
                            NavigationLink(value: Ziel.wuensche) {
                                Zeile(text: "Hörbuch wünschen", symbol: "sparkles")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical)
                }
                .refreshable { await laden(abs) }
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

    private func laden(_ abs: AudiobookshelfClient) async {
        do {
            bibliotheken = try await abs.bibliotheken()
            angefangen = try await abs.angefangen()
            fehler = nil
        } catch {
            fehler = error.localizedDescription
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titel).font(.title2.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(hoerbuecher) { h in
                        NavigationLink(value: h) { HoerbuchKarte(hoerbuch: h) }
                            .buttonStyle(.plain)
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
        .navigationTitle(bibliothek.name)
        .searchable(text: $text, prompt: "Titel, Autor, Sprecher")
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
              let neu = try? await abs.hoerbuecher(in: bibliothek.id, seite: hoerbuecher.count / 60) else { return }
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
    @State private var meldung: String?
    @State private var zurueckziehen: Wunsch?

    var body: some View {
        List {
            if let meldung {
                Section { Text(meldung).font(.callout) }
            }
            if !treffer.isEmpty {
                Section("Treffer bei Audible") {
                    ForEach(treffer) { t in
                        HStack(spacing: 12) {
                            Cover(url: t.cover.flatMap(URL.init(string:)), groesse: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title ?? "").lineLimit(2)
                                Text(t.author ?? "").font(.caption).foregroundStyle(Farben.textGedaempft)
                                if let reihe = t.series?.first?.series {
                                    Text([reihe, t.series?.first?.sequence].compactMap { $0 }.joined(separator: " – "))
                                        .font(.caption).foregroundStyle(Farben.textGedaempft)
                                }
                            }
                            Spacer()
                            Button("Wünschen") { Task { await wuenschen(t) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            Section("Meine Wünsche") {
                if wuensche.isEmpty {
                    Text("Noch keine Wünsche.").foregroundStyle(Farben.textGedaempft)
                }
                ForEach(wuensche) { w in
                    HStack(spacing: 12) {
                        Cover(url: w.coverUrl.flatMap(URL.init(string:)), groesse: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.titel).lineLimit(1)
                            Text(w.statusText).font(.caption)
                                .foregroundStyle(w.status == "da" ? Farben.blau : w.status == "fehler" ? .red : Farben.textGedaempft)
                            if let hinweis = w.hinweis { Text(hinweis).font(.caption2).foregroundStyle(Farben.textGedaempft) }
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
        .navigationTitle("Hörbuch wünschen")
        .searchable(text: $text, prompt: "Titel oder Autor bei Audible suchen")
        .onSubmit(of: .search) { Task { await suchen() } }
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

    private func suchen() async {
        guard let abs = sitzung.hoerbuchClient, !text.isEmpty else { return }
        do {
            treffer = try await abs.sucheBuecher(text)
            meldung = treffer.isEmpty ? "Bei Audible nichts gefunden." : nil
        } catch {
            meldung = "Suche fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func wuenschen(_ t: BuchTreffer) async {
        guard let abs = sitzung.hoerbuchClient else { return }
        do {
            switch try await abs.wuensche(t) {
            case .angenommen: meldung = "„\(t.title ?? "")“ ist gewünscht. Du bekommst Bescheid, sobald es da ist."
            case .schonVorhanden: meldung = "„\(t.title ?? "")“ ist schon in deiner Bibliothek."
            }
            await liste()
        } catch {
            meldung = "Wünschen fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func liste() async {
        guard let abs = sitzung.hoerbuchClient else { return }
        do {
            wuensche = try await abs.wuensche()
        } catch {
            meldung = "Wunsch-Dienst nicht erreichbar: \(error.localizedDescription)"
        }
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
