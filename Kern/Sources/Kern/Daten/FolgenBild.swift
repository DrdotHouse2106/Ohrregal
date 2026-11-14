import AVFoundation
import Foundation

/// Vorschaubild einer Podcast-Folge. Audiobookshelf kennt nur ein Bild pro Podcast;
/// das eigene Bild steckt aber in der Datei (z. B. YouTube-Vorschaubild) und wird einmal gelesen und zwischengespeichert.
@MainActor
public enum FolgenBild {
    nonisolated static let ordner: URL = {
        let o = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "Folgenbilder")
        try? FileManager.default.createDirectory(at: o, withIntermediateDirectories: true)
        return o
    }()

    private static var laufend: [String: Task<URL?, Never>] = [:]

    /// Schon bekanntes Bild (ohne Laden).
    public static func vorhanden(_ folge: String) -> URL? {
        let ziel = ordner.appending(path: "\(folge).jpg")
        return FileManager.default.fileExists(atPath: ziel.path) ? ziel : nil
    }

    /// Liest das Bild aus der Datei (geladen) bzw. dem Stream; AVFoundation holt dabei nur den Kopf der Datei.
    public static func bild(_ folge: String, quelle: URL) async -> URL? {
        if let da = vorhanden(folge) { return da }
        if let t = laufend[folge] { return await t.value }
        let aufgabe = Task<URL?, Never> {
            let asset = AVURLAsset(url: quelle)
            guard let meta = try? await asset.load(.commonMetadata),
                  let eintrag = AVMetadataItem.metadataItems(from: meta, filteredByIdentifier: .commonIdentifierArtwork).first,
                  let daten = try? await eintrag.load(.dataValue) else { return nil }
            let ziel = ordner.appending(path: "\(folge).jpg")
            try? daten.write(to: ziel, options: .atomic)
            return ziel
        }
        laufend[folge] = aufgabe
        let url = await aufgabe.value
        laufend[folge] = nil
        return url
    }

    /// Für Listen: Datei auf dem iPhone oder Stream von Audiobookshelf.
    public static func bild(_ folge: Folge, podcast: String, _ abs: AudiobookshelfClient) async -> URL? {
        if let da = vorhanden(folge.id) { return da }
        if let h = Offline.geteilt.hoerbuch(folge.id), let d = h.dateien.first { return await bild(folge.id, quelle: Offline.pfad(h, d)) }
        guard let ino = folge.ino, let url = try? await abs.dateiURL("/api/items/\(podcast)/file/\(ino)") else { return nil }
        return await bild(folge.id, quelle: url)
    }
}
