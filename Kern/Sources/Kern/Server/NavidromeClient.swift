import CryptoKit
import Foundation

/// Zugriff auf Navidrome über die (Open)Subsonic-API.
public struct NavidromeClient: Sendable {
    public let server: URL
    public let benutzer: String
    let passwort: String

    public init(server: URL, benutzer: String, passwort: String) {
        self.server = server
        self.benutzer = benutzer
        self.passwort = passwort
    }

    /// Token für die Anmeldung: md5(passwort + salt).
    static func token(passwort: String, salt: String) -> String {
        Insecure.MD5.hash(data: Data((passwort + salt).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Adresse für einen API-Aufruf, z. B. `adresse("getAlbumList2", ["type": "frequent"])`.
    public func adresse(_ methode: String, _ parameter: [String: String] = [:], salt: String = UUID().uuidString) -> URL {
        var teile = URLComponents(url: server.appending(path: "rest/\(methode)"), resolvingAgainstBaseURL: false)!
        let basis = ["u": benutzer, "t": Self.token(passwort: passwort, salt: salt), "s": salt,
                     "v": "1.16.1", "c": "Ohrregal", "f": "json"]
        teile.queryItems = basis.merging(parameter) { _, neu in neu }
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        return teile.url!
    }

    /// Prüft Adresse und Zugangsdaten.
    public func ping() async throws -> Bool {
        let (daten, _) = try await URLSession.shared.data(from: adresse("ping"))
        let antwort = try JSONDecoder().decode(Huelle.self, from: daten)
        return antwort.antwort.status == "ok"
    }

    struct Huelle: Decodable {
        let antwort: Status
        enum CodingKeys: String, CodingKey { case antwort = "subsonic-response" }
        struct Status: Decodable { let status: String }
    }
}
