import AVKit
import Kern
import SwiftUI

/// Mini-Player über der Tab-Leiste.
struct MiniPlayer: View {
    @Environment(Player.self) private var player
    @Binding var offen: Bool

    var body: some View {
        if let titel = player.aktuell {
            HStack(spacing: 12) {
                Cover(id: titel.coverArt, groesse: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titel.title).font(.subheadline.bold()).lineLimit(1)
                    Text(titel.artist ?? "").font(.caption).foregroundStyle(Farben.textGedaempft).lineLimit(1)
                }
                Spacer()
                Button { player.umschalten() } label: {
                    Image(systemName: player.spielt ? "pause.fill" : "play.fill").font(.title2).frame(width: 44, height: 44)
                }
                Button { player.weiter() } label: {
                    Image(systemName: "forward.fill").font(.title3).frame(width: 36, height: 44)
                }
            }
            .foregroundStyle(Farben.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Farben.flaeche, in: RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .bottom) {
                GeometryReader { g in
                    Capsule().fill(Farben.verlauf)
                        .frame(width: g.size.width * min(player.zeit / max(player.dauer, 1), 1), height: 3)
                }
                .frame(height: 3)
                .padding(.horizontal, 12)
            }
            .contentShape(Rectangle())
            .onTapGesture { offen = true }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
    }
}

struct VollPlayer: View {
    @Environment(Player.self) private var player
    @State private var ziehen: Double?

    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 20)
            Cover(id: player.aktuell?.coverArt, groesse: 320)
                .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
            VStack(spacing: 4) {
                Text(player.aktuell?.title ?? "").font(.title2.bold()).lineLimit(1)
                Text(player.aktuell?.artist ?? "").font(.title3).foregroundStyle(Farben.textGedaempft).lineLimit(1)
            }
            VStack(spacing: 4) {
                Slider(value: Binding(get: { ziehen ?? player.zeit }, set: { ziehen = $0 }),
                       in: 0...max(player.dauer, 1), onEditingChanged: { laeuft in
                    if !laeuft, let ziel = ziehen {
                        player.springe(zu: ziel)
                        ziehen = nil
                    }
                })
                HStack {
                    Text(dauerText(Int(ziehen ?? player.zeit)))
                    Spacer()
                    Text("-" + dauerText(Int(max(player.dauer - (ziehen ?? player.zeit), 0))))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(Farben.textGedaempft)
            }
            HStack(spacing: 50) {
                Button { player.zurueck() } label: { Image(systemName: "backward.fill").font(.title) }
                Button { player.umschalten() } label: {
                    Image(systemName: player.spielt ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 72))
                }
                Button { player.weiter() } label: { Image(systemName: "forward.fill").font(.title) }
            }
            .foregroundStyle(Farben.text)
            AirPlayKnopf().frame(width: 44, height: 44)
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Farben.violett.opacity(0.45), Farben.hintergrund], startPoint: .top, endPoint: .bottom))
        .presentationDragIndicator(.visible)
    }
}

struct AirPlayKnopf: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let knopf = AVRoutePickerView()
        knopf.tintColor = .white
        knopf.activeTintColor = UIColor(Farben.blau)
        return knopf
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
