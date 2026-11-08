import Kern
import SwiftUI

struct StartView: View {
    @Environment(\.client) private var client
    @Environment(Sitzung.self) private var sitzung
    @Environment(Player.self) private var player
    @State private var reihen: [Reihe] = []
    @State private var mixKuenstler: [Kuenstler] = []
    @State private var zufallsTitel: [Titel] = []
    @State private var fehler: String?
    @State private var zugaengeOffen = false
    @State private var verlaufLoeschen = false
    @State private var mitteilungen: String?

    struct Reihe: Identifiable {
        let titel: String
        let alben: [Album]
        var id: String { titel }
    }

    var body: some View {
        // Bewusst VStack statt LazyVStack: Reihen bleiben bestehen, ihre Wischposition auch (P1).
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Button {
                    Task { player.spiele(await Mixe.deinMix(client, kuenstler: mixKuenstler)) }
                } label: {
                    Label("Spiel etwas für mich", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Farben.verlauf, in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal)

                if !mixKuenstler.isEmpty { MixReihe(kuenstler: mixKuenstler) }

                ForEach(reihen) { AlbenReihe(titel: $0.titel, alben: $0.alben) }

                if !zufallsTitel.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Zufällige Titel").font(.title2.bold()).padding(.horizontal)
                        TitelListe(titel: zufallsTitel)
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Farben.hintergrund)
        .navigationTitle("Start")
        .toolbar {
            Menu {
                Button("Zugänge", systemImage: "key") { zugaengeOffen = true }
                Button("Mitteilungen", systemImage: "bell") {
                    Task { mitteilungen = await Benachrichtigungen.einschaltenUndPruefen() }
                }
                Button("Hörverlauf löschen", systemImage: "clock.arrow.circlepath") { verlaufLoeschen = true }
                Button("Abmelden", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { sitzung.abmelden() }
            } label: {
                Image(systemName: "person.crop.circle")
            }
        }
        .confirmationDialog("Hörverlauf löschen?", isPresented: $verlaufLoeschen, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { Hoerverlauf.geteilt.loeschen() }
        } message: {
            Text("Der Verlauf liegt nur auf diesem iPhone und bestimmt deine Mixe. Last.fm und Navidrome bleiben unverändert.")
        }
        .alert("Mitteilungen", isPresented: Binding(get: { mitteilungen != nil }, set: { if !$0 { mitteilungen = nil } })) {
            Button("OK") {}
        } message: {
            Text(mitteilungen ?? "")
        }
        .sheet(isPresented: $zugaengeOffen) { Anmeldung() }
        .refreshable { await laden() }
        .task { if reihen.isEmpty { await laden() } }
        .overlay {
            if let fehler, reihen.isEmpty {
                ContentUnavailableView("Server nicht erreichbar", systemImage: "wifi.exclamationmark", description: Text(fehler))
            }
        }
    }

    private func laden() async {
        do {
            async let zuletzt = client.alben("recent", anzahl: 50)
            async let haeufig = client.alben("frequent", anzahl: 50)
            async let neu = client.alben("newest")
            async let zufall = client.alben("random")
            async let titel = client.zufaelligeTitel(anzahl: 10)
            let zuletztGehoert = try await zuletzt
            let oft = try await haeufig
            // Lange nicht gehört: oft gespielt, aber nicht unter den letzten 50.
            let kuerzlich = Set(zuletztGehoert.map(\.id))
            let langeNicht = oft.filter { !kuerzlich.contains($0.id) }
            reihen = [
                Reihe(titel: "Weiterhören", alben: Array(zuletztGehoert.prefix(20))),
                Reihe(titel: "Am häufigsten gespielt", alben: Array(oft.prefix(20))),
                Reihe(titel: "Lange nicht gehört", alben: Array(langeNicht.prefix(20))),
                Reihe(titel: "Kürzlich hinzugefügt", alben: try await neu),
                Reihe(titel: "Zufällige Alben", alben: try await zufall),
            ].filter { !$0.alben.isEmpty }
            // Mixe: meistgehörte Künstler aus dem Verlauf, sonst aus den häufig gespielten Alben.
            var kuenstler = Hoerverlauf.geteilt.topKuenstler(anzahl: 6)
            if kuenstler.count < 4 {
                for a in oft where !kuenstler.contains(where: { $0.id == a.artistId }) {
                    if let id = a.artistId, let name = a.artist { kuenstler.append(Kuenstler(id: id, name: name)) }
                    if kuenstler.count >= 6 { break }
                }
            }
            mixKuenstler = kuenstler
            zufallsTitel = try await titel
            fehler = nil
        } catch {
            fehler = error.localizedDescription
        }
    }
}

/// „Für dich“: Dein Mix und ein Radio pro Lieblingskünstler.
struct MixReihe: View {
    @Environment(\.client) private var client
    @Environment(Player.self) private var player
    let kuenstler: [Kuenstler]
    @State private var laedt: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Für dich").font(.title2.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    karte("Dein Mix", unter: "Aus deinen Lieblingskünstlern", id: "mix") {
                        await Mixe.deinMix(client, kuenstler: kuenstler)
                    }
                    ForEach(kuenstler) { k in
                        karte("\(k.name) Radio", unter: "Mit ähnlichen Künstlern", id: k.id) {
                            await Mixe.radio(kuenstler: k.id, client)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func karte(_ titel: String, unter: String, id: String, titelLaden: @escaping @MainActor () async -> [Titel]) -> some View {
        Button {
            laedt = id
            Task {
                player.spiele(await titelLaden())
                laedt = nil
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 8).fill(Farben.verlauf)
                    if laedt == id {
                        ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text(titel).font(.title3.bold()).foregroundStyle(.white).lineLimit(3).padding(12)
                    }
                }
                .frame(width: 160, height: 160)
                Text(unter).font(.caption).foregroundStyle(Farben.textGedaempft).lineLimit(1)
            }
            .frame(width: 160, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(laedt != nil)
    }
}
