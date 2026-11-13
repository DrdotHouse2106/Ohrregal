import Foundation

/// Album (Subsonic `AlbumID3`).
public struct Album: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let artist: String?
    public let artistId: String?
    public let coverArt: String?
    public let year: Int?
    public let songCount: Int?
    public let song: [Titel]?
}

/// Titel (Subsonic `Child`).
public struct Titel: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let artist: String?
    public let artistId: String?
    public let album: String?
    public let albumId: String?
    public let coverArt: String?
    public let duration: Int?
    public let track: Int?
    /// Datum von „Gefällt mir“, nil wenn nicht markiert.
    public let starred: String?
    /// Dateiendung, z. B. „mp3“ oder „flac“ (für Downloads).
    public let suffix: String?
}

/// Künstler (Subsonic `ArtistID3`).
public struct Kuenstler: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let coverArt: String?
    public let albumCount: Int?
    public let album: [Album]?

    public init(id: String, name: String) {
        self.id = id
        self.name = name
        coverArt = nil
        albumCount = nil
        album = nil
    }
}

public struct Playlist: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let songCount: Int?
    public let coverArt: String?
    public let entry: [Titel]?
}

/// Ergebnis von Suche und „Gefällt mir“.
public struct Suchergebnis: Decodable, Sendable {
    public let artist: [Kuenstler]?
    public let album: [Album]?
    public let song: [Titel]?

    public var istLeer: Bool { (artist ?? []).isEmpty && (album ?? []).isEmpty && (song ?? []).isEmpty }
}

public struct ServerFehler: LocalizedError, Sendable {
    public let errorDescription: String?
    public init(_ text: String) { errorDescription = text }
}

/// Inhalt von `subsonic-response`; je nach Aufruf ist ein anderes Feld gefüllt.
struct Antwort: Decodable {
    struct Fehler: Decodable { let code: Int?; let message: String? }
    struct Alben: Decodable { let album: [Album]? }
    struct Titelliste: Decodable { let song: [Titel]? }
    struct Index: Decodable { let artist: [Kuenstler]? }
    struct KuenstlerIndex: Decodable { let index: [Index]? }
    struct Playlists: Decodable { let playlist: [Playlist]? }

    let status: String
    let error: Fehler?
    let albumList2: Alben?
    let randomSongs: Titelliste?
    let similarSongs2: Titelliste?
    let album: Album?
    let artist: Kuenstler?
    let artists: KuenstlerIndex?
    let searchResult3: Suchergebnis?
    let starred2: Suchergebnis?
    let playlists: Playlists?
    let playlist: Playlist?
    let lyricsList: Liedtexte?
    let internetRadioStations: Sendertabelle?
    let musicFolders: Ordnerliste?

    struct Ordnerliste: Decodable { let musicFolder: [Musikordner]? }

    struct Sendertabelle: Decodable { let internetRadioStation: [Sender]? }

    struct Liedtexte: Decodable {
        struct Strukturiert: Decodable {
            struct Zeile: Decodable { let start: Int?; let value: String }
            let synced: Bool?
            let line: [Zeile]?
        }
        let structuredLyrics: [Strukturiert]?
    }

    struct Huelle: Decodable {
        let antwort: Antwort
        enum CodingKeys: String, CodingKey { case antwort = "subsonic-response" }
    }
}

/// Eine Zeile Songtext; `start` in Sekunden, nil bei nicht synchronisierten Texten.
public struct Textzeile: Hashable, Sendable {
    public let start: Double?
    public let text: String
}

/// Internetradio-Sender aus Navidrome.
public struct Sender: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let streamUrl: String
    public let homePageUrl: String?
    /// Senderlogo (nur aus dem Senderverzeichnis).
    public let bild: String?

    public init(id: String, name: String, streamUrl: String, homePageUrl: String? = nil, bild: String? = nil) {
        self.id = id; self.name = name; self.streamUrl = streamUrl; self.homePageUrl = homePageUrl; self.bild = bild
    }
}

/// Bibliothek („Musikordner“) in Navidrome, z. B. Musik und YouTube.
public struct Musikordner: Decodable, Hashable, Sendable {
    public let id: String
    public let name: String

    enum CodingKeys: String, CodingKey { case id, name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? c.decode(String.self, forKey: .id) { id = text } else { id = String(try c.decode(Int.self, forKey: .id)) }
        name = (try? c.decode(String.self, forKey: .name)) ?? id
    }
}
