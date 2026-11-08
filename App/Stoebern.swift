import Kern
import SwiftUI

/// Audible-Kategorien; vorn „Hörspiele“, die der Dienst eigens zusammenstellt.
struct StoebernView: View {
    @Environment(Sitzung.self) private var sitzung
    @State private var kategorien: [Kategorie] = []
    @State private var fehler: String?

    var body: some View {
        List(kategorien) { k in
            NavigationLink(value: Ziel.kategorie(k)) {
                Label(k.name, systemImage: symbol(k))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Farben.hintergrund)
        .navigationTitle("Stöbern")
        .overlay {
            if let fehler {
                ContentUnavailableView("Kategorien nicht erreichbar", systemImage: "wifi.exclamationmark", description: Text(fehler))
            } else if kategorien.isEmpty {
                ProgressView()
            }
        }
        .task {
            guard kategorien.isEmpty, let abs = sitzung.hoerbuchClient else { return }
            do { kategorien = try await abs.kategorien() } catch { fehler = error.localizedDescription }
        }
    }

    private func symbol(_ k: Kategorie) -> String {
        let n = k.name.lowercased()
        if k.id == "hoerspiele" { return "theatermasks" }
        if n.contains("krimi") || n.contains("thriller") { return "magnifyingglass" }
        if n.contains("wissenschaft") || n.contains("computer") { return "atom" }
        if n.contains("geschichte") { return "building.columns" }
        if n.contains("wirtschaft") || n.contains("karriere") { return "briefcase" }
        if n.contains("kinder") || n.contains("jugend") { return "figure.and.child.holdinghands" }
        if n.contains("fantasy") || n.contains("science") { return "sparkles" }
        return "book"
    }
}

/// Beliebte oder neue Hörbücher einer Kategorie, dazu ihre Unterkategorien.
struct KategorieView: View {
    @Environment(Sitzung.self) private var sitzung
    let kategorie: Kategorie
    @State private var neueste = false
    @State private var treffer: [BuchTreffer] = []
    @State private var laedt = false
    @State private var fehler: String?

    var body: some View {
        List {
            if let unter = kategorie.unter, !unter.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(unter) { u in
                                NavigationLink(value: Ziel.kategorie(u)) {
                                    Text(u.name).font(.subheadline)
                                        .padding(.horizontal, 14).frame(height: 36)
                                        .background(Farben.flaeche, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
            Section {
                Picker("Sortierung", selection: $neueste) {
                    Text("Beliebt").tag(false)
                    Text("Neu").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            Section {
                if let fehler {
                    Text(fehler).foregroundStyle(.red)
                } else if laedt && treffer.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if treffer.isEmpty {
                    Text("Nichts Neues – alles schon da oder gewünscht.").foregroundStyle(Farben.textGedaempft)
                }
                ForEach(treffer) { t in
                    NavigationLink(value: t) {
                        HStack(spacing: 12) {
                            Cover(url: t.cover.flatMap(URL.init(string:)), groesse: 64)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title ?? "").lineLimit(2)
                                Text(t.author ?? "").font(.caption).foregroundStyle(Farben.textGedaempft).lineLimit(1)
                                if let reihe = t.reihenText {
                                    Text(reihe).font(.caption).foregroundStyle(Farben.textGedaempft).lineLimit(1)
                                }
                                if let dauer = t.duration {
                                    Text(stundenText(dauer * 60)).font(.caption2).foregroundStyle(Farben.textGedaempft)
                                }
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Farben.hintergrund)
        .navigationTitle(kategorie.name)
        .refreshable { await laden(neu: true) }
        .task(id: neueste) { await laden() }
    }

    private func laden(neu: Bool = false) async {
        guard let abs = sitzung.hoerbuchClient else { return }
        laedt = true
        defer { laedt = false }
        if !neu { treffer = [] }
        do {
            treffer = try await abs.stoebern(kategorie.id, neueste: neueste, neu: neu)
            fehler = nil
        } catch {
            fehler = error.localizedDescription
        }
    }
}
