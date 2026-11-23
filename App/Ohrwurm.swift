import Kern
import SwiftUI

/// Ohrwurm: Künstler im Apple-Katalog suchen, sehen was da ist und was fehlt, Lieder wünschen, Künstlern folgen.
struct OhrwurmView: View {
    @Environment(Sitzung.self) private var sitzung
    @State private var text = ""
    @State private var treffer: [Ohrwurm.Treffer]?
    @State private var neu: [Ohrwurm.Neuheit] = []
    @State private var gefolgt: [Ohrwurm.Gefolgt] = []
    @State private var sucht = false
    @State private var fehler: String?

    var body: some View {
        List {
            Section { Suchfeld(prompt: "Künstler suchen", text: $text, laeuft: sucht) { Task { await suchen() } } }
            if let fehler { Section { Text(fehler).foregroundStyle(.red) } }
            if let treffer {
                Section("Treffer") {
                    if treffer.isEmpty { Text("Nichts gefunden.").foregroundStyle(Farben.textGedaempft) }
                    ForEach(treffer) { t in NavigationLink(value: Ziel.ohrwurmKuenstler(t.id, t.name)) { Text(t.name) } }
                }
            }
            Section { NavigationLink { OhrwurmWunschliste() } label: { Label("Meine Wünsche", systemImage: "list.star") } }
            if !neu.isEmpty {
                Section {
                    ForEach(neu) { n in
                        NavigationLink(value: Ziel.ohrwurmKuenstler(n.kuenstlerId, n.kuenstler)) {
                            HStack(spacing: 12) {
                                Cover(url: n.cover.flatMap(URL.init(string:)), groesse: 56)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(n.name).lineLimit(2)
                                    Text([n.kuenstler, n.art, n.datum.map { String($0.prefix(10)) }].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(Farben.textGedaempft).lineLimit(1)
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Neu erschienen")
                        Spacer()
                        Button("Alle gesehen") { Task { try? await sitzung.musikwunsch?.ohrwurmGesehen(); neu = [] } }.font(.caption)
                    }
                }
            }
            if !gefolgt.isEmpty {
                Section("Ich folge") {
                    ForEach(gefolgt) { g in
                        NavigationLink(value: Ziel.ohrwurmKuenstler(g.appleId, g.name)) {
                            Label(g.name, systemImage: g.automatisch ? "bell.badge.fill" : "bell.fill")
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Farben.hintergrund)
        .navigationTitle("Ohrwurm")
        .task { await laden() }
        .refreshable { await laden() }
    }

    private func laden() async {
        guard let dienst = sitzung.musikwunsch else { return }
        do {
            async let n = dienst.ohrwurmNeuheiten()
            async let g = dienst.ohrwurmGefolgt()
            (neu, gefolgt) = try await (n, g)
            fehler = nil
        } catch {
            fehler = error.deutsch
        }
    }

    private func suchen() async {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let dienst = sitzung.musikwunsch else { return }
        sucht = true
        defer { sucht = false }
        do { treffer = try await dienst.ohrwurmSuche(t) } catch { fehler = error.deutsch }
    }
}

/// Künstlerseite wie bei Apple Music: Alben, Singles & EPs, Zusammenstellungen, Live; was da ist und was fehlt.
struct OhrwurmKuenstlerView: View {
    @Environment(Sitzung.self) private var sitzung
    let id: String
    let name: String
    @State private var seite: Ohrwurm.Kuenstler?
    @State private var fehler: String?
    @State private var meldung: String?
    @State private var alleFragen = false

    var body: some View {
        List {
            if let fehler { Section { Text(fehler).foregroundStyle(.red) } }
            if let seite {
                Section {
                    let z = seite.zahlen
                    Text("\(z.vorhanden) von \(z.lieder) Liedern da" + ((z.andereFassung ?? 0) > 0 ? ", \(z.andereFassung!) als andere Fassung" : ""))
                        .font(.callout)
                    folgenKnopf(seite)
                    if z.vorhanden + (z.andereFassung ?? 0) < z.lieder {
                        Button { alleFragen = true } label: { Label("Alle fehlenden Lieder wünschen", systemImage: "sparkles") }
                    }
                    if let meldung { Text(meldung).font(.caption).foregroundStyle(Farben.textGedaempft) }
                }
                ForEach(seite.abschnitte) { a in
                    Section(a.titel) {
                        ForEach(a.veroeffentlichungen) { v in
                            if v.lieder != nil {
                                NavigationLink { OhrwurmAlbumView(album: v) } label: { zeile(v) }
                            } else {
                                zeile(v)
                            }
                        }
                    }
                }
            } else if fehler == nil {
                Section { HStack { ProgressView(); Text("Lädt den Katalog … beim ersten Mal kann das dauern.").font(.callout) } }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Farben.hintergrund)
        .navigationTitle(name)
        .task { if seite == nil { await laden() } }
        .refreshable { await laden() }
        .confirmationDialog("Alle Lieder von \(name) wünschen, die noch fehlen?", isPresented: $alleFragen, titleVisibility: .visible) {
            Button("Wünschen") { Task { await wuenschen("kuenstler", id) } }
        } message: {
            Text("Nur aus Alben und Singles, jedes Lied einmal. Was schon da ist, wird übersprungen.")
        }
    }

    private func zeile(_ v: Ohrwurm.Veroeffentlichung) -> some View {
        HStack(spacing: 12) {
            Cover(url: v.cover.flatMap(URL.init(string:)), groesse: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(v.name).lineLimit(2)
                Text([v.jahr, v.lieder.map { "\(v.vorhanden)/\($0.count) da" } ?? v.liederGesamt.map { "\($0) Lieder" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Farben.textGedaempft)
            }
            Spacer()
            if let l = v.lieder, !l.isEmpty, v.vorhanden == l.count {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Farben.textGedaempft)
            }
        }
    }

    private func folgenKnopf(_ s: Ohrwurm.Kuenstler) -> some View {
        Menu {
            Button("Folgen – nur Hinweis bei Neuem") { Task { await folgen(an: true, automatisch: false) } }
            Button("Folgen – Neues automatisch wünschen") { Task { await folgen(an: true, automatisch: true) } }
            if s.gefolgt { Button("Nicht mehr folgen", role: .destructive) { Task { await folgen(an: false) } } }
        } label: {
            Label(s.gefolgt ? (s.automatisch ? "Du folgst · Neues wird gewünscht" : "Du folgst · Hinweis bei Neuem") : "Folgen",
                  systemImage: s.gefolgt ? "bell.fill" : "bell")
        }
    }

    private func laden() async {
        guard let dienst = sitzung.musikwunsch else { return }
        do { seite = try await dienst.ohrwurmKuenstler(id); fehler = nil } catch { fehler = error.deutsch }
    }

    private func folgen(an: Bool, automatisch: Bool = false) async {
        guard let dienst = sitzung.musikwunsch else { return }
        do { try await dienst.ohrwurmFolgen(id, an: an, automatisch: automatisch); await laden() } catch { fehler = error.deutsch }
    }

    private func wuenschen(_ art: String, _ appleId: String) async {
        guard let dienst = sitzung.musikwunsch else { return }
        meldung = "Wird gewünscht …"
        do {
            let n = try await dienst.ohrwurmWuenschen(art, appleId)
            meldung = n == 0 ? "Nichts Neues zu wünschen." : "\(n) Lieder gewünscht."
            await laden()
        } catch { meldung = error.deutsch }
    }
}

/// Lieder einer Veröffentlichung: ✓ da, ≈ andere Fassung, sonst „Wünschen“.
struct OhrwurmAlbumView: View {
    @Environment(Sitzung.self) private var sitzung
    @State var album: Ohrwurm.Veroeffentlichung
    @State private var meldung: String?

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Cover(url: album.cover.flatMap(URL.init(string:)), groesse: 110)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(album.name).font(.headline)
                        if let j = album.jahr { Text(j).foregroundStyle(Farben.textGedaempft) }
                        if (album.lieder ?? []).contains(where: { !$0.vorhanden && $0.andereFassung != true && $0.wunsch == nil }) {
                            Button("Fehlende wünschen") { Task { await wuenschen("album", album.id) } }.buttonStyle(.bordered)
                        }
                    }
                }
                if let meldung { Text(meldung).font(.caption).foregroundStyle(Farben.textGedaempft) }
            }
            Section {
                ForEach(album.lieder ?? []) { l in
                    HStack {
                        Text(l.titel).lineLimit(2)
                        Spacer()
                        if l.vorhanden {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Farben.textGedaempft)
                        } else if l.andereFassung == true {
                            Text("≈ andere Fassung").font(.caption).foregroundStyle(Farben.textGedaempft)
                        } else if let w = l.wunsch {
                            Text(w == "erledigt" ? "ist da" : w == "fehlgeschlagen" ? "noch nicht gefunden" : "gewünscht")
                                .font(.caption).foregroundStyle(Farben.blau)
                        } else if let id = l.appleId {
                            Button("Wünschen") { Task { await wuenschen("lied", id) } }.buttonStyle(.bordered).font(.caption)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Farben.hintergrund)
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func wuenschen(_ art: String, _ appleId: String) async {
        guard let dienst = sitzung.musikwunsch else { return }
        do {
            let n = try await dienst.ohrwurmWuenschen(art, appleId)
            meldung = n == 0 ? "Nichts Neues zu wünschen." : "\(n) Lieder gewünscht."
            // Stand direkt anzeigen, ohne die ganze Künstlerseite neu zu laden
            if var lieder = album.lieder {
                for i in lieder.indices where !lieder[i].vorhanden && lieder[i].andereFassung != true && lieder[i].wunsch == nil
                    && (art == "album" || lieder[i].appleId == appleId) { lieder[i].wunsch = "offen" }
                album.lieder = lieder
            }
        } catch { meldung = error.deutsch }
    }
}

/// Alle Ohrwurm-Wünsche mit Stand; Wischen zieht einen Wunsch zurück.
struct OhrwurmWunschliste: View {
    @Environment(Sitzung.self) private var sitzung
    @State private var wuensche: [Ohrwurm.Wunsch] = []
    @State private var fehler: String?

    var body: some View {
        List {
            if let fehler { Section { Text(fehler).foregroundStyle(.red) } }
            if wuensche.isEmpty { Text("Noch keine Wünsche.").foregroundStyle(Farben.textGedaempft) }
            ForEach(["offen", "in_arbeit", "fehlgeschlagen", "erledigt"], id: \.self) { stand in
                let liste = wuensche.filter { $0.stand == stand }
                if let erster = liste.first {
                    Section(erster.standText.prefix(1).uppercased() + String(erster.standText.dropFirst())) {
                        ForEach(liste) { w in
                            HStack(spacing: 12) {
                                Cover(url: w.cover.flatMap(URL.init(string:)), groesse: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(w.titel).lineLimit(1)
                                    Text([w.kuenstler, w.album, w.text].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(Farben.textGedaempft).lineLimit(2)
                                }
                            }
                            .swipeActions {
                                if w.stand != "erledigt" {
                                    Button("Zurückziehen", role: .destructive) { Task { await zurueckziehen(w) } }
                                }
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Farben.hintergrund)
        .navigationTitle("Meine Wünsche")
        .task { await laden() }
        .refreshable { await laden() }
    }

    private func laden() async {
        guard let dienst = sitzung.musikwunsch else { return }
        do { wuensche = try await dienst.ohrwurmWuensche().reversed(); fehler = nil } catch { fehler = error.deutsch }
    }

    private func zurueckziehen(_ w: Ohrwurm.Wunsch) async {
        guard let dienst = sitzung.musikwunsch else { return }
        do { try await dienst.ohrwurmZurueckziehen(w.id); wuensche.removeAll { $0.id == w.id } } catch { fehler = error.deutsch }
    }
}
