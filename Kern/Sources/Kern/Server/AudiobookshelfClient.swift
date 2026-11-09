import Foundation

/// Zugriff auf Audiobookshelf und auf den Dienst „Hörbuchwunsch“ (gleiche Adresse + `/wunsch-api`, gleiches Token).
@MainActor
public final class AudiobookshelfClient {
    public let server: URL
    let benutzer: String
    let passwort: String
    private var token: String?

    public init(server: URL, benutzer: String, passwort: String) {
        self.server = server
        self.benutzer = benutzer
        self.passwort = passwort
    }

    // MARK: Anmeldung und Anfragen

    /// Meldet sich an und merkt sich das Token. Prüft dabei auch die Zugangsdaten.
    @discardableResult
    public func anmelden() async throws -> String {
        var anfrage = URLRequest(url: adresse("/login"))
        anfrage.httpMethod = "POST"
        anfrage.setValue("application/json", forHTTPHeaderField: "Content-Type")
        anfrage.httpBody = try JSONSerialization.data(withJSONObject: ["username": benutzer, "password": passwort])
        let (daten, antwort) = try await URLSession.shared.data(for: anfrage)
        guard (antwort as? HTTPURLResponse)?.statusCode == 200 else {
            throw ServerFehler("Audiobookshelf: Benutzername oder Passwort falsch.")
        }
        struct Login: Decodable {
            struct Benutzer: Decodable { let token: String?; let accessToken: String? }
            let user: Benutzer
        }
        let benutzer = try JSONDecoder().decode(Login.self, from: daten).user
        // Das ältere Token läuft nicht ab und eignet sich daher auch für lange Streams.
        guard let neu = benutzer.token ?? benutzer.accessToken else { throw ServerFehler("Audiobookshelf hat kein Token geliefert.") }
        token = neu
        return neu
    }

    func aktuellesToken() async throws -> String {
        if let token { return token }
        return try await anmelden()
    }

    func adresse(_ pfad: String) -> URL { URL(string: server.absoluteString + pfad)! }

