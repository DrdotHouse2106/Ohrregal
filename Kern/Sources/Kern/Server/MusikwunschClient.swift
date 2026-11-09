import Foundation

/// Album aus Lidarr bzw. MusicBrainz (Dienst „Hörbuchwunsch“, `/musik`).
public struct LidarrAlbum: Decodable, Hashable, Identifiable, Sendable {
    public let mbid: String
    public let titel: String
    public let kuenstler: String?
    public let kuenstlerMbid: String?
    public let jahr: String?
    public let typ: String?
    public let titelAnzahl: Int?
    public let cover: String?
    public var status: String
    public let erscheint: String?

    public var id: String { mbid }

    enum CodingKeys: String, CodingKey { case mbid, titel, kuenstler, kuenstlerMbid, jahr, typ, titelAnzahl, cover, status, erscheint }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mbid = try c.decode(String.self, forKey: .mbid)
        titel = (try? c.decode(String.self, forKey: .titel)) ?? ""
        kuenstler = try? c.decode(String.self, forKey: .kuenstler)
        kuenstlerMbid = try? c.decode(String.self, forKey: .kuenstlerMbid)
        jahr = (try? c.decode(String.self, forKey: .jahr)) ?? (try? c.decode(Int.self, forKey: .jahr)).map(String.init)
        typ = try? c.decode(String.self, forKey: .typ)
        titelAnzahl = try? c.decode(Int.self, forKey: .titelAnzahl)
        cover = try? c.decode(String.self, forKey: .cover)
        status = (try? c.decode(String.self, forKey: .status)) ?? "fehlt"
        erscheint = try? c.decode(String.self, forKey: .erscheint)
    }

    public var statusText: String {
        switch status {
        case "da": "Vorhanden"
        case "gewuenscht": "Gewünscht"
        case "laedt": "Wird geladen"
        default: "Fehlt"
        }
    }
}

public struct LidarrKuenstler: Decodable, Hashable, Sendable {
    public let name: String
    public let mbid: String?
    public var folgt: Bool?
    public let inLidarr: Bool?
}

public struct MusikWunsch: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let mbid: String?
    public let titel: String
    public let kuenstler: String?
    public let cover: String?
    public let status: String
    public let hinweis: String?

    public var statusText: String {
        switch status {
        case "gewuenscht": "gewünscht"
        case "nicht_gefunden": "noch nicht gefunden"
        case "laedt": "wird geladen"
        case "einsortieren": "wird einsortiert"
        case "da": "ist da"
        case "fehler": "Fehler"
        default: status
        }
    }
}

/// Musik wünschen über den Dienst; angemeldet wird mit dem Navidrome-Konto (Subsonic-Token).
public struct MusikwunschClient: Sendable {
    let navidrome: NavidromeClient
    public let basis: URL

    public init(navidrome: NavidromeClient, basis: URL) {
        self.navidrome = navidrome
        self.basis = basis
    }

