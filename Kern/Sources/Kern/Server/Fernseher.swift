import CryptoKit
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
        /// Ziel für Rückfragen („192.168.1.20“).
        public var adresse: String { if case let .hostPort(h, _) = endpunkt { return "\(h)" }; return name }
        public var id: String { name }

        /// Von Hand eingegebene Adresse bzw. Adresse aus dem QR-Code („192.168.1.20“ oder „192.168.1.20:47811“).
        /// Nur private IPv4-Adressen im Heimnetz, keine Hostnamen: Zugangsdaten dürfen nie ins Internet gehen.
        public static func manuell(_ text: String) -> Geraet? {
            let t = text.trimmingCharacters(in: .whitespaces)
            let teile = t.split(separator: ":")
            guard let host = teile.first, Fernseher.istHeimnetz(String(host)) else { return nil }
            let port = teile.count > 1 ? UInt16(teile[1]) : 47811
            guard let port, let p = NWEndpoint.Port(rawValue: port) else { return nil }
            return Geraet(name: t, endpunkt: .hostPort(host: NWEndpoint.Host(String(host)), port: p))
        }
    }

    /// 10/8, 172.16/12, 192.168/16, 169.254/16 – sonst nein.
    public nonisolated static func istHeimnetz(_ ip: String) -> Bool {
        let z = ip.split(separator: ".").compactMap { UInt8($0) }
        guard z.count == 4, ip.split(separator: ".").count == 4 else { return false }
        return z[0] == 10 || (z[0] == 172 && (16...31).contains(z[1])) || (z[0] == 192 && z[1] == 168) || (z[0] == 169 && z[1] == 254)
    }

    /// Zugänge für den QR-Weg verschlüsseln (AES-GCM, Schlüssel = SHA-256 des Codes auf dem Bildschirm).
    /// Der Code selbst geht nicht übers Netz; nur der Fernseher, der ihn anzeigt, kann die Daten lesen.
    public nonisolated static func verschluesseln(_ json: [String: Any], code: String) throws -> String {
        let schluessel = SymmetricKey(data: SHA256.hash(data: Data(code.utf8)))
        let daten = try JSONSerialization.data(withJSONObject: json)
        guard let paket = try AES.GCM.seal(daten, using: schluessel).combined else { throw ServerFehler("Verschlüsseln fehlgeschlagen.") }
        return paket.base64EncodedString()
    }

    public private(set) var geraete: [Geraet] = []
    @ObservationIgnored private var browser: NWBrowser?

    public func suchen() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: "_ohrregal._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] ergebnisse, _ in
            let liste = ergebnisse.compactMap { r -> Geraet? in
                guard case let .service(name, _, _, _) = r.endpoint else { return nil }
                // Alle Fernseh-Sticks heißen „Android.local“: direkt an die mitgeschickte IPv4 und den Port des Dienstes.
                if case let .bonjour(txt) = r.metadata, let ip = txt["ip"], Self.istHeimnetz(ip),
                   let port = txt["port"].flatMap(UInt16.init).flatMap(NWEndpoint.Port.init(rawValue:)) {
                    return Geraet(name: name, endpunkt: .hostPort(host: NWEndpoint.Host(ip), port: port))
                }
                return Geraet(name: name, endpunkt: r.endpoint)
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
