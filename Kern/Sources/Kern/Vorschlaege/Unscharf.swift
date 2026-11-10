import Foundation

/// Fehlertolerante Suche: Tippfehler, Umlaute und Groß-/Kleinschreibung spielen keine Rolle.
public enum Unscharf {
    /// Kleinbuchstaben, ohne Akzente, Umlaute als Grundbuchstabe (ä/ae → a), nur Buchstaben, Ziffern und Leerzeichen.
    public static func einfach(_ text: String) -> String {
        var t = text.lowercased()
        for (a, b) in [("ae", "a"), ("oe", "o"), ("ue", "u"), ("ß", "ss")] { t = t.replacingOccurrences(of: a, with: b) }
        t = t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
        return String(t.map { $0.isLetter || $0.isNumber ? $0 : " " }).split(separator: " ").joined(separator: " ")
    }

    /// 0…1: Wie gut passt die Suche zum Namen? Jedes Suchwort zählt mit seinem besten Gegenstück im Namen.
    public static func aehnlichkeit(_ suche: String, _ name: String) -> Double {
        let woerter = einfach(suche).split(separator: " ").map(String.init)
        let ziel = einfach(name).split(separator: " ").map(String.init)
        guard !woerter.isEmpty, !ziel.isEmpty else { return 0 }
        let werte = woerter.map { w in
            ziel.map { z -> Double in
                if z.hasPrefix(w) { return 1 }
                let vergleich = String(z.prefix(max(w.count, 1) + 1))
                return 1 - Double(abstand(w, vergleich)) / Double(max(w.count, vergleich.count))
            }.max() ?? 0
        }
        return werte.reduce(0, +) / Double(werte.count)
    }

    /// Levenshtein-Abstand.
    static func abstand(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var vorher = Array(0...b.count)
        for i in 1...a.count {
            var jetzt = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                jetzt[j] = min(vorher[j] + 1, jetzt[j - 1] + 1, vorher[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            vorher = jetzt
        }
        return vorher[b.count]
    }
}

extension NavidromeClient {
    /// Suche wie `suche`, findet aber auch bei Tippfehlern: Liefert Navidrome zu wenig, werden Kandidaten über
    /// die Wortanfänge geholt und nach Ähnlichkeit sortiert.
    public func sucheUnscharf(_ text: String) async throws -> Suchergebnis {
        let genau = try await suche(text)
        let anzahl = (genau?.artist?.count ?? 0) + (genau?.album?.count ?? 0) + (genau?.song?.count ?? 0)
        if anzahl >= 5, let genau { return genau }

        var kuenstler = genau?.artist ?? [], alben = genau?.album ?? [], titel = genau?.song ?? []
        let woerter = Set(Unscharf.einfach(text).split(separator: " ").filter { $0.count >= 3 }.map { String($0.prefix(3)) })
        for wort in woerter {
            guard let mehr = try? await hole("search3", ["query": wort, "artistCount": "40", "albumCount": "40", "songCount": "60"]).searchResult3 else { continue }
            kuenstler += mehr.artist ?? []
            alben += mehr.album ?? []
            titel += mehr.song ?? []
        }
        func beste<T: Identifiable>(_ liste: [T], _ name: (T) -> String, _ hoechstens: Int) -> [T] where T.ID == String {
            var gesehen = Set<String>()
            return liste.filter { gesehen.insert($0.id).inserted }
                .map { ($0, Unscharf.aehnlichkeit(text, name($0))) }
                .filter { $0.1 >= 0.7 }
                .sorted { $0.1 > $1.1 }
                .prefix(hoechstens).map(\.0)
        }
        return Suchergebnis(artist: beste(kuenstler, \.name, 10),
                            album: beste(alben, { "\($0.name) \($0.artist ?? "")" }, 20),
                            song: beste(titel, { "\($0.title) \($0.artist ?? "")" }, 30))
    }
}
