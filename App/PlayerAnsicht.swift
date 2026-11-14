import AVKit
import Kern
import SwiftUI

/// Mini-Player über der Tab-Leiste.
struct MiniPlayer: View {
    @Environment(Player.self) private var player
    @Binding var offen: Bool
    /// In der Tab-Leiste (iOS 26): ohne eigenen Hintergrund, die Leiste zeichnet ihn.
    var kompakt = false

    var body: some View {
        if let a = player.anzeige {
            if kompakt { inhalt(a).padding(.horizontal, 6).contentShape(Rectangle()).onTapGesture { offen = true } } else { schwebend(a) }
        }
    }

    private func schwebend(_ a: Anzeige) -> some View {
        inhalt(a)
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

    private func inhalt(_ a: Anzeige) -> some View {
            HStack(spacing: 12) {
                Cover(url: a.cover, groesse: kompakt ? 32 : 44, ganz: a.cover?.isFileURL == true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.titel).font(.subheadline.bold()).lineLimit(1)
                    Text(player.aktuellesKapitel?.title ?? a.untertitel).font(.caption).foregroundStyle(Farben.textGedaempft).lineLimit(1)
                }
                Spacer()
                Button { player.umschalten() } label: {
                    Image(systemName: player.spielt ? "pause.fill" : "play.fill").font(kompakt ? .title3 : .title2).frame(width: 44, height: 44)
                }
                Button { player.weiter() } label: {
                    Image(systemName: player.istHoerbuch ? "goforward.30" : "forward.fill").font(.title3).frame(width: 36, height: 44)
                }
            }
            .foregroundStyle(Farben.text)
    }
}

struct VollPlayer: View {
    @Environment(Player.self) private var player
    @Environment(\.client) private var client
    @Environment(Sitzung.self) private var sitzung
    @State private var ziehen: Double?
    @State private var kapitelOffen = false
    @State private var songtextOffen = false
    @State private var warteschlangeOffen = false

    var body: some View {
        @Bindable var player = player
        VStack(spacing: 24) {
            Spacer(minLength: 20)
            // Folgenbilder (aus der Datei, meist 16:9) ganz zeigen.
            Cover(url: player.anzeige?.cover, groesse: 300, ganz: player.anzeige?.cover?.isFileURL == true)
                .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
            VStack(spacing: 4) {
                // Lange Folgentitel (YouTube) ganz zeigen, notfalls etwas kleiner.
                Text(player.anzeige?.titel ?? "").font(.title2.bold()).lineLimit(4).minimumScaleFactor(0.75).multilineTextAlignment(.center)
                Text(player.anzeige?.untertitel ?? "").font(.title3).foregroundStyle(Farben.textGedaempft).lineLimit(1)
                if let k = player.aktuellesKapitel {
                    Button { kapitelOffen = true } label: {
                        Label(k.title, systemImage: "list.bullet").font(.subheadline).lineLimit(1)
                    }
                    .foregroundStyle(Farben.blau)
                }
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
                Button { player.zurueck() } label: {
                    Image(systemName: player.istHoerbuch ? "gobackward.15" : "backward.fill").font(.title)
                }
                Button { player.umschalten() } label: {
                    Image(systemName: player.spielt ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 72))
                }
                Button { player.weiter() } label: {
                    Image(systemName: player.istHoerbuch ? "goforward.30" : "forward.fill").font(.title)
                }
            }
            .foregroundStyle(Farben.text)
            HStack {
                if player.istHoerbuch {
                    Menu {
                        Picker("Geschwindigkeit", selection: $player.tempo) {
                            ForEach([0.75, 1, 1.1, 1.25, 1.5, 1.75, 2] as [Float], id: \.self) { Text(tempoText($0)).tag($0) }
                        }
                    } label: {
                        Text(tempoText(player.tempo)).font(.headline).frame(width: 60, height: 44)
                    }
                }
                if let titel = player.aktuell {
                    Button { Favoriten.geteilt.umschalten(titel, client) } label: {
                        Image(systemName: Favoriten.geteilt.ist(titel) ? "heart.fill" : "heart")
                            .font(.title3).frame(width: 44, height: 44)
                            .foregroundStyle(Favoriten.geteilt.ist(titel) ? Farben.violett : Farben.text)
                    }
                    Button { songtextOffen = true } label: {
                        Image(systemName: "quote.bubble").font(.title3).frame(width: 44, height: 44)
                    }
                    Button { warteschlangeOffen = true } label: {
                        Image(systemName: "list.bullet").font(.title3).frame(width: 44, height: 44)
                    }
                    Menu { TitelMenue(titel: titel) } label: {
                        Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44)
                    }
                }
                Spacer()
                AirPlayKnopf().frame(width: 44, height: 44)
                Spacer()
                if player.istHoerbuch {
                    Menu {
                        Button("Aus") { player.schlafen(in: nil) }
                        Button("Ende des Kapitels") { player.schlafenAmEndeDesKapitels() }
                        ForEach([15, 30, 45, 60], id: \.self) { m in Button("\(m) Minuten") { player.schlafen(in: m) } }
                    } label: {
                        Image(systemName: player.schlafenUm != nil || player.schlafenAmKapitelende ? "moon.zzz.fill" : "moon.zzz")
                            .font(.title3).frame(width: 60, height: 44)
                    }
                }
            }
            .foregroundStyle(Farben.text)
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Farben.violett.opacity(0.45), Farben.hintergrund], startPoint: .top, endPoint: .bottom))
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $kapitelOffen) { KapitelListe() }
        .sheet(isPresented: $warteschlangeOffen) { WarteschlangeView() }
        .sheet(isPresented: $songtextOffen) { if let t = player.aktuell { SongtextView(titel: t) } }
        // Auch hier, weil der Player selbst ein Blatt ist und darüber nur er etwas öffnen kann.
        .sheet(isPresented: Binding(get: { sitzung.playlistFuer != nil }, set: { if !$0 { sitzung.playlistFuer = nil } })) {
            PlaylistAuswahl(titel: sitzung.playlistFuer ?? [])
        }
    }

    private func tempoText(_ t: Float) -> String {
        (t == t.rounded() ? String(format: "%.0f", t) : String(format: "%g", t)).replacingOccurrences(of: ".", with: ",") + "×"
    }
}

struct KapitelListe: View {
    @Environment(Player.self) private var player
    @Environment(\.dismiss) private var schliessen

    var body: some View {
        NavigationStack {
            List(Array(player.kapitel.enumerated()), id: \.offset) { _, k in
                Button {
                    player.springe(zu: k.start)
                    schliessen()
                } label: {
                    HStack {
                        Text(k.title).foregroundStyle(k == player.aktuellesKapitel ? Farben.blau : Farben.text)
                        Spacer()
                        Text(dauerText(Int(k.start))).font(.caption.monospacedDigit()).foregroundStyle(Farben.textGedaempft)
                    }
                }
            }
            .navigationTitle("Kapitel")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
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
