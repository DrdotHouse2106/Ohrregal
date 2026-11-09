import Kern
import SwiftUI

/// Menü für einen Titel (langes Drücken, „…“ im Player).
struct TitelMenue: View {
    @Environment(\.client) private var client
    @Environment(Player.self) private var player
    @Environment(Sitzung.self) private var sitzung
    let titel: Titel

    var body: some View {
        Button("Als Nächstes spielen", systemImage: "text.line.first.and.arrowtriangle.forward") {
            Protokoll.geteilt.merke("als_naechstes", titel: titel)
            player.alsNaechstes([titel])
        }
        Button("Zur Warteschlange", systemImage: "text.line.last.and.arrowtriangle.forward") {
            Protokoll.geteilt.merke("warteschlange", titel: titel)
            player.anhaengen([titel])
        }
        Button(Mediathek.geteilt.enthaelt(titel) ? "Aus der Mediathek entfernen" : "Zur Mediathek hinzufügen",
               systemImage: Mediathek.geteilt.enthaelt(titel) ? "minus.circle" : "plus.circle") {
            Task {
                if Mediathek.geteilt.enthaelt(titel) { await Mediathek.geteilt.entfernen([titel], client) }
                else { await Mediathek.geteilt.hinzufuegen([titel], client) }
            }
        }
        Button(Favoriten.geteilt.ist(titel) ? "Gefällt mir nicht mehr" : "Gefällt mir",
               systemImage: Favoriten.geteilt.ist(titel) ? "heart.slash" : "heart") {
            Favoriten.geteilt.umschalten(titel, client)
        }
        Button("Zur Playlist hinzufügen …", systemImage: "text.badge.plus") { sitzung.playlistFuer = [titel] }
        Button("Radio ab diesem Song", systemImage: "dot.radiowaves.left.and.right") {
            Protokoll.geteilt.merke("radio", titel: titel)
            Task { player.spiele(await Mixe.radio(ab: titel, client), quelle: "Radio") }
        }
    }
}

/// Playlist wählen oder neu anlegen; die Titel gehen direkt an Navidrome.
struct PlaylistAuswahl: View {
    @Environment(\.client) private var client
    @Environment(\.dismiss) private var schliessen
    let titel: [Titel]
    @State private var playlists: [Playlist] = []
    @State private var neuOffen = false
    @State private var name = ""
    @State private var fehler: String?

    var body: some View {
        NavigationStack {
            List {
                Button { neuOffen = true } label: { Label("Neue Playlist", systemImage: "plus") }
                if let fehler { Text(fehler).foregroundStyle(.red) }
                ForEach(playlists) { p in
                    Button {
                        Task {
                            do {
                                try await client.zurPlaylist(p.id, titel: titel.map(\.id))
                                titel.forEach { Protokoll.geteilt.merke("playlist", titel: $0, wert: p.name) }
                                schliessen()
                            } catch { fehler = error.localizedDescription }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Cover(id: p.coverArt, groesse: 44)
                            Text(p.name).foregroundStyle(Farben.text)
                        }
                    }
                }
            }
            .navigationTitle("Zur Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Abbrechen") { schliessen() } }
            .alert("Neue Playlist", isPresented: $neuOffen) {
                TextField("Name", text: $name)
                Button("Anlegen") {
                    Task {
                        do {
                            try await client.neuePlaylist(name, titel: titel.map(\.id))
                            titel.forEach { Protokoll.geteilt.merke("playlist", titel: $0, wert: name) }
                            schliessen()
                        } catch { fehler = error.localizedDescription }
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            }
            .task { playlists = (try? await client.playlists()) ?? [] }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Warteschlange: antippen springt hin, ziehen sortiert um, wischen entfernt.
struct WarteschlangeView: View {
    @Environment(Player.self) private var player
    @Environment(\.dismiss) private var schliessen

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(player.warteschlange.enumerated()), id: \.offset) { i, t in
                    Button { player.springeZu(i) } label: {
                        HStack(spacing: 12) {
                            Cover(id: t.coverArt, groesse: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title).lineLimit(1)
                                    .foregroundStyle(i == player.index ? Farben.blau : i < player.index ? Farben.textGedaempft : Farben.text)
                                Text(t.artist ?? "").font(.caption).foregroundStyle(Farben.textGedaempft).lineLimit(1)
                            }
                            Spacer()
                            if i == player.index { Image(systemName: "speaker.wave.2.fill").foregroundStyle(Farben.blau) }
                        }
                    }
                    .deleteDisabled(i == player.index)
                }
                .onMove { player.verschiebe(von: $0, nach: $1) }
                .onDelete { player.entferne($0) }
            }
            .navigationTitle("Warteschlange")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { schliessen() } }
            }
        }
    }
}

/// Songtext; synchronisierte Texte laufen mit und springen beim Antippen an die Stelle.
struct SongtextView: View {
    @Environment(\.client) private var client
    @Environment(Player.self) private var player
    let titel: Titel
    @State private var zeilen: [Textzeile]?

    var body: some View {
        NavigationStack {
            ScrollViewReader { leser in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let zeilen, zeilen.isEmpty {
                            Text("Für diesen Titel gibt es keinen Songtext.").foregroundStyle(Farben.textGedaempft)
                        }
                        ForEach(Array((zeilen ?? []).enumerated()), id: \.offset) { i, z in
                            Text(z.text.isEmpty ? "♪" : z.text)
                                .font(.title2.bold())
                                .foregroundStyle(i == aktuelleZeile ? Farben.text : Farben.textGedaempft.opacity(z.start == nil ? 1 : 0.5))
                                .id(i)
                                .onTapGesture { if let start = z.start { player.springe(zu: start) } }
                        }
                    }
                    .padding()
                }
                .onChange(of: aktuelleZeile) { _, neu in
                    if let neu { withAnimation { leser.scrollTo(neu, anchor: .center) } }
                }
            }
            .background(Farben.hintergrund)
            .navigationTitle(titel.title)
            .navigationBarTitleDisplayMode(.inline)
            .overlay { if zeilen == nil { ProgressView() } }
            .task { zeilen = (try? await client.songtext(titel.id)) ?? [] }
        }
    }

    private var aktuelleZeile: Int? {
        guard let zeilen, player.aktuell?.id == titel.id else { return nil }
        return zeilen.lastIndex { ($0.start ?? .infinity) <= player.zeit + 0.3 }
    }
}
