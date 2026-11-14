import Foundation
import Observation

/// Öffentliches Senderverzeichnis radio-browser.info (frei, ohne Anmeldung).
public enum RadioVerzeichnis {
    /// Sucht tolerant: „krone hit“ findet auch „KroneHit“ (erst wie eingegeben, dann ohne Leerzeichen,
    /// dann nach dem längsten Wort, gefiltert auf Namen mit allen Wörtern).
    public static func suche(_ text: String) async throws -> [Sender] {
        let woerter = text.lowercased().split(separator: " ").map(String.init)
        var treffer = try await abfrage(text)
        if treffer.isEmpty, woerter.count > 1 { treffer = try await abfrage(woerter.joined()) }
        if treffer.isEmpty, woerter.count > 1, let laengstes = woerter.max(by: { $0.count < $1.count }) {
            treffer = try await abfrage(laengstes).filter { s in
                let name = s.name.lowercased().replacingOccurrences(of: " ", with: "")
                return woerter.allSatisfy { name.contains($0) }
            }
        }
        return treffer
    }

    static func abfrage(_ text: String) async throws -> [Sender] {
        struct Eintrag: Decodable {
            let stationuuid: String
            let name: String
            let url_resolved: String
            let favicon: String?
            let homepage: String?
            let codec: String?
        }
        var teile = URLComponents(string: "https://de1.api.radio-browser.info/json/stations/search")!
        teile.queryItems = [URLQueryItem(name: "name", value: text), URLQueryItem(name: "limit", value: "40"),
                            URLQueryItem(name: "hidebroken", value: "true"), URLQueryItem(name: "order", value: "clickcount"),
                            URLQueryItem(name: "reverse", value: "true")]
        var anfrage = URLRequest(url: teile.url!)
        anfrage.setValue("Ohrregal/1.0", forHTTPHeaderField: "User-Agent")
        let (daten, _) = try await URLSession.shared.data(for: anfrage)
        // Ohne erkennbares Tonformat ist es meist ein Fernsehstream. Logos über https (sonst blockt iOS sie).
        return try JSONDecoder().decode([Eintrag].self, from: daten)
            .filter { !$0.url_resolved.isEmpty && $0.codec != "UNKNOWN" }
            .map { Sender(id: "rb-" + $0.stationuuid, name: $0.name.trimmingCharacters(in: .whitespaces), streamUrl: $0.url_resolved,
                          homePageUrl: $0.homepage, bild: $0.favicon.flatMap { $0.isEmpty ? nil : $0.replacingOccurrences(of: "http://", with: "https://") }) }
    }
}

/// Gemerkte Sender aus dem Verzeichnis; bleiben auf dem iPhone.
@MainActor @Observable
public final class MeineSender {
    public static let geteilt = MeineSender()

    public private(set) var liste: [Sender]

    init() {
        liste = (UserDefaults.standard.data(forKey: "meineSender")).flatMap { try? JSONDecoder().decode([Sender].self, from: $0) } ?? []
    }

    public func enthaelt(_ s: Sender) -> Bool { liste.contains { $0.id == s.id } }

    public func umschalten(_ s: Sender) {
        if enthaelt(s) { liste.removeAll { $0.id == s.id } } else { liste.append(s) }
        UserDefaults.standard.set(try? JSONEncoder().encode(liste), forKey: "meineSender")
    }

    /// Einmalig: lokal gemerkte Sender nach Navidrome übertragen (nacheinander); übertragene verschwinden lokal.
    public func uebertragen(_ dienst: MusikwunschClient) async {
        for s in liste where (try? await dienst.senderAnlegen(s)) != nil { umschalten(s) }
    }

    /// Gleicher Stream? (ohne Schrägstrich am Ende verglichen)
    public static func gleich(_ a: String, _ b: String) -> Bool {
        func n(_ s: String) -> String { s.hasSuffix("/") ? String(s.dropLast()) : s }
        return n(a) == n(b)
    }
}
