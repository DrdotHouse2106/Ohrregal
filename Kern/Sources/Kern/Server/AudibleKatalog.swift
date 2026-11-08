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
}
