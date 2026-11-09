import Kern
import SwiftUI

/// Merkt sich, welche Hörbücher fertig gehört sind; Markieren geht an Audiobookshelf und ins Hörprotokoll.
@MainActor @Observable
final class Gehoert {
    static let geteilt = Gehoert()
    private(set) var ids: Set<String> = []
    /// Nach einer Markierung „Entdecken“ neu rechnen lassen.
    var geaendert = false

    func laden(_ abs: AudiobookshelfClient) async {
        if let neu = try? await abs.fertigGehoert() { ids = neu }
    }

    func umschalten(_ h: Hoerbuch, _ abs: AudiobookshelfClient) {
        let gehoert = !ids.contains(h.id)
        geaendert = true
        if gehoert { ids.insert(h.id) } else { ids.remove(h.id) }
        Protokoll.geteilt.merke(gehoert ? "hoerbuch_fertig" : "hoerbuch_ungehoert", art: "hoerbuch", quelle: "manuell",
                                id: h.id, name: h.titel, urheber: h.autor)
        Task {
            do { try await abs.markiere(h.id, gehoert: gehoert) } catch {
                if gehoert { ids.remove(h.id) } else { ids.insert(h.id) }
            }
        }
    }
}

/// Menüeintrag für Hörbuch-Karten (langes Drücken).
struct GehoertKnopf: View {
    @Environment(Sitzung.self) private var sitzung
    let hoerbuch: Hoerbuch

    var body: some View {
        if let abs = sitzung.hoerbuchClient {
            let gehoert = Gehoert.geteilt.ids.contains(hoerbuch.id)
            Button(gehoert ? "Als ungehört markieren" : "Als gehört markieren",
                   systemImage: gehoert ? "circle" : "checkmark.circle") {
                Gehoert.geteilt.umschalten(hoerbuch, abs)
            }
        }
    }
}
