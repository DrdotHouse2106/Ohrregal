import Foundation
import Observation

/// Lieblings-Podcasts: stehen vorn, ihre neuen Folgen zuerst. Gespeichert im eigenen Dienst (alle Geräte),
/// ohne Dienst nur auf dem iPhone.
@MainActor @Observable
public final class PodcastFavoriten {
    public static let geteilt = PodcastFavoriten()

    public private(set) var ids: [String]

    init() { ids = UserDefaults.standard.stringArray(forKey: "podcastFavoriten") ?? [] }

    public func ist(_ id: String) -> Bool { ids.contains(id) }

    /// Vom Dienst holen (falls vorhanden); lokale Liste bleibt sonst.
    public func laden(_ abs: AudiobookshelfClient) async {
        guard let liste = try? await abs.podcastFavoriten() else { return }
        ids = liste
        UserDefaults.standard.set(ids, forKey: "podcastFavoriten")
    }

    public func umschalten(_ id: String, _ abs: AudiobookshelfClient?) {
        if ist(id) { ids.removeAll { $0 == id } } else { ids.append(id) }
        UserDefaults.standard.set(ids, forKey: "podcastFavoriten")
        let liste = ids
        if let abs { Task { try? await abs.podcastFavoritenSpeichern(liste) } }
    }

    /// Favoriten zuerst (in ihrer Reihenfolge), Rest wie gehabt.
    public func sortiert<T>(_ liste: [T], id: (T) -> String?) -> [T] {
        liste.enumerated().sorted { a, b in
            let ia = id(a.element).flatMap { ids.firstIndex(of: $0) } ?? Int.max
            let ib = id(b.element).flatMap { ids.firstIndex(of: $0) } ?? Int.max
            return ia != ib ? ia < ib : a.offset < b.offset
        }.map(\.element)
    }
}
