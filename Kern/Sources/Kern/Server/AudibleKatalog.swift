import Foundation

/// Öffentlicher Audible-Katalog (ohne Anmeldung), z. B. für Hörproben.
public enum AudibleKatalog {
    /// Adresse der Hörprobe (MP3, ca. 5 Minuten) oder nil, wenn es keine gibt.
    public static func hoerprobe(_ asin: String) async -> URL? {
        struct Antwort: Decodable {
            struct Produkt: Decodable { let sample_url: String? }
            let product: Produkt
        }
        guard let url = URL(string: "https://api.audible.de/1.0/catalog/products/\(asin)?response_groups=sample"),
              let (daten, _) = try? await URLSession.shared.data(from: url),
              let antwort = try? JSONDecoder().decode(Antwort.self, from: daten) else { return nil }
        return antwort.product.sample_url.flatMap(URL.init(string:))
    }

    /// Tippfehler: Audible korrigiert sie nicht, schlägt aber schon ab dem Wortanfang vor.
    /// Kürzt den Suchtext von hinten, bis ein Autor oder Titel vorgeschlagen wird („Peinkover“ → „Michael Peinkofer“).
    public static func vorschlag(_ text: String) async -> String? {
        struct Antwort: Decodable {
            struct Wert: Decodable { let value: String }
            struct Person: Decodable { let name: Wert? }
            struct Produkt: Decodable { let title: Wert? }
            struct Modell: Decodable { let person_metadata: Person?; let product_metadata: Produkt? }
            struct Eintrag: Decodable { let model: Modell }
            struct Liste: Decodable { let items: [Eintrag] }
            let model: Liste
        }
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for _ in 0..<10 where rest.count >= 3 {
            var teile = URLComponents(string: "https://api.audible.de/1.0/searchsuggestions")!
            teile.queryItems = [URLQueryItem(name: "key_strokes", value: rest), URLQueryItem(name: "site_variant", value: "desktop")]
            if let url = teile.url, let (daten, _) = try? await URLSession.shared.data(from: url),
               let erster = (try? JSONDecoder().decode(Antwort.self, from: daten))?.model.items.first?.model,
               let wert = erster.person_metadata?.name?.value ?? erster.product_metadata?.title?.value {
                return wert
            }
            rest.removeLast()
        }
        return nil
    }
}
