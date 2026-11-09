import BackgroundTasks
import Kern
import SwiftUI

/// Vorrat der Startseite: liegt auf dem iPhone, erscheint sofort und wird nachts im Hintergrund erneuert.
struct StartVorrat: Codable {
    var zeit = Date()
    var zuletzt: [Album] = []
    var reihen: [StartView.Reihe] = []
    var mixe: [Mix] = []

    private static var datei: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "startvorrat.json")
    }

    static func laden() -> StartVorrat? {
        (try? Data(contentsOf: datei)).flatMap { try? JSONDecoder().decode(StartVorrat.self, from: $0) }
    }

    func speichern() {
        try? JSONEncoder().encode(self).write(to: Self.datei, options: .atomic)
    }

    @MainActor static func berechnen(_ client: NavidromeClient) async throws -> StartVorrat {
        async let zuletztAnfrage = client.alben("recent", anzahl: 50)
        async let haeufigAnfrage = client.alben("frequent", anzahl: 50)
        async let neuAnfrage = client.alben("newest")
        async let gefaelltAnfrage = client.alben("starred")
        async let zufallAnfrage = client.alben("random")
        let kuerzlich = try await zuletztAnfrage
        let oft = try await haeufigAnfrage
        let gehoert = Set(kuerzlich.map(\.id))
        var vorrat = StartVorrat()
        vorrat.zuletzt = Array(kuerzlich.prefix(15))
        vorrat.reihen = [
            .init(titel: "Am häufigsten gespielt", alben: Array(oft.prefix(20))),
            // Oft gespielt, aber nicht unter den letzten 50.
            .init(titel: "Lange nicht gehört", alben: Array(oft.filter { !gehoert.contains($0.id) }.prefix(20))),
            .init(titel: "Kürzlich hinzugefügt", alben: try await neuAnfrage),
            .init(titel: "Alben mit „Gefällt mir“", alben: (try? await gefaelltAnfrage) ?? []),
            .init(titel: "Zufällige Alben", alben: try await zufallAnfrage),
        ].filter { !$0.alben.isEmpty }
        vorrat.mixe = await Mix.laden(client, haeufig: oft)
        return vorrat
    }
}

/// Nächtliches Erneuern im Hintergrund (iOS entscheidet den genauen Zeitpunkt, frühestens 3 Uhr).
enum Hintergrund {
    static let kennung = "de.drdothouse.Ohrregal.vorladen"

    static func registrieren() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: kennung, using: nil) { aufgabe in
            let arbeit = Task { @MainActor in
                if let client = geteilteSitzung.client, let vorrat = try? await StartVorrat.berechnen(client) {
                    vorrat.speichern()
                }
                if let abs = geteilteSitzung.hoerbuchClient { await Offline.geteilt.nachtragen(abs) }
                aufgabe.setTaskCompleted(success: true)
                planen()
            }
            aufgabe.expirationHandler = { arbeit.cancel() }
        }
    }

    static func planen() {
        let anfrage = BGAppRefreshTaskRequest(identifier: kennung)
        var kalender = Calendar.current
        kalender.timeZone = .current
        anfrage.earliestBeginDate = kalender.nextDate(after: Date(), matching: DateComponents(hour: 3), matchingPolicy: .nextTime)
        try? BGTaskScheduler.shared.submit(anfrage)
    }
}