    func sende(_ pfad: String, methode: String = "GET", json: [String: Any]? = nil, warten: TimeInterval = 30) async throws -> (Data, Int) {
        var anfrage = URLRequest(url: URL(string: basis.absoluteString + pfad)!)
        anfrage.httpMethod = methode
        anfrage.timeoutInterval = warten
        anfrage.setValue(navidrome.benutzer, forHTTPHeaderField: "X-Subsonic-U")
        anfrage.setValue(NavidromeClient.token(passwort: navidrome.passwort, salt: navidrome.salt), forHTTPHeaderField: "X-Subsonic-T")
        anfrage.setValue(navidrome.salt, forHTTPHeaderField: "X-Subsonic-S")
        if let json {
            anfrage.httpBody = try JSONSerialization.data(withJSONObject: json)
            anfrage.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (daten, antwort) = try await URLSession.shared.data(for: anfrage)
        return (daten, (antwort as? HTTPURLResponse)?.statusCode ?? 0)
    }

    func hole<T: Decodable>(_ pfad: String) async throws -> T {
        let (daten, code) = try await sende(pfad)
        guard (200..<300).contains(code) else { throw Self.fehler(daten, code) }
        return try JSONDecoder().decode(T.self, from: daten)
    }

    static func fehler(_ daten: Data, _ code: Int) -> ServerFehler {
        struct Text: Decodable { let text: String? }
        if let text = try? JSONDecoder().decode(Text.self, from: daten).text { return ServerFehler(text) }
        return ServerFehler(code == 404 ? "Bei Lidarr nicht gefunden." : "Der Wunsch-Dienst meldet Fehler \(code).")
    }

    static func kodiert(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?"))) ?? text
    }

    public func suche(_ text: String) async throws -> [LidarrAlbum] {
        struct Liste: Decodable { let alben: [LidarrAlbum] }
        let liste: Liste = try await hole("/musik/suche?q=\(Self.kodiert(text))")
        return liste.alben
    }

    /// Alben eines Künstlers mit Stand; nil, wenn Lidarr/MusicBrainz ihn nicht kennt.
    public func kuenstler(_ name: String, mbid: String? = nil) async throws -> (kuenstler: LidarrKuenstler, alben: [LidarrAlbum])? {
        struct Seite: Decodable { let kuenstler: LidarrKuenstler; let alben: [LidarrAlbum] }
        var pfad = "/musik/kuenstler?name=\(Self.kodiert(name))"
        if let mbid { pfad += "&mbid=\(mbid)" }
        let (daten, code) = try await sende(pfad)
        if code == 404 { return nil }
        guard (200..<300).contains(code) else { throw Self.fehler(daten, code) }
        let seite = try JSONDecoder().decode(Seite.self, from: daten)
        return (seite.kuenstler, seite.alben)
    }

    public enum Ergebnis: Sendable { case gewuenscht, schonVorhanden }

    /// Kann bei einem neuen Künstler bis zu einer Minute dauern.
    public func wuensche(_ album: LidarrAlbum) async throws -> Ergebnis {
        var json: [String: Any] = ["mbid": album.mbid, "titel": album.titel]
        json["kuenstlerMbid"] = album.kuenstlerMbid
        json["kuenstler"] = album.kuenstler
        let (daten, code) = try await sende("/musik/wunsch", methode: "POST", json: json, warten: 90)
        switch code {
        case 200, 201: return .gewuenscht
        case 409: return .schonVorhanden
        default: throw Self.fehler(daten, code)
        }
    }

    public func wuensche() async throws -> [MusikWunsch] {
        struct Liste: Decodable { let wuensche: [MusikWunsch] }
        let liste: Liste = try await hole("/musik/wunsch")
        return liste.wuensche
    }

    public func zurueckziehen(_ id: String) async throws {
        let (daten, code) = try await sende("/musik/wunsch/\(id)", methode: "DELETE")
        guard (200..<300).contains(code) else { throw Self.fehler(daten, code) }
    }

    public func folgen(_ mbid: String, name: String, an: Bool) async throws {
        let daten: Data, code: Int
        if an {
            (daten, code) = try await sende("/musik/folgen", methode: "POST", json: ["kuenstlerMbid": mbid, "name": name], warten: 90)
        } else {
            (daten, code) = try await sende("/musik/folgen/\(mbid)", methode: "DELETE")
        }
        guard (200..<300).contains(code) else { throw Self.fehler(daten, code) }
    }

    public func neuerscheinungen() async throws -> [LidarrAlbum] {
        struct Liste: Decodable { let alben: [LidarrAlbum] }
        let liste: Liste = try await hole("/musik/neuerscheinungen")
        return liste.alben
    }

    public func geraetAbmelden(_ token: String) async throws {
        let (daten, code) = try await sende("/geraet/\(token)", methode: "DELETE")
        guard (200..<300).contains(code) else { throw Self.fehler(daten, code) }
    }

    /// Hörprotokoll schicken; true, wenn der Server es angenommen hat.
    public func sendeEreignisse(_ ereignisse: [Ereignis]) async -> Bool {
        let kodierer = JSONEncoder()
        kodierer.dateEncodingStrategy = .iso8601
        guard let daten = try? kodierer.encode(ereignisse),
              let liste = try? JSONSerialization.jsonObject(with: daten) as? [Any],
              let (_, code) = try? await sende("/ereignisse", methode: "POST", json: ["ereignisse": liste]) else { return false }
        return (200..<300).contains(code)
    }

    /// Gerät für „Album ist da“ anmelden (gehört dann dem Navidrome-Benutzer).
    public func meldeGeraet(_ token: String, umgebung: String) async throws {
        let (daten, code) = try await sende("/geraet", methode: "POST", json: ["apnsToken": token, "umgebung": umgebung])
        guard (200..<300).contains(code) else { throw Self.fehler(daten, code) }
    }
}
