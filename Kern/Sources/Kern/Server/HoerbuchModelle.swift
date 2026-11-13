import Foundation

public struct Bibliothek: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let mediaType: String?
}

/// Eintrag einer Audiobookshelf-Bibliothek (gekürzte Form).
public struct Hoerbuch: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    /// „book“ oder „podcast“.
    public let mediaType: String?
    public let media: Medium

    public struct Medium: Decodable, Hashable, Sendable {
        public let metadata: Metadaten
        public let duration: Double?
    }

    /// Liest die gekürzte Form (Listen: authorName …) und die volle Form (Einzelabruf: authors[], narrators[], series[]).
    public struct Metadaten: Decodable, Hashable, Sendable {
        public let title: String?
        public let authorName: String?
        public let narratorName: String?
        public let seriesName: String?
        public let description: String?

        enum CodingKeys: String, CodingKey { case title, authorName, narratorName, seriesName, description, authors, narrators, series, author }
        struct Name: Decodable { let name: String; let sequence: String? }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func leer(_ s: String?) -> String? { s?.isEmpty == false ? s : nil }
            title = try? c.decode(String.self, forKey: .title)
            authorName = leer((try? c.decode(String.self, forKey: .authorName))
                ?? (try? c.decode([Name].self, forKey: .authors))?.map(\.name).joined(separator: ", ")
                ?? (try? c.decode(String.self, forKey: .author)))
            narratorName = leer((try? c.decode(String.self, forKey: .narratorName))
                ?? (try? c.decode([String].self, forKey: .narrators))?.joined(separator: ", "))
            seriesName = leer((try? c.decode(String.self, forKey: .seriesName))
                ?? (try? c.decode([Name].self, forKey: .series))?.map { n in n.sequence.map { "\(n.name) – Teil \($0)" } ?? n.name }.joined(separator: ", "))
            description = leer((try? c.decode(String.self, forKey: .description))?.ohneHTML)
        }
    }

    public var titel: String { media.metadata.title ?? "Ohne Titel" }
    public var autor: String { media.metadata.authorName ?? "" }
}

public struct Kapitel: Codable, Hashable, Sendable {
    public let start: Double
    public let end: Double
    public let title: String
}

/// Antwort von `POST /api/items/{id}/play`.
public struct HoerbuchSitzung: Decodable, Sendable {
    public let id: String
    public let libraryItemId: String
    public let currentTime: Double?
    public let duration: Double
    public let displayTitle: String?
    public let displayAuthor: String?
    public let chapters: [Kapitel]?
    public let audioTracks: [Spur]

    public struct Spur: Decodable, Sendable {
        public let startOffset: Double
        public let duration: Double
        public let contentUrl: String
    }
}

/// Treffer aus `GET /api/search/books` (Audible über Audiobookshelf).
public struct BuchTreffer: Decodable, Hashable, Identifiable, Sendable {
    public let title: String?
    public let subtitle: String?
    public let author: String?
    public let narrator: String?
    public let cover: String?
    public let asin: String?
    public let language: String?
    public let duration: Double?
    public let series: [Reihe]?
    public let description: String?
    public let publisher: String?
    public let publishedYear: String?
    /// Nur bei „Entdecken“: warum der Titel vorgeschlagen wird.
    public let grund: String?

    /// Beschreibung ohne HTML (Audible liefert sie mit Absätzen und Formatierung).
    public var beschreibung: String? { description?.ohneHTML }

    public struct Reihe: Decodable, Hashable, Sendable {
        public let series: String?
        public let sequence: String?

        enum CodingKeys: String, CodingKey { case series, sequence }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            series = try? c.decode(String.self, forKey: .series)
            sequence = (try? c.decode(String.self, forKey: .sequence)) ?? (try? c.decode(Double.self, forKey: .sequence)).map { $0 == $0.rounded() ? String(Int($0)) : String($0) }
        }
    }

    public var id: String { asin ?? "\(title ?? "")|\(author ?? "")" }

    enum CodingKeys: String, CodingKey { case title, subtitle, author, narrator, cover, asin, language, duration, series, description, publisher, publishedYear, grund }

    public init(from decoder: Decoder) throws {
        // Die Anbieter liefern Felder mal als Zahl, mal als Text; nichts davon darf die Suche scheitern lassen.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try? c.decode(String.self, forKey: .title)
        subtitle = try? c.decode(String.self, forKey: .subtitle)
        author = try? c.decode(String.self, forKey: .author)
        narrator = try? c.decode(String.self, forKey: .narrator)
        cover = try? c.decode(String.self, forKey: .cover)
        asin = try? c.decode(String.self, forKey: .asin)
        language = try? c.decode(String.self, forKey: .language)
        duration = (try? c.decode(Double.self, forKey: .duration)) ?? (try? c.decode(String.self, forKey: .duration)).flatMap(Double.init)
        series = try? c.decode([Reihe].self, forKey: .series)
        description = try? c.decode(String.self, forKey: .description)
        publisher = try? c.decode(String.self, forKey: .publisher)
        publishedYear = (try? c.decode(String.self, forKey: .publishedYear)) ?? (try? c.decode(Int.self, forKey: .publishedYear)).map(String.init)
        grund = try? c.decode(String.self, forKey: .grund)
    }
}

