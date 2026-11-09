import Kern
import SwiftUI

/// Internetradio-Sender aus Navidrome (eingerichtet in der Navidrome-Weboberfläche).
struct RadioView: View {
    @Environment(\.client) private var client
    @Environment(Player.self) private var player
    @State private var sender: [Sender]?

    var body: some View {
        List(sender ?? []) { s in
            Button { player.spiele(sender: s) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .frame(width: 44, height: 44)
                        .background(Farben.verlauf, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white)
                    Text(s.name).foregroundStyle(player.anzeige?.titel == s.name && player.istRadio ? Farben.blau : Farben.text)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Farben.hintergrund)
        .navigationTitle("Radio")
        .overlay {
            if sender == nil {
                ProgressView()
            } else if sender?.isEmpty == true {
                ContentUnavailableView("Keine Sender", systemImage: "dot.radiowaves.left.and.right",
                                       description: Text("Internetradio-Sender werden in der Navidrome-Weboberfläche eingerichtet."))
            }
        }
        .refreshable { sender = (try? await client.sender()) ?? [] }
        .task { if sender == nil { sender = (try? await client.sender()) ?? [] } }
    }
}
