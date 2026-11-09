import Kern
import SwiftUI

/// Laden-Knopf für Alben und Playlists: lädt alle Titel aufs iPhone oder löscht sie wieder.
struct LadenKnopf: View {
    @Environment(\.client) private var client
    let titel: [Titel]

    var body: some View {
        let offline = Offline.geteilt
        let laufend = titel.compactMap { offline.laedt("t:\($0.id)") }
        Button {
            if offline.istGeladen(titel.map(\.id)) { offline.loesche(titel: titel.map(\.id)) } else { offline.lade(titel, client) }
        } label: {
            Group {
                if !laufend.isEmpty {
                    ProgressView(value: Double(titel.count - laufend.count) / Double(max(titel.count, 1)))
                        .progressViewStyle(.circular)
                } else {
                    Label(offline.istGeladen(titel.map(\.id)) ? "Geladen" : "Laden",
                          systemImage: offline.istGeladen(titel.map(\.id)) ? "checkmark.circle.fill" : "arrow.down.circle")
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.bordered)
        .disabled(titel.isEmpty)
        .accessibilityLabel(offline.istGeladen(titel.map(\.id)) ? "Download löschen" : "Laden")
    }
}

struct HoerbuchLadenKnopf: View {
    @Environment(Sitzung.self) private var sitzung
    let hoerbuch: Hoerbuch
    @State private var fehler: String?

    var body: some View {
        let offline = Offline.geteilt
        VStack(spacing: 4) {
            if let anteil = offline.laedt("h:\(hoerbuch.id)") {
                ProgressView(value: anteil) { Text("Wird aufs iPhone geladen …").font(.caption) }
            } else if offline.hoerbuch(hoerbuch.id) != nil {
                Button(role: .destructive) { offline.loesche(hoerbuch: hoerbuch.id) } label: {
                    Label("Auf dem iPhone · Download löschen", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    Task {
                        guard let abs = sitzung.hoerbuchClient else { return }
                        do { try await offline.lade(hoerbuch: hoerbuch, abs) } catch { fehler = error.localizedDescription }
                    }
                } label: {
                    Label("Aufs iPhone laden", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if let fehler { Text(fehler).font(.caption).foregroundStyle(.red) }
        }
        .controlSize(.large)
    }
}

/// Alles, was auf dem iPhone liegt, dazu die Einstellungen für Downloads.
struct GeladenView: View {
    @Environment(Player.self) private var player
    @Environment(Sitzung.self) private var sitzung
    @State private var allesLoeschen = false

    var body: some View {
        @Bindable var offline = Offline.geteilt
        List {
            Section {
                Toggle("Gehörte Hörbücher automatisch laden", isOn: $offline.hoerbuecherAutomatisch)
                Toggle("Nur im WLAN laden", isOn: $offline.nurWLAN)
                LabeledContent("Belegt", value: ByteCountFormatter.string(fromByteCount: offline.belegt, countStyle: .file))
            } footer: {
                Text("Geladenes spielt ohne Server und ohne mobile Daten. Hörpositionen werden offline gemerkt und später an Audiobookshelf gemeldet.")
            }
            if !offline.hoerbuecher.isEmpty {
                Section("Hörbücher") {
                    ForEach(offline.hoerbuecher) { h in
                        NavigationLink(value: Ziel.hoerbuch(h.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(h.titel).lineLimit(1)
                                if let anteil = offline.laedt("h:\(h.id)") {
                                    ProgressView(value: anteil)
                                } else {
                                    Text([h.autor, stundenText(h.dauer)].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(Farben.textGedaempft)
                                }
                            }
                        }
                        .swipeActions { Button("Löschen", role: .destructive) { offline.loesche(hoerbuch: h.id) } }
                    }
                }
            }
            if !offline.titel.isEmpty {
                Section {
                    ForEach(Array(offline.titel.enumerated()), id: \.element.id) { i, t in
                        Button { player.spiele(offline.titel, ab: i) } label: { TitelZeile(titel: t) }
                            .buttonStyle(.plain)
                            .swipeActions { Button("Löschen", role: .destructive) { offline.loesche(titel: [t.id]) } }
                    }
                } header: {
                    HStack {
                        Text("Musik · \(offline.titel.count) Titel")
                        Spacer()
                        Button("Zufällig", systemImage: "shuffle") { player.spiele(offline.titel.shuffled()) }.font(.caption)
                    }
                }
            }
            if !offline.hoerbuecher.isEmpty || !offline.titel.isEmpty {
                Section { Button("Alle Downloads löschen", role: .destructive) { allesLoeschen = true } }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Farben.hintergrund)
        .navigationTitle("Geladen")
        .confirmationDialog("Alle Downloads löschen?", isPresented: $allesLoeschen, titleVisibility: .visible) {
            Button("Alles löschen", role: .destructive) { offline.loescheAlles() }
        } message: {
            Text("Musik und Hörbücher werden vom iPhone gelöscht. Auf dem Server bleibt alles.")
        }
    }
}