/// Wunsch aus dem Dienst „Hörbuchwunsch“ (siehe Dienst/API.md).
public struct Wunsch: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let asin: String?
    public let titel: String
    public let autor: String?
    public let coverUrl: String?
    public let status: String
    public let hinweis: String?
    public let fortschritt: Int?
    public let absItemId: String?

    public var statusText: String {
        switch status {
        case "gewuenscht": "gewünscht"
        case "nicht_gefunden": "noch nicht gefunden"
        case "laedt": "wird geladen" + (fortschritt.map { " (\($0) %)" } ?? "")
        case "einsortieren": "wird einsortiert"
        case "da": "ist da"
        case "fehler": "Fehler"
        default: status
        }
    }
}

/// Reihe, der der Benutzer folgt (Dienst „Hörbuchwunsch“, `GET /reihe`).
public struct GefolgteReihe: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let reihe: String
    public let autor: String?
    public let teileGesamt: Int?
    public let teileDa: Int?
    public let teileGewuenscht: Int?
    public let hinweis: String?

    public var stand: String {
        var teile: [String] = []
        if let da = teileDa { teile.append(teileGesamt.map { "\(da) von \($0) da" } ?? "\(da) da") }
        if let g = teileGewuenscht, g > 0 { teile.append("\(g) gewünscht, lädt nachts") }
        return teile.joined(separator: " · ")
    }
}

/// Audible-Kategorie zum Stöbern (Dienst „Hörbuchwunsch“, `GET /kategorien`).
public struct Kategorie: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let unter: [Kategorie]?
}

extension String {
    /// Text ohne HTML-Auszeichnung; Absätze bleiben als Zeilenumbruch erhalten.
    public var ohneHTML: String {
        replacingOccurrences(of: "<br\\s*/?>|</p>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Folge eines Podcasts in Audiobookshelf (Bibliothek vom Typ „podcast“).
public struct Folge: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let libraryItemId: String?
    public let title: String?
    public let description: String?
    /// Millisekunden seit 1970; bei Dateien ohne RSS oft leer, dann zählt `addedAt`.
    public let publishedAt: Double?
    public let addedAt: Double?
    public let duration: Double?
    /// Nur bei „Neue Folgen“: Name des Podcasts.
    public let podcastTitel: String?
    /// Datei für den Download (`/api/items/{podcast}/file/{ino}`).
    public let ino: String?
    public let endung: String?

    enum CodingKeys: String, CodingKey { case id, libraryItemId, title, description, publishedAt, addedAt, duration, audioFile, podcast }
    struct Datei: Decodable { struct Meta: Decodable { let ext: String? }; let duration: Double?; let ino: String?; let metadata: Meta? }
    struct Podcast: Decodable { struct Meta: Decodable { let title: String? }; let metadata: Meta? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        libraryItemId = try? c.decode(String.self, forKey: .libraryItemId)
        title = try? c.decode(String.self, forKey: .title)
        description = (try? c.decode(String.self, forKey: .description))?.ohneHTML
        publishedAt = try? c.decode(Double.self, forKey: .publishedAt)
        addedAt = try? c.decode(Double.self, forKey: .addedAt)
        let datei = try? c.decode(Datei.self, forKey: .audioFile)
        duration = (try? c.decode(Double.self, forKey: .duration)) ?? datei?.duration
        ino = datei?.ino
        endung = datei?.metadata?.ext.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        podcastTitel = (try? c.decode(Podcast.self, forKey: .podcast))?.metadata?.title
    }

    public var titel: String { title ?? "Ohne Titel" }
    public var datum: Date? { (publishedAt ?? addedAt).map { Date(timeIntervalSince1970: $0 / 1000) } }
}

/// Treffer aus dem Apple-Podcast-Verzeichnis (über den eigenen Dienst).
public struct PodcastTreffer: Decodable, Hashable, Identifiable, Sendable {
    public let feedUrl: String
    public let titel: String
    public let autor: String?
    public let cover: String?
    public let genre: String?
    public let folgen: Int?
    /// Gesetzt, wenn der Podcast schon in Audiobookshelf liegt.
    public let absItemId: String?
    public var id: String { feedUrl }

    /// Gleicher Treffer, jetzt mit Audiobookshelf-ID (nach dem Abonnieren).
    public init(kopie t: PodcastTreffer, absItemId: String) {
        feedUrl = t.feedUrl; titel = t.titel; autor = t.autor; cover = t.cover; genre = t.genre; folgen = t.folgen; self.absItemId = absItemId
    }
}

/// Über den Dienst angelegte Abos; `eingerichtet` sagt, ob Abonnieren möglich ist.
public struct PodcastAbos: Decodable, Sendable {
    public struct Abo: Decodable, Hashable, Identifiable, Sendable {
        public let absItemId: String
        public let titel: String?
        public let vonMir: Bool?
        public var id: String { absItemId }
    }
    public let abos: [Abo]
    public let eingerichtet: Bool
}
