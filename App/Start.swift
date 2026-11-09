import Kern
import SwiftUI

/// Startseite im Stil von Apple Music: Gruß, Mixe mit Cover-Collage, Hörbücher weiterhören, zuletzt gespielt,
/// Schnellauswahl und die übrigen Reihen.
struct StartView: View {
    @Environment(\.client) private var client
    @Environment(Sitzung.self) private var sitzung
    @Environment(Player.self) private var player
    @State private var mixe: [Mix] = []
    @State private var hoerbuecher: [Hoerbuch] = []
    @State private var zuletzt: [Album] = []
    @State private var reihen: [Reihe] = []
    @State private var fehler: String?
    @State private var geladen = false
    @State private var zugaengeOffen = false
    @State private var ueberMichOffen = false
    @State private var mitteilungen: String?

    struct Reihe: Identifiable, Codable {
        let titel: String
        let alben: [Album]
        var id: String { titel }
    }

    var body: some View {
        // Bewusst VStack statt LazyVStack: Reihen bleiben bestehen, ihre Wischposition auch (P1).
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Button {
                    player.spiele(mixe.first?.titel.shuffled() ?? [], quelle: "Spiel etwas für mich")
                } label: {
                    Label("Spiel etwas für mich", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Farben.verlauf, in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal)
                .disabled(mixe.isEmpty)

                if !mixe.isEmpty { MixReihe(mixe: mixe) }

                if !hoerbuecher.isEmpty { HoerbuchReihe(titel: "Hörbücher weiterhören", hoerbuecher: hoerbuecher) }
                if !zuletzt.isEmpty { AlbenReihe(titel: "Zuletzt gespielt", alben: zuletzt) }

                if let titel = mixe.first?.titel, titel.count > 4 {
                    Schnellauswahl(titel: Array(titel.prefix(16)))
                }

                ForEach(reihen) { AlbenReihe(titel: $0.titel, alben: $0.alben) }
            }
            .padding(.vertical)
        }
        .background(Farben.hintergrund)
        .navigationTitle(gruss)
        .toolbar {
            Menu {
                Button("Zugänge", systemImage: "key") { zugaengeOffen = true }
                Button("Mitteilungen", systemImage: "bell") {
                    Task { mitteilungen = await Benachrichtigungen.einschaltenUndPruefen() }
                }
                Button("Was Ohrregal über mich weiß", systemImage: "person.text.rectangle") { ueberMichOffen = true }
                Button("Abmelden", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { sitzung.abmelden() }
            } label: {
                Image(systemName: "person.crop.circle")
            }
        }
        .navigationDestination(isPresented: $ueberMichOffen) { UeberMichView() }
        .alert("Mitteilungen", isPresented: Binding(get: { mitteilungen != nil }, set: { if !$0 { mitteilungen = nil } })) {
            Button("OK") {}
        } message: {
            Text(mitteilungen ?? "")
        }
        .sheet(isPresented: $zugaengeOffen) { Anmeldung() }
        .refreshable { await laden(neu: true) }
        .task { await laden() }
        .overlay {
            if let fehler, reihen.isEmpty {
                ContentUnavailableView("Server nicht erreichbar", systemImage: "wifi.exclamationmark", description: Text(fehler))
            } else if !geladen {
                ProgressView()
            }
        }
    }

    private var gruss: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: "Guten Morgen"
        case 11..<17: "Hallo"
        case 17..<23: "Guten Abend"
        default: "Gute Nacht"
        }
    }

    /// Zeigt zuerst den Vorrat (sofort), rechnet nur neu, wenn er älter als 6 Stunden ist oder neu gewünscht.
    private func laden(neu: Bool = false) async {
        if !geladen, let vorrat = StartVorrat.laden() { anwenden(vorrat) }
        hoerbuecher = (try? await sitzung.hoerbuchClient?.angefangen()) ?? hoerbuecher
        if !neu, let vorrat = StartVorrat.laden(), Date().timeIntervalSince(vorrat.zeit) < 6 * 3600 { return }
        do {
            let vorrat = try await StartVorrat.berechnen(client)
            vorrat.speichern()
            anwenden(vorrat)
            fehler = nil
        } catch {
            fehler = error.localizedDescription
            geladen = true
        }
    }

    private func anwenden(_ vorrat: StartVorrat) {
        zuletzt = vorrat.zuletzt
        reihen = vorrat.reihen
        mixe = vorrat.mixe
        geladen = true
    }
}

