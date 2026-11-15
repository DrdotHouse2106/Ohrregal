import Foundation
import Network
import Observation

/// „Vom iPhone auf den Fernseher“: findet Ohrregal-TV-Apps im Heimnetz (Bonjour `_ohrregal._tcp`)
/// und schickt ihnen, was gerade läuft. Gestreamt wird danach direkt vom eigenen Server zum Fernseher.
@MainActor @Observable
public final class Fernseher {
    public static let geteilt = Fernseher()

    public struct Geraet: Identifiable, Hashable, @unchecked Sendable {
        public let name: String
        let endpunkt: NWEndpoint
        public var id: String { name }
    }

    public private(set) var geraete: [Geraet] = []
    @ObservationIgnored private var browser: NWBrowser?

    public func suchen() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjour(type: "_ohrregal._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] ergebnisse, _ in
            let liste = ergebnisse.compactMap { r -> Geraet? in
                if case let .service(name, _, _, _) = r.endpoint { return Geraet(name: name, endpunkt: r.endpoint) }
                return nil
            }.sorted { $0.name < $1.name }
            Task { @MainActor in self?.geraete = liste }
        }
        b.start(queue: .main)
        browser = b
    }

    /// Kleine HTTP-Anfrage direkt über TCP (ohne URLSession: kein ATS, keine Namensauflösung nötig).
    /// `warten`: Sekunden bis zur Antwort (beim Einrichten wartet der Fernseher auf „Übernehmen“).
    public func sende(_ g: Geraet, _ pfad: String, json: [String: Any], warten: Double = 10) async throws {
        let rumpf = try JSONSerialization.data(withJSONObject: json)
        var anfrage = Data("POST \(pfad) HTTP/1.1\r\nHost: ohrregal\r\nContent-Type: application/json\r\nContent-Length: \(rumpf.count)\r\nConnection: close\r\n\r\n".utf8)
        anfrage.append(rumpf)
        let text = String(decoding: try await Self.austausch(g.endpunkt, anfrage, warten: warten), as: UTF8.self)
        let code = Int(text.split(separator: " ").dropFirst().first ?? "") ?? 0
        guard (200..<300).contains(code) else {
            let inhalt = text.components(separatedBy: "\r\n\r\n").dropFirst().joined()
            let meldung = (try? JSONSerialization.jsonObject(with: Data(inhalt.utf8)) as? [String: Any])?["text"] as? String
            throw ServerFehler(meldung ?? (code == 0 ? "Der Fernseher antwortet nicht." : "Der Fernseher meldet Fehler \(code)."))
        }
    }

    private final class Lauf: @unchecked Sendable {
        var fertig = false
        var daten = Data()
    }

    nonisolated static func austausch(_ ziel: NWEndpoint, _ daten: Data, warten: Double) async throws -> Data {
        let verbindung = NWConnection(to: ziel, using: .tcp)
        let schlange = DispatchQueue(label: "fernseher")
        let lauf = Lauf()
        return try await withCheckedThrowingContinuation { fortsetzung in
            func ende(_ ergebnis: Result<Data, Error>) {
                guard !lauf.fertig else { return }
                lauf.fertig = true
                verbindung.cancel()
                fortsetzung.resume(with: ergebnis)
            }
            func lesen() {
                verbindung.receive(minimumIncompleteLength: 1, maximumLength: 65536) { teil, _, komplett, fehler in
                    if let teil { lauf.daten.append(teil) }
                    if komplett || fehler != nil { ende(.success(lauf.daten)) } else { lesen() }
                }
            }
            verbindung.stateUpdateHandler = { zustand in
                switch zustand {
                case .ready:
                    verbindung.send(content: daten, completion: .contentProcessed { fehler in if let fehler { ende(.failure(fehler)) } })
                    lesen()
                case .failed(let fehler), .waiting(let fehler):
                    ende(.failure(fehler))
                default:
                    break
                }
            }
            verbindung.start(queue: schlange)
            schlange.asyncAfter(deadline: .now() + warten) { ende(.failure(ServerFehler("Der Fernseher antwortet nicht. Ist Ohrregal dort geöffnet?"))) }
        }
    }
}
