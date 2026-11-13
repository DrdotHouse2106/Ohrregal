import Kern
import SwiftUI

/// Internetradio. Mit eigenem Dienst liegen die Sender in Navidrome (für alle Geräte gleich),
/// sonst lokal unter „Meine Sender“. Gesucht wird im Verzeichnis radio-browser.info.
struct RadioView: View {
    @Environment(\.client) private var client
    @Environment(Sitzung.self) private var sitzung
    @State private var navidrome: [Sender] = []
    /// Sender über den Dienst (mit Logo und „von mir“); nil = Dienst nicht eingerichtet.
    @State private var server: [MusikwunschClient.ServerSender]?
    @State private var text = ""
    @State private var treffer: [Sender]?
    @State private var fehler: String?
    private var meine: MeineSender { .geteilt }

    var body: some View {
        List {
            if let fehler { Text(fehler).font(.callout) }
            if let treffer {
                Section("Gefunden") {
                    ForEach(treffer) { s in SenderZeile(sender: s, gemerkt: gemerkt(s)) { Task { await merken(s) } } }
                }
            } else if let server {
                if !server.isEmpty {
                    Section("Sender") {
                        ForEach(server) { s in
                            SenderZeile(sender: s.sender)
                                .swipeActions {
                                    if s.vonMir == true {
                                        Button("Entfernen", role: .destructive) { Task { await entfernen(s) } }
                                    }
                                }
                        }
                    }
                }
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
            } else if treffer == nil, server?.isEmpty ?? (meine.liste.isEmpty && navidrome.isEmpty) {
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
        .refreshable { await laden() }
        .task { await laden() }
    }

    private func gemerkt(_ s: Sender) -> Bool {
        if let server { return server.contains { MeineSender.gleich($0.streamUrl, s.streamUrl) } }
        return meine.enthaelt(s)
    }

    private func merken(_ s: Sender) async {
        guard let server, let dienst = sitzung.musikwunsch else { meine.umschalten(s); return }
        if let vorhanden = server.first(where: { MeineSender.gleich($0.streamUrl, s.streamUrl) }) {
            if vorhanden.vonMir == true { await entfernen(vorhanden) }
            return
        }
        do { try await dienst.senderAnlegen(s); await laden() } catch { fehler = "Sender nicht gespeichert: \(error.deutsch)" }
    }

    private func entfernen(_ s: MusikwunschClient.ServerSender) async {
        do { try await sitzung.musikwunsch?.senderLoeschen(s.id); await laden() } catch { fehler = "Nicht entfernt: \(error.deutsch)" }
    }

    private func laden() async {
        if sitzung.dienstDa, let dienst = sitzung.musikwunsch, let antwort = try? await dienst.sender(), antwort.eingerichtet {
            if !meine.liste.isEmpty {
                await meine.uebertragen(dienst)
                server = (try? await dienst.sender())?.liste ?? antwort.liste
            } else {
                server = antwort.liste
            }
            fehler = nil
        } else {
            server = nil
            navidrome = (try? await client.sender()) ?? navidrome
        }
    }
}

/// Sender mit Logo; Antippen spielt. Mit `merken` gibt es einen Stern.
struct SenderZeile: View {
    @Environment(Player.self) private var player
    let sender: Sender
    var gemerkt = false
    var merken: (() -> Void)?

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
            if let merken {
                Button(action: merken) {
                    Image(systemName: gemerkt ? "star.fill" : "star").foregroundStyle(Farben.blau)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