/// Ein fertig geladener Mix; so startet er beim Antippen sofort und zeigt seine Cover.
struct Mix: Identifiable, Codable {
    let id: String
    let name: String
    let untertitel: String
    let titel: [Titel]

    /// Cover der ersten vier verschiedenen Alben für die Collage.
    var cover: [String] {
        var gesehen = Set<String>()
        return titel.compactMap { t in
            guard let c = t.coverArt, gesehen.insert(t.albumId ?? c).inserted else { return nil }
            return c
        }
        .prefix(4).map { $0 }
    }

    /// „Dein Mix“ aus den Lieblingskünstlern und ein Mix pro Künstler.
    @MainActor static func laden(_ client: NavidromeClient, haeufig: [Album]) async -> [Mix] {
        var kuenstler = Hoerverlauf.geteilt.topKuenstler(anzahl: 6)
        // Ohne Verlauf: Künstler der häufig gespielten Alben.
        for a in haeufig where kuenstler.count < 6 && !kuenstler.contains(where: { $0.id == a.artistId }) {
            if let id = a.artistId, let name = a.artist { kuenstler.append(Kuenstler(id: id, name: name)) }
        }
        var einzeln: [Mix] = []
        await withTaskGroup(of: (Int, [Titel]).self) { gruppe in
            for (i, k) in kuenstler.enumerated() {
                gruppe.addTask { (i, (try? await client.aehnlicheTitel(k.id, anzahl: 40)) ?? []) }
            }
            var ergebnis: [(Int, [Titel])] = []
            for await e in gruppe { ergebnis.append(e) }
            for (i, titel) in ergebnis.sorted(by: { $0.0 < $1.0 }) where !titel.isEmpty {
                einzeln.append(Mix(id: kuenstler[i].id, name: "\(kuenstler[i].name) Mix", untertitel: "Mit ähnlichen Künstlern",
                                   titel: Mixe.bereinigt(titel).shuffled()))
            }
        }
        var dein = Mixe.bereinigt(einzeln.flatMap { Array($0.titel.prefix(12)) }).shuffled()
        if dein.count < 20 { dein += (try? await client.zufaelligeTitel(anzahl: 40)) ?? [] }
        return [Mix(id: "dein", name: "Dein Mix", untertitel: "Aus deinen Lieblingskünstlern", titel: dein)] + einzeln
    }
}

struct MixReihe: View {
    @Environment(Player.self) private var player
    let mixe: [Mix]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Für dich").font(.title2.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(mixe) { mix in
                        Button { player.spiele(mix.titel, quelle: "Mix: \(mix.name)") } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Collage(cover: mix.cover)
                                    .overlay(alignment: .bottomLeading) {
                                        Text(mix.name).font(.headline).foregroundStyle(.white).lineLimit(2)
                                            .padding(10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(mix.untertitel).font(.caption).foregroundStyle(Farben.textGedaempft).lineLimit(1)
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

/// Vier Cover im Quadrat; bei weniger Covern füllt der Quallen-Verlauf.
struct Collage: View {
    let cover: [String]

    var body: some View {
        let raster = [GridItem(.fixed(80), spacing: 0), GridItem(.fixed(80), spacing: 0)]
        ZStack {
            Farben.verlauf
            if cover.count >= 4 {
                LazyVGrid(columns: raster, spacing: 0) {
                    ForEach(cover, id: \.self) { Cover(id: $0, groesse: 80).clipShape(Rectangle()) }
                }
            } else if let erstes = cover.first {
                Cover(id: erstes, groesse: 160)
            }
        }
        .frame(width: 160, height: 160)
    }
}

/// Schnellauswahl: Titel in Spalten zu je vier, seitlich wischbar.
struct Schnellauswahl: View {
    @Environment(Player.self) private var player
    let titel: [Titel]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Schnellauswahl").font(.title2.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(56), spacing: 6), count: 4), spacing: 16) {
                    ForEach(Array(titel.enumerated()), id: \.offset) { i, t in
                        Button { player.spiele(titel, ab: i, quelle: "Schnellauswahl") } label: {
                            HStack(spacing: 10) {
                                Cover(id: t.coverArt, groesse: 48)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title).lineLimit(1)
                                    Text(t.artist ?? "").font(.caption).foregroundStyle(Farben.textGedaempft).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(width: 280)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { TitelMenue(titel: t) }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
