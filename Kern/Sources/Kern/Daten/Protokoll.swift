import AVFoundation
import Foundation

/// Ein Ereignis des Hörprotokolls (siehe Dienst/API.md, „/ereignisse“).
public struct Ereignis: Codable, Sendable {
    public var uid = UUID().uuidString
    public let typ: String
    public var zeit = Date()
    public let art: String
    public var id: String?
    public var titel: String?
    public var kuenstler: String?
    public var kuenstlerId: String?
    public var albumId: String?
    public var position: Double?
    public var dauer: Double?
    public var wert: String?
    public var quelle: String?
    public var geraet = "iPhone"
    public var ausgabe: String?
}

/// Sammelt das Hörprotokoll, hält es offline vor und schickt es gebündelt an den eigenen Server.
@MainActor
public final class Protokoll {
    public static let geteilt = Protokoll()

    public enum Antwort: Sendable {
        case angenommen
        case spaeter
        case zuGross
        /// Der Server lehnt den Stapel ab; der Text nennt die uid des kaputten Ereignisses.
        case ungueltig(String)
    }

    /// Schickt einen Stapel. Wird von der App gesetzt.
    public var senden: (@MainActor ([Ereignis]) async -> Antwort)?
    /// Wird von CarPlay gesetzt, solange es verbunden ist.
    public var geraet = "iPhone"

    private var offen: [Ereignis] = []
    private var sendetGerade = false
    private let datei: URL

    init() {
        let ordner = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        datei = ordner.appending(path: "protokoll.json")
        offen = (try? Data(contentsOf: datei)).flatMap { try? JSONDecoder().decode([Ereignis].self, from: $0) } ?? []
    }

    public func merke(_ typ: String, titel t: Titel? = nil, art: String = "musik", position: Double? = nil, dauer: Double? = nil,
                      wert: String? = nil, quelle: String? = nil, id: String? = nil, name: String? = nil, urheber: String? = nil) {
        var e = Ereignis(typ: typ, art: art)
        e.id = t?.id ?? id
        e.titel = t?.title ?? name
        e.kuenstler = t?.artist ?? urheber
        e.kuenstlerId = t?.artistId
        e.albumId = t?.albumId
        e.position = position.map { ($0 * 10).rounded() / 10 }
        e.dauer = dauer ?? t?.duration.map(Double.init)
        e.wert = wert
        e.quelle = quelle
        e.geraet = geraet
        e.ausgabe = Self.ausgabe
        offen.append(e)
        if offen.count > 20_000 { offen.removeFirst(offen.count - 20_000) }
        speichern()
        if offen.count >= 20 { Task { await abschicken() } }
    }

    /// Schickt alles Offene in Stapeln bis 200 Ereignisse und etwa 80 KB (der Proxy nimmt höchstens 100 KB).
    /// Bei Verbindungsfehlern bleibt alles liegen; kaputte Ereignisse werden verworfen, damit nichts festhängt.
    public func abschicken() async {
        guard !sendetGerade, let senden, !offen.isEmpty else { return }
        sendetGerade = true
        defer { sendetGerade = false }
        var hoechstens = 200
        while !offen.isEmpty {
            var stapel: [Ereignis] = []
            var groesse = 0
            for e in offen.prefix(hoechstens) {
                let bytes = (try? JSONEncoder().encode(e).count) ?? 500
                if !stapel.isEmpty && groesse + bytes > 80_000 { break }
                stapel.append(e)
                groesse += bytes
            }
            switch await senden(stapel) {
            case .angenommen:
                let erledigt = Set(stapel.map(\.uid))
                offen.removeAll { erledigt.contains($0.uid) }
                hoechstens = 200
            case .zuGross:
                guard stapel.count > 1 else { offen.removeAll { $0.uid == stapel[0].uid }; break }
                hoechstens = max(stapel.count / 2, 1)
            case .ungueltig(let text):
                let kaputt = stapel.first { text.contains($0.uid) }?.uid ?? stapel[0].uid
                offen.removeAll { $0.uid == kaputt }
            case .spaeter:
                return
            }
            speichern()
        }
    }

    private func speichern() {
        try? JSONEncoder().encode(offen).write(to: datei, options: .atomic)
    }

    static var ausgabe: String? {
        #if os(iOS)
        switch AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType {
        case .builtInSpeaker, .builtInReceiver: return "Lautsprecher"
        case .headphones: return "Kopfhörer"
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP: return "Bluetooth"
        case .airPlay: return "AirPlay"
        case .carAudio: return "Auto"
        default: return nil
        }
        #else
        return nil
        #endif
    }
}
