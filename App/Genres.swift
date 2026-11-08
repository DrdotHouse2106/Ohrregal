import Foundation

/// Deutsche Namen für die Genres aus Audiobookshelf (Audible liefert sie oft englisch).
/// nil heißt ausblenden: „Audiobook“ oder „Hörbuch“ sagen nichts über den Inhalt.
enum Genres {
    static func deutsch(_ genre: String) -> String? {
        let schluessel = genre.lowercased().trimmingCharacters(in: .whitespaces)
        if ["audiobook", "audiobooks", "hörbuch", "hörbücher", "hoerbuch", "hoerbuecher"].contains(schluessel) { return nil }
        return namen[schluessel] ?? genre
    }

    private static let namen: [String: String] = [
        "hoerspiel": "Hörspiele", "hörspiel": "Hörspiele", "hörspiele": "Hörspiele", "radio drama": "Hörspiele",
        "radio & tv": "Hörspiele", "drama & poetry": "Drama & Lyrik",
        "arts & entertainment": "Kunst & Unterhaltung",
        "biographies & memoirs": "Biografien & Erinnerungen", "biography": "Biografien",
        "business & careers": "Wirtschaft & Karriere", "business": "Wirtschaft",
        "children's audiobooks": "Kinderhörbücher", "children": "Kinderhörbücher", "kinder": "Kinderhörbücher",
        "comedy & humor": "Comedy & Humor", "humor": "Humor",
        "computers & technology": "Computer & Technologie",
        "education & learning": "Bildung & Lernen",
        "erotica": "Erotik",
        "health & wellness": "Gesundheit & Wellness",
        "history": "Geschichte",
        "home & garden": "Haus & Garten",
        "literature & fiction": "Literatur & Belletristik", "fiction": "Belletristik", "classics": "Klassiker",
        "money & finance": "Geld & Finanzen",
        "mystery, thriller & suspense": "Krimis & Thriller", "mystery": "Krimis", "thriller": "Thriller",
        "thriller & suspense": "Thriller", "crime": "Krimis", "suspense": "Spannung",
        "politics & social sciences": "Politik & Gesellschaft",
        "relationships, parenting & personal development": "Beziehungen & Persönlichkeit",
        "religion & spirituality": "Religion & Spiritualität",
        "romance": "Liebesromane",
        "science & engineering": "Wissenschaft & Technik", "science": "Wissenschaft",
        "science fiction & fantasy": "Science-Fiction & Fantasy", "science fiction": "Science-Fiction",
        "sports & outdoors": "Sport & Outdoor",
        "teen & young adult": "Jugendbücher", "young adult": "Jugendbücher",
        "travel & tourism": "Reisen & Tourismus",
        "self-help": "Ratgeber", "non-fiction": "Sachbuch", "nonfiction": "Sachbuch",
    ]
}
