import Kern
import SwiftUI

struct SucheView: View {
    @Environment(\.client) private var client
    @State private var text = ""
    @State private var ergebnis: Suchergebnis?

    var body: some View {
        ErgebnisAnsicht(ergebnis: ergebnis)
            .navigationTitle("Suchen")
            .safeAreaInset(edge: .top) { Suchfeld(prompt: "Künstler, Alben, Titel", text: $text) }
            .task(id: text) {
                guard text.count >= 2 else { ergebnis = nil; return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                ergebnis = try? await client.suche(text)
            }
    }
}

struct ErgebnisAnsicht: View {
    let ergebnis: Suchergebnis?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let k = ergebnis?.artist, !k.isEmpty { KuenstlerReihe(kuenstler: k) }
                if let a = ergebnis?.album, !a.isEmpty { AlbenReihe(titel: "Alben", alben: a) }
                if let t = ergebnis?.song, !t.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Titel").font(.title2.bold()).padding(.horizontal)
                        TitelListe(titel: t)
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Farben.hintergrund)
        .overlay {
            if ergebnis?.istLeer == true { ContentUnavailableView.search }
        }
    }
}
