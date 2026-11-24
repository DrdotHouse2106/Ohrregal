import Foundation

/// Ohrwurm: Musiksammlung mit Apple-Katalog. Erreichbar über den Wunsch-Dienst unter `/ohrwurm/…`.
public enum Ohrwurm {
    public struct Treffer: Decodable, Hashable, Identifiable, Sendable { public let id: String; public let name: String }

    public struct Lied: Decodable, Hashable, Identifiable, Sendable {
        public let appleId: String?
        public let isrc: String?
        public let titel: String
        public let dauer: Double?
        public let vorhanden: Bool
        public let andereFassung: Bool?
        public var wunsch: String?
        public var id: String { appleId ?? isrc ?? titel }
    }

    public struct Veroeffentlichung: Decodable, Hashable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let jahr: String?
        public let liederGesamt: Int?
        public let cover: String?
        /// nil bei Zusammenstellungen, Live und Mitwirkung (nur Anzeige)
        public var lieder: [Lied]?
        public var vorhanden: Int { lieder?.filter(\.vorhanden).count ?? 0 }
    }

    public struct Abschnitt: Decodable, Hashable, Identifiable, Sendable {
        public let art: String
        public let titel: String
        public let veroeffentlichungen: [Veroeffentlichung]
        public var id: String { art }
    }

    public struct Zahlen: Decodable, Hashable, Sendable {
        public let lieder: Int
        public let vorhanden: Int
        public let andereFassung: Int?
    }

    public struct Kuenstler: Decodable, Hashable, Sendable {
        public let id: String
        public let name: String
        public let gefolgt: Bool
        public let automatisch: Bool
        public let zahlen: Zahlen
        public let abschnitte: [Abschnitt]
    }

    public struct Wunsch: Decodable, Hashable, Identifiable, Sendable {
        public let id: Int
        public let titel: String
        public let kuenstler: String
        public let album: String?
        public let cover: String?
        public let stand: String
        public let text: String?

        public var standText: String {
            switch stand {
            case "offen": "gewünscht"
            case "in_arbeit": "in Arbeit"
            case "fehlgeschlagen": "noch nicht gefunden"
            case "erledigt": "ist da"
            default: stand
            }
        }
    }

    /// Treffer der Von-Hand-Suche (z. B. eine Usenet-Veröffentlichung aus Prowlarr).
    public struct Kandidat: Decodable, Hashable, Identifiable, Sendable {
        public let anschluss: String
        public let kennung: String
        public let titel: String
        public let groesse: Int64?
        public let indexer: String?
        public let alterTage: Int?
        public let grabs: Int?
        public let gesperrt: Bool?
        public var id: String { anschluss + kennung }
    }

    public struct Gefolgt: Decodable, Hashable, Identifiable, Sendable {
        public let appleId: String
        public let name: String
        public let automatisch: Bool
        public var id: String { appleId }
    }

    public struct Neuheit: Decodable, Hashable, Identifiable, Sendable {
        public let albumId: String
        public let kuenstlerId: String
        public let kuenstler: String
        public let name: String
        public let art: String
        public let datum: String?
        public let cover: String?
        public var id: String { albumId }
    }
}

extension MusikwunschClient {
    private func ohrwurm<T: Decodable>(_ pfad: String, methode: String = "GET", json: [String: Any]? = nil) async throws -> T {
        let (daten, code) = try await sende("/ohrwurm/" + pfad, methode: methode, json: json, warten: 300)
        guard (200..<300).contains(code) else {
            if code == 503 { throw ServerFehler("Ohrwurm ist am Server noch nicht eingerichtet.") }
            throw Self.fehler(daten, code)
        }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: daten)
    }

    private struct Ok: Decodable {}

    public func ohrwurmSuche(_ name: String) async throws -> [Ohrwurm.Treffer] {
        try await ohrwurm("suche?name=\(Self.kodiert(name))")
    }

    public func ohrwurmKuenstler(_ id: String) async throws -> Ohrwurm.Kuenstler {
        try await ohrwurm("kuenstler/\(id)")
    }

    /// art: lied, album oder kuenstler. Gibt die Zahl neuer Wünsche zurück (schon Vorhandenes wird übersprungen).
    @discardableResult
    public func ohrwurmWuenschen(_ art: String, _ appleId: String) async throws -> Int {
        let neu: [Ohrwurm.Wunsch] = try await ohrwurm("wuensche", methode: "POST", json: ["art": art, "apple_id": appleId])
        return neu.count
    }

    public func ohrwurmWuensche() async throws -> [Ohrwurm.Wunsch] { try await ohrwurm("wuensche") }

    public func ohrwurmZurueckziehen(_ id: Int) async throws {
        let _: Ok = try await ohrwurm("wuensche/\(id)", methode: "DELETE")
    }

    /// Von-Hand-Suche: alle Treffer der Anschlüsse für einen Wunsch (kann bis zu einer Minute dauern).
    public func ohrwurmTreffer(_ id: Int) async throws -> [Ohrwurm.Kandidat] { try await ohrwurm("wuensche/\(id)/treffer") }

    public func ohrwurmNehmen(_ id: Int, _ k: Ohrwurm.Kandidat) async throws {
        let _: Ok = try await ohrwurm("wuensche/\(id)/treffer", methode: "POST", json: ["anschluss": k.anschluss, "kennung": k.kennung])
    }

    public func ohrwurmGefolgt() async throws -> [Ohrwurm.Gefolgt] { try await ohrwurm("folgen") }

    public func ohrwurmFolgen(_ appleId: String, an: Bool, automatisch: Bool = false) async throws {
        if an {
            let _: Ohrwurm.Gefolgt = try await ohrwurm("folgen", methode: "POST", json: ["apple_id": appleId, "automatisch": automatisch])
        } else {
            let _: Ok = try await ohrwurm("folgen/\(appleId)", methode: "DELETE")
        }
    }

    public func ohrwurmNeuheiten() async throws -> [Ohrwurm.Neuheit] { try await ohrwurm("neuheiten") }

    public func ohrwurmGesehen() async throws {
        let _: Ok = try await ohrwurm("neuheiten/gesehen", methode: "POST", json: [:])
    }
}
