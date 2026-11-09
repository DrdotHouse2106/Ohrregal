import Foundation
import Observation

/// „Gefällt mir“ für Titel; Änderungen gelten sofort in der App und gehen an Navidrome.
@MainActor @Observable
public final class Favoriten {
    public static let geteilt = Favoriten()
    private var stand: [String: Bool] = [:]

    public func ist(_ titel: Titel) -> Bool { stand[titel.id] ?? (titel.starred != nil) }

    public func umschalten(_ titel: Titel, _ client: NavidromeClient) {
        let neu = !ist(titel)
        stand[titel.id] = neu
        Protokoll.geteilt.merke(neu ? "gefaellt" : "gefaellt_nicht", titel: titel)
        Task {
            do { try await client.gefaelltMir(titel.id, neu) } catch { stand[titel.id] = !neu }
        }
    }
}
