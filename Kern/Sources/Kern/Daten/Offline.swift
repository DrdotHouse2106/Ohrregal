import Foundation
import Observation

/// Ein vollständig oder teilweise geladenes Hörbuch.
public struct OfflineHoerbuch: Codable, Identifiable, Sendable {
    public let id: String
    public let titel: String
    public let autor: String
    public let dauer: Double
    public let kapitel: [Kapitel]
    public let dateien: [Datei]
    /// Zuletzt gehörte Stelle; wird offline gemerkt und später an Audiobookshelf gemeldet.
    public var position: Double = 0
    public var positionOffen = false

    public struct Datei: Codable, Sendable {
        public let name: String
        public let start: Double
    }
}

/// Downloads aufs iPhone: Musiktitel und Hörbücher. Läuft im Hintergrund weiter, auf Wunsch nur im WLAN.
@MainActor @Observable
public final class Offline {
    public static let geteilt = Offline()

    public private(set) var hoerbuecher: [OfflineHoerbuch] = []
    public private(set) var titel: [Titel] = []
    /// Fortschritt laufender Downloads (0…1), Schlüssel „h:<id>“ oder „t:<id>“.
    public private(set) var fortschritt: [String: Double] = [:]

    public var nurWLAN: Bool {
        didSet { UserDefaults.standard.set(nurWLAN, forKey: "offlineNurWLAN") }
    }
    public var hoerbuecherAutomatisch: Bool {
        didSet { UserDefaults.standard.set(hoerbuecherAutomatisch, forKey: "offlineHoerbuecherAuto") }
    }

    /// Wird vom App-Delegate gesetzt, wenn iOS die App für fertige Hintergrund-Downloads weckt.
    public var hintergrundFertig: (() -> Void)?

    nonisolated static let ordner: URL = {
        let o = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Offline")
        try? FileManager.default.createDirectory(at: o, withIntermediateDirectories: true)
        return o
    }()

    private var wartendeTitel: [String: Titel] = [:]
    @ObservationIgnored private var sitzung: URLSession!
    @ObservationIgnored private let helfer = Helfer()

