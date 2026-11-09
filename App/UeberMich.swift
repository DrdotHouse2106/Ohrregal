import Kern
import SwiftUI

/// „Was Ohrregal über mich weiß“: das Hörprotokoll einsehen und löschen.
struct UeberMichView: View {
    @Environment(Sitzung.self) private var sitzung
    @State private var gesamt = 0
    @State private var eintraege: [MusikwunschClient.ProtokollEintrag] = []
    @State private var fehler: String?
    @State private var loeschen = false
    @State private var letzterVersuch = UserDefaults.standard.string(forKey: "protokollLetzterVersuch")

    var body: some View {
        List {
            Section {
                Text("Ohrregal merkt sich, was du hörst, überspringst, mit einem Herz markierst, suchst und wünschst, dazu Uhrzeit, Gerät und Ausgabe (z. B. Kopfhörer oder Auto). Daraus entstehen deine Vorschläge – sonst nichts.")
                Text("Liegt nur auf deinem eigenen Server und in dessen nächtlicher Sicherung bei Hetzner in Deutschland. Wird an niemanden weitergegeben.")
                    .font(.callout).foregroundStyle(Farben.textGedaempft)
            }
            Section {
                LabeledContent("Ereignisse auf dem Server", value: "\(gesamt)")
                LabeledContent("Noch auf diesem iPhone", value: "\(Protokoll.geteilt.offenAnzahl)")
                LabeledContent("Hörverlauf für Mixe (nur hier)", value: "\(Hoerverlauf.geteilt.ereignisse.count)")
            }
            Section {
                Text(letzterVersuch ?? "Noch kein Sendeversuch.").font(.caption).foregroundStyle(Farben.textGedaempft)
                Button("Jetzt senden", systemImage: "arrow.up.circle") { Task { await laden() } }
            } header: {
                Text("Letzter Sendeversuch")
            }
            if let fehler { Section { Text(fehler).foregroundStyle(.red) } }
            if !eintraege.isEmpty {
                Section("Zuletzt") {
                    ForEach(eintraege) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(beschreibung(e)).lineLimit(2)
                            Text([e.datum.map { $0.formatted(date: .abbreviated, time: .shortened) }, e.quelle, e.geraet, e.ausgabe]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(Farben.textGedaempft)
                        }
                    }
                }
            }
            Section {
                Button("Alles löschen", role: .destructive) { loeschen = true }
            } footer: {
                Text("Löscht das Protokoll auf dem Server und den Hörverlauf auf diesem iPhone. Last.fm und die Wiedergabezähler in Navidrome bleiben unverändert.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Farben.hintergrund)
        .navigationTitle("Was Ohrregal über mich weiß")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await laden() }
        .task { await laden() }
        .confirmationDialog("Alles löschen?", isPresented: $loeschen, titleVisibility: .visible) {
            Button("Protokoll und Verlauf löschen", role: .destructive) { Task { await allesLoeschen() } }
        } message: {
            Text("Deine Vorschläge fangen danach wieder von vorn an.")
        }
    }

    private func laden() async {
        await Protokoll.geteilt.abschicken()
        letzterVersuch = UserDefaults.standard.string(forKey: "protokollLetzterVersuch")
        guard let dienst = sitzung.musikwunsch else { return }
        do {
            let ergebnis = try await dienst.protokoll()
            gesamt = ergebnis.gesamt
            eintraege = ergebnis.eintraege
            fehler = nil
        } catch {
            fehler = error.localizedDescription
        }
    }

    private func allesLoeschen() async {
        Protokoll.geteilt.offeneVerwerfen()
        Hoerverlauf.geteilt.loeschen()
        do { try await sitzung.musikwunsch?.protokollLoeschen() } catch { fehler = error.localizedDescription }
        await laden()
    }

    private func beschreibung(_ e: MusikwunschClient.ProtokollEintrag) -> String {
        let was = [e.titel, e.kuenstler].compactMap { $0 }.joined(separator: " – ")
        let typen = ["start": "Gestartet", "ende": "Ganz gehört", "uebersprungen": "Übersprungen", "gespult": "Gespult",
                     "pause": "Pause", "gefaellt": "Gefällt mir", "gefaellt_nicht": "Gefällt mir nicht mehr",
                     "playlist": "Zur Playlist", "als_naechstes": "Als Nächstes", "warteschlange": "Zur Warteschlange",
                     "radio": "Radio gestartet", "suche": "Gesucht", "tempo": "Tempo", "schlaftimer": "Schlaf-Timer",
                     "hoerbuch_abgebrochen": "Aus Weiterhören entfernt", "hoerbuch_fertig": "Hörbuch fertig"]
        let typ = typen[e.typ] ?? e.typ
        if let wert = e.wert, was.isEmpty { return "\(typ): \(wert)" }
        return [typ, was.isEmpty ? nil : was, e.wert.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
    }
}
