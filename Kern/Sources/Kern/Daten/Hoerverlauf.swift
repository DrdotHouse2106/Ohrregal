import Foundation

/// Was gehört und was übersprungen wurde. Bleibt nur auf dem Gerät (Application Support).
public struct Hoerereignis: Codable, Sendable {
    public let titelId: String
    public let kuenstlerId: String?
    public let kuenstler: String?
    public let albumId: String?
    public let zeit: Date
    public let uebersprungen: Bool
}

@MainActor
public final class Hoerverlauf {
    public static let geteilt = Hoerverlauf()

    public private(set) var ereignisse: [Hoerereignis] = []
    private let datei: URL

    init(datei: URL? = nil) {
        let ordner = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        self.datei = datei ?? ordner.appending(path: "hoerverlauf.json")
        if let daten = try? Data(contentsOf: self.datei) {
            ereignisse = (try? JSONDecoder().decode([Hoerereignis].self, from: daten)) ?? []
        }
    }

    public func merke(_ titel: Titel, uebersprungen: Bool, am zeit: Date = Date()) {
        ereignisse.append(Hoerereignis(titelId: titel.id, kuenstlerId: titel.artistId, kuenstler: titel.artist,
                                       albumId: titel.albumId, zeit: zeit, uebersprungen: uebersprungen))
        // Höchstens ein Jahr und 10.000 Einträge.
        let grenze = zeit.addingTimeInterval(-365 * 86400)
        ereignisse = Array(ereignisse.filter { $0.zeit > grenze }.suffix(10_000))
        try? JSONEncoder().encode(ereignisse).write(to: datei, options: .atomic)
    }

    /// Meistgehörte Künstler der letzten Tage (nur ganz gehörte Titel).
    public func topKuenstler(tage: Int = 30, anzahl: Int = 5, jetzt: Date = Date()) -> [Kuenstler] {
        let grenze = jetzt.addingTimeInterval(-Double(tage) * 86400)
        var zaehler: [String: (name: String, anzahl: Int)] = [:]
        for e in ereignisse where !e.uebersprungen && e.zeit > grenze {
            guard let id = e.kuenstlerId else { continue }
            zaehler[id] = (e.kuenstler ?? "", (zaehler[id]?.anzahl ?? 0) + 1)
        }
        return zaehler.sorted { $0.value.anzahl > $1.value.anzahl }.prefix(anzahl).map { Kuenstler(id: $0.key, name: $0.value.name) }
    }

    /// Titel, die mindestens zweimal übersprungen und seitdem nie ganz gehört wurden.
    public func unbeliebt() -> Set<String> {
        var stand: [String: Int] = [:]
        for e in ereignisse { stand[e.titelId] = e.uebersprungen ? (stand[e.titelId] ?? 0) + 1 : 0 }
        return Set(stand.filter { $0.value >= 2 }.keys)
    }

    public func loeschen() {
        ereignisse = []
        try? FileManager.default.removeItem(at: datei)
    }
}