    init() {
        let d = UserDefaults.standard
        nurWLAN = d.object(forKey: "offlineNurWLAN") as? Bool ?? true
        hoerbuecherAutomatisch = d.object(forKey: "offlineHoerbuecherAuto") as? Bool ?? true
        if let daten = try? Data(contentsOf: Self.ordner.appending(path: "index.json")),
           let index = try? JSONDecoder().decode(Index.self, from: daten) {
            hoerbuecher = index.hoerbuecher
            titel = index.titel
            wartendeTitel = Dictionary(index.wartend.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        }
        let konfiguration = URLSessionConfiguration.background(withIdentifier: "de.drdothouse.Ohrregal.offline")
        konfiguration.sessionSendsLaunchEvents = true
        konfiguration.isDiscretionary = false
        helfer.offline = self
        sitzung = URLSession(configuration: konfiguration, delegate: helfer, delegateQueue: nil)
    }

    private struct Index: Codable {
        var hoerbuecher: [OfflineHoerbuch]
        var titel: [Titel]
        var wartend: [Titel]
    }

    private func speichern() {
        let index = Index(hoerbuecher: hoerbuecher, titel: titel, wartend: Array(wartendeTitel.values))
        try? JSONEncoder().encode(index).write(to: Self.ordner.appending(path: "index.json"), options: .atomic)
    }

    // MARK: Abfragen

    public func datei(fuerTitel id: String) -> URL? {
        guard titel.contains(where: { $0.id == id }) else { return nil }
        return Self.dateien(in: "t").first { $0.deletingPathExtension().lastPathComponent == id }
    }

    /// Nur vollständig geladene Hörbücher.
    public func hoerbuch(_ id: String) -> OfflineHoerbuch? {
        guard let h = hoerbuecher.first(where: { $0.id == id }), fortschritt["h:\(id)"] == nil,
              h.dateien.allSatisfy({ FileManager.default.fileExists(atPath: Self.pfad(h, $0).path) }) else { return nil }
        return h
    }

    public func istGeladen(_ titelIds: [String]) -> Bool {
        !titelIds.isEmpty && titelIds.allSatisfy { id in titel.contains { $0.id == id } }
    }

    public func laedt(_ schluessel: String) -> Double? { fortschritt[schluessel] }

    /// Belegter Speicher in Bytes.
    public var belegt: Int64 {
        let alle = FileManager.default.enumerator(at: Self.ordner, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL] ?? []
        return alle.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    nonisolated static func pfad(_ h: OfflineHoerbuch, _ d: OfflineHoerbuch.Datei) -> URL {
        ordner.appending(path: "h/\(h.id)/\(d.name)")
    }

    nonisolated static func dateien(in unterordner: String) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: ordner.appending(path: unterordner), includingPropertiesForKeys: nil)) ?? []
    }

    // MARK: Laden

    public func lade(_ neu: [Titel], _ client: NavidromeClient) {
        for t in neu where !titel.contains(where: { $0.id == t.id }) && wartendeTitel[t.id] == nil {
            wartendeTitel[t.id] = t
            fortschritt["t:\(t.id)"] = 0
            var anfrage = URLRequest(url: client.streamURL(t.id))
            anfrage.allowsCellularAccess = !nurWLAN
            let aufgabe = sitzung.downloadTask(with: anfrage)
            aufgabe.taskDescription = "t|\(t.id)|\(t.id).\(t.suffix ?? "mp3")"
            aufgabe.resume()
        }
        speichern()
    }

    public func lade(hoerbuch: Hoerbuch, _ abs: AudiobookshelfClient) async throws {
        guard !hoerbuecher.contains(where: { $0.id == hoerbuch.id }) else { return }
        let voll = try await abs.dateien(hoerbuch.id)
        guard !voll.dateien.isEmpty else { throw ServerFehler("Das Hörbuch hat keine Dateien.") }
        var start = 0.0
        var dateien: [OfflineHoerbuch.Datei] = []
        for (i, d) in voll.dateien.enumerated() {
            dateien.append(.init(name: String(format: "%03d.%@", i, d.endung), start: start))
            start += d.dauer
        }
        let neu = OfflineHoerbuch(id: hoerbuch.id, titel: hoerbuch.titel, autor: hoerbuch.autor,
                                  dauer: voll.dauer ?? start, kapitel: voll.kapitel, dateien: dateien)
        hoerbuecher.append(neu)
        fortschritt["h:\(hoerbuch.id)"] = 0
        speichern()
        for (d, quelle) in zip(dateien, voll.dateien) {
            var anfrage = URLRequest(url: try await abs.dateiURL("/api/items/\(hoerbuch.id)/file/\(quelle.ino)"))
            anfrage.allowsCellularAccess = !nurWLAN
            let aufgabe = sitzung.downloadTask(with: anfrage)
            aufgabe.taskDescription = "h|\(hoerbuch.id)|\(d.name)"
            aufgabe.resume()
        }
    }

    // MARK: Löschen

    public func loesche(hoerbuch id: String) {
        abbrechen("h|\(id)|")
        try? FileManager.default.removeItem(at: Self.ordner.appending(path: "h/\(id)"))
        hoerbuecher.removeAll { $0.id == id }
        fortschritt["h:\(id)"] = nil
        speichern()
    }

    public func loesche(titel ids: [String]) {
        for id in ids {
            abbrechen("t|\(id)|")
            if let datei = datei(fuerTitel: id) { try? FileManager.default.removeItem(at: datei) }
            wartendeTitel[id] = nil
            fortschritt["t:\(id)"] = nil
        }
        titel.removeAll { ids.contains($0.id) }
        speichern()
    }

    public func loescheAlles() {
        sitzung.getAllTasks { $0.forEach { $0.cancel() } }
        try? FileManager.default.removeItem(at: Self.ordner)
        try? FileManager.default.createDirectory(at: Self.ordner, withIntermediateDirectories: true)
        hoerbuecher = []
        titel = []
        wartendeTitel = [:]
        fortschritt = [:]
        speichern()
    }

    private func abbrechen(_ praefix: String) {
        sitzung.getAllTasks { $0.filter { $0.taskDescription?.hasPrefix(praefix) == true }.forEach { $0.cancel() } }
    }

    // MARK: Hörposition offline

    /// Merkt die Stelle eines geladenen Hörbuchs; `offen` heißt: noch nicht an Audiobookshelf gemeldet.
    public func merke(position: Double, hoerbuch id: String, offen: Bool) {
        guard let i = hoerbuecher.firstIndex(where: { $0.id == id }) else { return }
        hoerbuecher[i].position = position
        hoerbuecher[i].positionOffen = hoerbuecher[i].positionOffen || offen
        speichern()
    }

    /// Meldet offline gehörte Stellen an Audiobookshelf nach.
    public func nachtragen(_ abs: AudiobookshelfClient) async {
        for h in hoerbuecher where h.positionOffen {
            if (try? await abs.fortschrittMelden(h.id, zeit: h.position, dauer: h.dauer)) != nil,
               let i = hoerbuecher.firstIndex(where: { $0.id == h.id }) {
                hoerbuecher[i].positionOffen = false
            }
        }
        speichern()
    }

    // MARK: Rückmeldungen der Downloads

    fileprivate func meldeFortschritt(_ beschreibung: String, _ anteil: Double) {
        let teile = beschreibung.split(separator: "|").map(String.init)
        guard teile.count == 3 else { return }
        let schluessel = "\(teile[0]):\(teile[1])"
        if teile[0] == "h", let h = hoerbuecher.first(where: { $0.id == teile[1] }), let i = h.dateien.firstIndex(where: { $0.name == teile[2] }) {
            // Gesamtfortschritt: fertige Dateien plus Anteil der laufenden.
            let fertig = h.dateien.filter { FileManager.default.fileExists(atPath: Self.pfad(h, $0).path) }.count
            fortschritt[schluessel] = min((Double(fertig) + (i < h.dateien.count ? anteil : 0)) / Double(h.dateien.count), 0.99)
        } else {
            fortschritt[schluessel] = min(anteil, 0.99)
        }
    }

    fileprivate func fertig(_ beschreibung: String) {
        let teile = beschreibung.split(separator: "|").map(String.init)
        guard teile.count == 3 else { return }
        if teile[0] == "t" {
            if let t = wartendeTitel.removeValue(forKey: teile[1]) { titel.append(t) }
            fortschritt["t:\(teile[1])"] = nil
        } else if let h = hoerbuecher.first(where: { $0.id == teile[1] }),
                  h.dateien.allSatisfy({ FileManager.default.fileExists(atPath: Self.pfad(h, $0).path) }) {
            fortschritt["h:\(teile[1])"] = nil
        }
        speichern()
    }

    fileprivate func fehlgeschlagen(_ beschreibung: String) {
        let teile = beschreibung.split(separator: "|").map(String.init)
        guard teile.count == 3 else { return }
        if teile[0] == "t" {
            wartendeTitel[teile[1]] = nil
            fortschritt["t:\(teile[1])"] = nil
            speichern()
        } else {
            loesche(hoerbuch: teile[1])
        }
    }
}

