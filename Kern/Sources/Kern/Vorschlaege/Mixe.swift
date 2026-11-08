import Foundation

/// Mixe aus Navidrome (ähnliche Titel über Last.fm) und dem eigenen Hörverlauf.
@MainActor
public enum Mixe {
    /// Mix aus den meistgehörten Künstlern und ihren ähnlichen Künstlern.
    public static func deinMix(_ client: NavidromeClient, kuenstler: [Kuenstler]) async -> [Titel] {
        var titel: [Titel] = []
        for k in kuenstler.prefix(5) {
            titel += (try? await client.aehnlicheTitel(k.id, anzahl: 15)) ?? []
        }
        if titel.count < 20 { titel += (try? await client.zufaelligeTitel(anzahl: 30)) ?? [] }
        return bereinigt(titel).shuffled()
    }

    /// Radio ab einem Künstler: seine Titel und die ähnlicher Künstler.
    public static func radio(kuenstler id: String, _ client: NavidromeClient) async -> [Titel] {
        bereinigt((try? await client.aehnlicheTitel(id, anzahl: 50)) ?? []).shuffled()
    }

    /// Radio ab einem Titel: erst der Titel, dann ähnliche.
    public static func radio(ab titel: Titel, _ client: NavidromeClient) async -> [Titel] {
        [titel] + bereinigt((try? await client.aehnlicheTitel(titel.id, anzahl: 50)) ?? []).filter { $0.id != titel.id }
    }

    /// Ohne doppelte und ohne oft übersprungene Titel.
    public static func bereinigt(_ titel: [Titel]) -> [Titel] {
        let unbeliebt = Hoerverlauf.geteilt.unbeliebt()
        var gesehen = Set<String>()
        return titel.filter { !unbeliebt.contains($0.id) && gesehen.insert($0.id).inserted }
    }
}