    /// Anfrage mit Token. Bei 401 wird genau einmal neu angemeldet, nie in einer Schleife.
    func sende(_ pfad: String, methode: String = "GET", json: [String: Any]? = nil) async throws -> (Data, Int) {
        for versuch in 0..<2 {
            let aktuell = try await aktuellesToken()
            var anfrage = URLRequest(url: adresse(pfad))
            anfrage.httpMethod = methode
            anfrage.setValue("Bearer \(aktuell)", forHTTPHeaderField: "Authorization")
            if let json {
                anfrage.httpBody = try JSONSerialization.data(withJSONObject: json)
                anfrage.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let (daten, antwort) = try await URLSession.shared.data(for: anfrage)
            let code = (antwort as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401, versuch == 0 { token = nil; continue }
            return (daten, code)
        }
        throw ServerFehler("Anmeldung bei Audiobookshelf abgelehnt.")
    }

    func hole<T: Decodable>(_ pfad: String, methode: String = "GET", json: [String: Any]? = nil) async throws -> T {
        let (daten, code) = try await sende(pfad, methode: methode, json: json)
        guard (200..<300).contains(code) else { throw Self.fehler(daten, code) }
        return try JSONDecoder().decode(T.self, from: daten)
    }

    static func fehler(_ daten: Data, _ code: Int) -> ServerFehler {
        struct Text: Decodable { let text: String? }
        if let text = try? JSONDecoder().decode(Text.self, from: daten).text { return ServerFehler(text) }
        return ServerFehler("Der Server meldet Fehler \(code).")
    }

    static func kodiert(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?"))) ?? text
    }

    // MARK: Bibliothek

    public func bibliotheken() async throws -> [Bibliothek] {
        struct Liste: Decodable { let libraries: [Bibliothek] }
        let liste: Liste = try await hole("/api/libraries")
        return liste.libraries.filter { $0.mediaType == "book" }
    }

    /// Fortschritt-ID je Hörbuch, zum Entfernen aus „Weiterhören“.
    private var fortschritt: [String: String] = [:]

    /// Angefangene Hörbücher ohne die, die in Audiobookshelf ausgeblendet oder fertig sind.
    public func angefangen() async throws -> [Hoerbuch] {
        struct Liste: Decodable { let libraryItems: [Hoerbuch] }
        struct Ich: Decodable {
            struct Fortschritt: Decodable {
                let id: String
                let libraryItemId: String
                let hideFromContinueListening: Bool?
                let isFinished: Bool?
            }
            let mediaProgress: [Fortschritt]?
        }
        let liste: Liste = try await hole("/api/me/items-in-progress")
        let ich: Ich? = try? await hole("/api/me")
        var verborgen = Set<String>()
        for f in ich?.mediaProgress ?? [] {
            fortschritt[f.libraryItemId] = f.id
            if f.hideFromContinueListening == true || f.isFinished == true { verborgen.insert(f.libraryItemId) }
        }
        return liste.libraryItems.filter { !verborgen.contains($0.id) }
    }

    /// Wie „Nicht in Weiterhören anzeigen“ in Audiobookshelf.
    public func ausWeiterhoerenEntfernen(_ hoerbuch: String) async throws {
        guard let id = fortschritt[hoerbuch] else { throw ServerFehler("Kein Fortschritt zu diesem Hörbuch gefunden.") }
        let (daten, code) = try await sende("/api/me/progress/\(id)/remove-from-continue-listening")
        guard (200..<300).contains(code) else { throw Self.fehler(daten, code) }
    }

    /// Vorschläge von Audible passend zum Hörverlauf (Dienst „Hörbuchwunsch“). Leer, solange der Dienst sie nicht anbietet.
    public func kategorien() async throws -> [Kategorie] {
        struct Liste: Decodable { let kategorien: [Kategorie] }
        let liste: Liste = try await hole("/wunsch-api/kategorien")
        return liste.kategorien
    }

    /// Beliebte oder neue Hörbücher einer Kategorie.
    public func stoebern(_ kategorie: String, neueste: Bool, neu: Bool = false) async throws -> [BuchTreffer] {
        struct Liste: Decodable { let treffer: [BuchTreffer] }
        let pfad = "/wunsch-api/stoebern?kategorie=\(Self.kodiert(kategorie))&sortierung=\(neueste ? "neu" : "beliebt")" + (neu ? "&neu=1" : "")
        let liste: Liste = try await hole(pfad)
        return liste.treffer
    }

    public func entdecken(neu: Bool = false) async throws -> [BuchTreffer] {
        struct Liste: Decodable { let treffer: [BuchTreffer] }
        let liste: Liste = try await hole("/wunsch-api/entdecken" + (neu ? "?neu=1" : ""))
        return liste.treffer
    }

    /// Seitenweise; optional neueste zuerst und nach Genre gefiltert.
    public func hoerbuecher(in bibliothek: String, seite: Int, anzahl: Int = 60, neuesteZuerst: Bool = false, genre: String? = nil) async throws -> [Hoerbuch] {
        struct Liste: Decodable { let results: [Hoerbuch] }
        var pfad = "/api/libraries/\(bibliothek)/items?limit=\(anzahl)&page=\(seite)&minified=1"
        pfad += neuesteZuerst ? "&sort=addedAt&desc=1" : "&sort=media.metadata.title"
        if let genre {
            // Audiobookshelf erwartet den Filterwert Base64-kodiert.
            let wert = Data(genre.utf8).base64EncodedString().addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            pfad += "&filter=genres.\(wert)"
        }
        let liste: Liste = try await hole(pfad)
        return liste.results
    }

    public func genres(in bibliothek: String) async throws -> [String] {
        struct Filter: Decodable { let genres: [String]? }
        let filter: Filter = try await hole("/api/libraries/\(bibliothek)/filterdata")
        return (filter.genres ?? []).sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    public func suche(in bibliothek: String, nach text: String) async throws -> [Hoerbuch] {
        struct Ergebnis: Decodable {
            struct Treffer: Decodable { let libraryItem: Hoerbuch }
            let book: [Treffer]?
        }
        let ergebnis: Ergebnis = try await hole("/api/libraries/\(bibliothek)/search?q=\(Self.kodiert(text))")
        return ergebnis.book?.map(\.libraryItem) ?? []
    }

    public func coverURL(_ id: String) -> URL? {
        token.map { adresse("/api/items/\(id)/cover?token=\($0)") }
    }

    // MARK: Wiedergabe

    public func starte(_ id: String) async throws -> HoerbuchSitzung {
        try await hole("/api/items/\(id)/play", methode: "POST", json: [
            "deviceInfo": ["clientName": "Ohrregal", "deviceId": geraeteId],
            "forceDirectPlay": true,
            "mediaPlayer": "AVPlayer",
            "supportedMimeTypes": ["audio/mpeg", "audio/mp4", "audio/x-m4a", "audio/aac", "audio/flac", "audio/x-m4b"],
        ])
    }

    /// Meldet die Hörposition; mit `schliessen` endet die Sitzung.
    public func synchronisiere(_ sitzung: String, zeit: Double, gehoert: Double, dauer: Double, schliessen: Bool) async throws {
        _ = try await sende("/api/session/\(sitzung)/\(schliessen ? "close" : "sync")", methode: "POST",
                            json: ["currentTime": zeit, "timeListened": gehoert, "duration": dauer])
    }

    public func dateiURL(_ pfad: String) async throws -> URL {
        let aktuell = try await aktuellesToken()
        return adresse(pfad + (pfad.contains("?") ? "&" : "?") + "token=\(aktuell)")
    }

    private var geraeteId: String {
        if let id = UserDefaults.standard.string(forKey: "geraeteId") { return id }
        let neu = UUID().uuidString
        UserDefaults.standard.set(neu, forKey: "geraeteId")
        return neu
    }

    // MARK: Hörbücher suchen und wünschen

    /// Sucht über die Metadatendienste von Audiobookshelf (Audible Deutschland).
    public func sucheBuecher(_ text: String) async throws -> [BuchTreffer] {
        try await hole("/api/search/books?provider=audible.de&title=\(Self.kodiert(text))")
    }

    public func wuensche() async throws -> [Wunsch] {
        struct Liste: Decodable { let wuensche: [Wunsch] }
        let liste: Liste = try await hole("/wunsch-api/wunsch")
        return liste.wuensche
    }

    public enum WunschErgebnis: Sendable {
        case angenommen(Wunsch)
        case schonVorhanden(absItemId: String?)
    }

    public func wuensche(_ treffer: BuchTreffer) async throws -> WunschErgebnis {
        // Gesucht wird bei Audible Deutschland, daher Sprache Deutsch.
        var json: [String: Any] = ["titel": treffer.title ?? "", "autor": treffer.author ?? "", "sprache": "de"]
        json["asin"] = treffer.asin
        json["sprecher"] = treffer.narrator
        json["reihe"] = treffer.series?.first?.series
        json["teil"] = treffer.series?.first?.sequence
        json["laufzeitMin"] = treffer.duration.map { Int($0) }
        json["coverUrl"] = treffer.cover
        let (daten, code) = try await sende("/wunsch-api/wunsch", methode: "POST", json: json)
        switch code {
        case 200, 201: return .angenommen(try JSONDecoder().decode(Wunsch.self, from: daten))
        case 409:
            struct Vorhanden: Decodable { let absItemId: String? }
            return .schonVorhanden(absItemId: (try? JSONDecoder().decode(Vorhanden.self, from: daten))?.absItemId)
        default: throw Self.fehler(daten, code)
        }
    }

    /// Ein einzelnes Hörbuch, z. B. nach dem Antippen einer Push-Nachricht.
    public func hoerbuch(_ id: String) async throws -> Hoerbuch {
        try await hole("/api/items/\(id)?expanded=1")
    }

    /// Gerät für Push-Nachrichten anmelden (`umgebung`: „produktion“ oder „sandbox“).
    public func meldeGeraet(_ token: String, umgebung: String) async throws {
        let (daten, code) = try await sende("/wunsch-api/geraet", methode: "POST", json: ["apnsToken": token, "umgebung": umgebung])
        guard (200..<300).contains(code) else { throw Self.fehler(daten, code) }
    }

    public func geraetAbmelden(_ token: String) async throws {
        let (daten, code) = try await sende("/wunsch-api/geraet/\(token)", methode: "DELETE")
        guard (200..<300).contains(code) else { throw Self.fehler(daten, code) }
    }

    /// Reihe folgen: fehlende und künftige Teile werden automatisch gewünscht.
    public func folgeReihe(_ treffer: BuchTreffer) async throws {
        guard let reihe = treffer.series?.first?.series else { throw ServerFehler("Dieses Hörbuch gehört zu keiner Reihe.") }
        var json: [String: Any] = ["reihe": reihe, "autor": treffer.author ?? "", "sprache": "de"]
        json["asin"] = treffer.asin
        let (daten, code) = try await sende("/wunsch-api/reihe", methode: "POST", json: json)
        guard (200..<300).contains(code) else { throw Self.fehler(daten, code) }
    }

    public func reihen() async throws -> [GefolgteReihe] {
        struct Liste: Decodable { let reihen: [GefolgteReihe] }
        let liste: Liste = try await hole("/wunsch-api/reihe")
        return liste.reihen
    }

    public func reiheEntfolgen(_ id: String) async throws {
        let (daten, code) = try await sende("/wunsch-api/reihe/\(id)", methode: "DELETE")
        guard (200..<300).contains(code) else { throw Self.fehler(daten, code) }
    }

    public func zurueckziehen(_ id: String) async throws {
        let (daten, code) = try await sende("/wunsch-api/wunsch/\(id)", methode: "DELETE")
        guard (200..<300).contains(code) else { throw Self.fehler(daten, code) }
    }

    public func erneutSuchen(_ id: String) async throws {
        let (daten, code) = try await sende("/wunsch-api/wunsch/\(id)/erneut", methode: "POST")
        guard (200..<300).contains(code) else { throw Self.fehler(daten, code) }
    }
}