/// Empfängt die Rückmeldungen der Hintergrund-Downloads.
private final class Helfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var offline: Offline?

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let beschreibung = downloadTask.taskDescription,
              (downloadTask.response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else { return }
        let teile = beschreibung.split(separator: "|").map(String.init)
        guard teile.count == 3 else { return }
        // Die Datei muss hier sofort verschoben werden, danach löscht iOS sie.
        let ziel = Offline.ordner.appending(path: teile[0] == "h" ? "h/\(teile[1])/\(teile[2])" : "t/\(teile[2])")
        try? FileManager.default.createDirectory(at: ziel.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: ziel)
        try? FileManager.default.moveItem(at: location, to: ziel)
        Task { @MainActor in self.offline?.fertig(beschreibung) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let beschreibung = downloadTask.taskDescription, totalBytesExpectedToWrite > 0 else { return }
        let anteil = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in self.offline?.meldeFortschritt(beschreibung, anteil) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let fehler = error != nil || !((task.response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false)
        guard fehler, let beschreibung = task.taskDescription, (error as? URLError)?.code != .cancelled else { return }
        Task { @MainActor in self.offline?.fehlgeschlagen(beschreibung) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.offline?.hintergrundFertig?()
            self.offline?.hintergrundFertig = nil
        }
    }
}
