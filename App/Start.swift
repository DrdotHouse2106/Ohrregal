import Kern
import SwiftUI

struct StartView: View {
    @Environment(\.client) private var client
    @Environment(Sitzung.self) private var sitzung
    @Environment(Player.self) private var player
    @State private var reihen: [Reihe] = []
    @State private var zufallsTitel: [Titel] = []
    @State private var fehler: String?
    @State private var zugaengeOffen = false

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
                    Task { player.spiele((try? await client.zufaelligeTitel()) ?? []) }
                } label: {
                    Label("Spiel etwas für mich", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Farben.verlauf, in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal)

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
                Button("Abmelden", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { sitzung.abmelden() }
            } label: {
                Image(systemName: "person.crop.circle")
            }
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
            async let zuletzt = client.alben("recent")
            async let haeufig = client.alben("frequent")
            async let neu = client.alben("newest")
            async let zufall = client.alben("random")
            async let titel = client.zufaelligeTitel(anzahl: 10)
            reihen = [
                Reihe(titel: "Weiterhören", alben: try await zuletzt),
                Reihe(titel: "Am häufigsten gespielt", alben: try await haeufig),
                Reihe(titel: "Kürzlich hinzugefügt", alben: try await neu),
                Reihe(titel: "Zufällige Alben", alben: try await zufall),
            ].filter { !$0.alben.isEmpty }
            zufallsTitel = try await titel
            fehler = nil
        } catch {
            fehler = error.localizedDescription
        }
    }
}
