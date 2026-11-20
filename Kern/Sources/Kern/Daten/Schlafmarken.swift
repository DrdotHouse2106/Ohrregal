import Foundation

/// Lesezeichen in Audiobookshelf (pro Person, auf allen Geräten und in der Weboberfläche sichtbar).
public struct Lesezeichen: Decodable, Hashable, Identifiable, Sendable {
    public let libraryItemId: String
    public let title: String
    public let time: Double
    public var id: String { "\(libraryItemId)|\(time)" }
    /// Von Ohrregal beim Schlaf-Timer gesetzt („☾ …“).
    public var istSchlafmarke: Bool { title.hasPrefix(Schlafmarken.zeichen) }
}

/// Eine Timer-Nacht: wo der Timer gestellt wurde und wo er abgeschaltet hat (für die Frage am nächsten Tag).
public struct SchlafNacht: Codable, Hashable, Identifiable, Sendable {
    public let hoerbuch: String
    public var gestellt: Double
    public var gestelltUm: Date
    public var abgeschaltet: Double?
    public var abgeschaltetUm: Date?
    public var id: String { hoerbuch }
}

/// Schlafmarken: Beim Stellen eines Minuten-Timers und beim Abschalten setzt Ohrregal je ein Lesezeichen;
/// am nächsten Tag fragt es, wo es weitergehen soll. Je Hörbuch bleiben die letzten 3 Abende.
public enum Schlafmarken {
    public static let zeichen = "☾ "
    static let abende = 3

    static func uhr(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
    static func tag(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated)) }

    public static func nacht(_ hoerbuch: String) -> SchlafNacht? {
        UserDefaults.standard.data(forKey: "schlafnacht.\(hoerbuch)").flatMap { try? JSONDecoder().decode(SchlafNacht.self, from: $0) }
    }

    static func merke(_ n: SchlafNacht?, fuer hoerbuch: String) {
        UserDefaults.standard.set(n.flatMap { try? JSONEncoder().encode($0) }, forKey: "schlafnacht.\(hoerbuch)")
    }

    /// Frage nur, wenn der Timer abgeschaltet hat und seitdem mindestens eine Stunde vergangen ist.
    public static func offeneFrage(_ hoerbuch: String) -> SchlafNacht? {
        guard let n = nacht(hoerbuch), let um = n.abgeschaltetUm, Date().timeIntervalSince(um) > 3600 else { return nil }
        return n
    }

    public static func beantwortet(_ hoerbuch: String) { merke(nil, fuer: hoerbuch) }

    /// Timer gestellt (oder verlängert: dann rückt die Marke nach, man war ja noch wach).
    @MainActor static func gestellt(_ hoerbuch: String, zeit: Double, _ abs: AudiobookshelfClient) {
        let alt = nacht(hoerbuch)
        let neu = SchlafNacht(hoerbuch: hoerbuch, gestellt: zeit, gestelltUm: .now)
        merke(neu, fuer: hoerbuch)
        Task {
            if let alt, alt.abgeschaltet == nil { try? await abs.lesezeichenLoeschen(hoerbuch, zeit: alt.gestellt) }
            try? await abs.lesezeichenSetzen(hoerbuch, zeit: zeit, titel: "\(zeichen)Timer gestellt · \(tag(.now)) \(uhr(.now))")
            await aufraeumen(hoerbuch, abs)
        }
    }

    @MainActor static func abgeschaltet(_ hoerbuch: String, zeit: Double, _ abs: AudiobookshelfClient) {
        guard var n = nacht(hoerbuch) else { return }
        n.abgeschaltet = zeit
        n.abgeschaltetUm = .now
        merke(n, fuer: hoerbuch)
        Task {
            try? await abs.lesezeichenSetzen(hoerbuch, zeit: zeit, titel: "\(zeichen)Abgeschaltet · \(tag(.now)) \(uhr(.now))")
            await aufraeumen(hoerbuch, abs)
        }
    }

    /// Nur die Schlafmarken der letzten 3 Abende behalten (je Abend höchstens 2); eigene Lesezeichen bleiben.
    static func aufraeumen(_ hoerbuch: String, _ abs: AudiobookshelfClient) async {
        guard let alle = try? await abs.lesezeichen(hoerbuch) else { return }
        let marken = alle.filter(\.istSchlafmarke)
        guard marken.count > abende * 2 else { return }
        // Ältere zuerst löschen: Reihenfolge, in der Audiobookshelf sie liefert (älteste zuerst).
        for m in marken.prefix(marken.count - abende * 2) { try? await abs.lesezeichenLoeschen(hoerbuch, zeit: m.time) }
    }
}
