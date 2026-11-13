import Kern
import SwiftUI

/// Internetradio: eigene Sender (aus dem Verzeichnis radio-browser.info) und Sender aus Navidrome.
struct RadioView: View {
    @Environment(\.client) private var client
    @State private var navidrome: [Sender] = []
    @State private var text = ""
    @State private var treffer: [Sender]?
    private var meine: MeineSender { .geteilt }

    var body: some View {
        List {
            if let treffer {
                Section("Gefunden") { ForEach(treffer) { SenderZeile(sender: $0) } }
            } else {
                if !meine.liste.isEmpty {
                    Section("Meine Sender") {
                        ForEach(meine.liste) { s in
                            SenderZeile(sender: s)
                                .swipeActions { Button("Entfernen", role: .destructive) { meine.umschalten(s) } }
                        }
                    }
                }
                if !navidrome.isEmpty {
                    Section("Aus Navidrome") { ForEach(navidrome) { SenderZeile(sender: $0) } }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Farben.hintergrund)
        .navigationTitle("Radio")
        .safeAreaInset(edge: .top) { Suchfeld(prompt: "Sender suchen, z. B. WDR 4", text: $text) }
        .overlay {
            if treffer?.isEmpty == true {
                ContentUnavailableView.search
            } else if treffer == nil, meine.liste.isEmpty, navidrome.isEmpty {
                ContentUnavailableView("Noch keine Sender", systemImage: "dot.radiowaves.left.and.right",
                                       description: Text("Oben einen Sender suchen und mit dem Stern merken."))
            }
        }
        .task(id: text) {
            guard text.count >= 2 else { treffer = nil; return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            treffer = (try? await RadioVerzeichnis.suche(text)) ?? []
        }
        .refreshable { navidrome = (try? await client.sender()) ?? navidrome }
        .task { navidrome = (try? await client.sender()) ?? [] }
    }
}

/// Sender mit Logo; Antippen spielt, der Stern merkt ihn unter „Meine Sender“.
struct SenderZeile: View {
    @Environment(Player.self) private var player
    let sender: Sender

    var body: some View {
        HStack(spacing: 12) {
            Button { player.spiele(sender: sender) } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: sender.bild.flatMap(URL.init(string:))) { bild in
                        bild.resizable().scaledToFit().background(.white)
                    } placeholder: {
                        Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Farben.verlauf)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(sender.name).lineLimit(2)
                        .foregroundStyle(player.anzeige?.titel == sender.name && player.istRadio ? Farben.blau : Farben.text)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Navidrome-Sender verwaltet Navidrome selbst.
            if sender.id.hasPrefix("rb-") {
                Button { MeineSender.geteilt.umschalten(sender) } label: {
                    Image(systemName: MeineSender.geteilt.enthaelt(sender) ? "star.fill" : "star").foregroundStyle(Farben.blau)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
