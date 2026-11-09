import CryptoKit
import Foundation

/// Zugriff auf Navidrome über die (Open)Subsonic-API.
public struct NavidromeClient: Sendable {
    public let server: URL
    public let benutzer: String
    let passwort: String
    /// Fester Salt pro Sitzung, damit Cover-Adressen gleich bleiben und zwischengespeichert werden.
    let salt: String

    public init(server: URL, benutzer: String, passwort: String) {
        self.server = server
        self.benutzer = benutzer
        self.passwort = passwort
        salt = String(UUID().uuidString.prefix(12))
    }

    /// Token für die Anmeldung: md5(passwort + salt).
    static func token(passwort: String, salt: String) -> String {
        Insecure.MD5.hash(data: Data((passwort + salt).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Adresse für einen API-Aufruf, z. B. `adresse("getAlbumList2", ["type": "frequent"])`.
    public func adresse(_ methode: String, _ parameter: [String: String] = [:], mehrfach: [(String, String)] = [], salt: String? = nil) -> URL {
        let salt = salt ?? self.salt
        var teile = URLComponents(url: server.appending(path: "rest/\(methode)"), resolvingAgainstBaseURL: false)!
        let basis = ["u": benutzer, "t": Self.token(passwort: passwort, salt: salt), "s": salt,
                     "v": "1.16.1", "c": "Ohrregal", "f": "json"]
        teile.queryItems = basis.merging(parameter) { _, neu in neu }
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) } + mehrfach.map { URLQueryItem(name: $0.0, value: $0.1) }
        return teile.url!
    }

    func hole(_ methode: String, _ parameter: [String: String] = [:], mehrfach: [(String, String)] = []) async throws -> Antwort {
        let (daten, _) = try await URLSession.shared.data(from: adresse(methode, parameter, mehrfach: mehrfach))
        return try Self.lies(daten)
    }

    static func lies(_ daten: Data) throws -> Antwort {
        let antwort = try JSONDecoder().decode(Antwort.Huelle.self, from: daten).antwort
        guard antwort.status == "ok" else {
            switch antwort.error?.code {
            case 40: throw ServerFehler("Benutzername oder Passwort falsch.")
            case 41: throw ServerFehler("Dieser Server erlaubt keine Anmeldung per Token.")
            default: throw ServerFehler(antwort.error?.message ?? "Unbekannter Serverfehler")
            }
        }
        return antwort
    }

    // MARK: Aufrufe

    /// Prüft Adresse und Zugangsdaten.
    public func ping() async throws { _ = try await hole("ping") }

    /// Albenliste: `recent`, `frequent`, `newest`, `random`, `alphabeticalByName`, `starred` …
    /// Albenliste; mit `ordner` nur aus einer Bibliothek (Navidrome-Musikordner).
    public func alben(_ typ: String, anzahl: Int = 20, ab offset: Int = 0, ordner: String? = nil) async throws -> [Album] {
        var parameter = ["type": typ, "size": "\(anzahl)", "offset": "\(offset)"]
        parameter["musicFolderId"] = ordner
        return try await hole("getAlbumList2", parameter).albumList2?.album ?? []
    }

    public func ordner() async throws -> [Musikordner] {
        try await hole("getMusicFolders").musicFolders?.musicFolder ?? []
    }

    public func album(_ id: String) async throws -> Album? { try await hole("getAlbum", ["id": id]).album }

    public func kuenstlerListe() async throws -> [Kuenstler] {
        try await hole("getArtists").artists?.index?.flatMap { $0.artist ?? [] } ?? []
    }

    public func kuenstler(_ id: String) async throws -> Kuenstler? { try await hole("getArtist", ["id": id]).artist }

    public func zufaelligeTitel(anzahl: Int = 50) async throws -> [Titel] {
        try await hole("getRandomSongs", ["size": "\(anzahl)"]).randomSongs?.song ?? []
    }

    public func aehnlicheTitel(_ id: String, anzahl: Int = 50) async throws -> [Titel] {
        try await hole("getSimilarSongs2", ["id": id, "count": "\(anzahl)"]).similarSongs2?.song ?? []
    }

    public func suche(_ text: String) async throws -> Suchergebnis? {
        try await hole("search3", ["query": text, "artistCount": "10", "albumCount": "20", "songCount": "30"]).searchResult3
    }

    public func favoriten() async throws -> Suchergebnis? { try await hole("getStarred2").starred2 }

    public func playlists() async throws -> [Playlist] { try await hole("getPlaylists").playlists?.playlist ?? [] }

    public func playlist(_ id: String) async throws -> Playlist? { try await hole("getPlaylist", ["id": id]).playlist }

    /// Meldet „läuft gerade“ (`fertig: false`) oder „gehört“ (`fertig: true`) an Navidrome und damit an Last.fm.
    public func scrobble(_ id: String, fertig: Bool) async throws {
        _ = try await hole("scrobble", ["id": id, "submission": fertig ? "true" : "false"])
    }

    // MARK: Gefällt mir und Playlists

    public func gefaelltMir(_ id: String, _ an: Bool) async throws {
        _ = try await hole(an ? "star" : "unstar", ["id": id])
    }

    @discardableResult
    public func neuePlaylist(_ name: String, titel: [String] = []) async throws -> Playlist? {
        try await hole("createPlaylist", ["name": name], mehrfach: titel.map { ("songId", $0) }).playlist
    }

    public func zurPlaylist(_ playlist: String, titel: [String]) async throws {
        _ = try await hole("updatePlaylist", ["playlistId": playlist], mehrfach: titel.map { ("songIdToAdd", $0) })
    }

    /// Entfernt Einträge über ihre Stelle in der Playlist.
    public func ausPlaylist(_ playlist: String, stellen: [Int]) async throws {
        _ = try await hole("updatePlaylist", ["playlistId": playlist], mehrfach: stellen.map { ("songIndexToRemove", String($0)) })
    }

    public func loeschePlaylist(_ id: String) async throws {
        _ = try await hole("deletePlaylist", ["id": id])
    }

    /// Songtext (OpenSubsonic); synchronisierte Fassung bevorzugt.
    public func songtext(_ id: String) async throws -> [Textzeile] {
        let alle = try await hole("getLyricsBySongId", ["id": id]).lyricsList?.structuredLyrics ?? []
        guard let text = alle.first(where: { $0.synced == true }) ?? alle.first else { return [] }
        return (text.line ?? []).map { Textzeile(start: text.synced == true ? $0.start.map { Double($0) / 1000 } : nil, text: $0.value) }
    }

    public func sender() async throws -> [Sender] {
        try await hole("getInternetRadioStations").internetRadioStations?.internetRadioStation ?? []
    }

    public func coverURL(_ id: String?, groesse: Int) -> URL? {
        id.map { adresse("getCoverArt", ["id": $0, "size": "\(groesse)"]) }
    }

    public func streamURL(_ id: String) -> URL { adresse("stream", ["id": id]) }
}
