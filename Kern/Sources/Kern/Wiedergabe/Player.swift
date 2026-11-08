import AVFoundation
import MediaPlayer
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Was gerade läuft, unabhängig davon, ob Musik oder Hörbuch.
public struct Anzeige: Equatable, Sendable {
    public let titel: String
    public let untertitel: String
    public let cover: URL?
    public let dauer: Double
}

/// Spielt Musik von Navidrome und Hörbücher von Audiobookshelf.
/// Meldet sich bei Sperrbildschirm, Kopfhörern, CarPlay und Watch.
@MainActor @Observable
public final class Player {
    public private(set) var warteschlange: [Titel] = []
    public private(set) var index = 0
    public private(set) var spielt = false
    /// Bei Hörbüchern die Zeit im ganzen Buch.
    public private(set) var zeit: Double = 0
    public private(set) var anzeige: Anzeige?
    public private(set) var istHoerbuch = false
    public private(set) var kapitel: [Kapitel] = []
    public private(set) var schlafenUm: Date?
    public private(set) var schlafenAmKapitelende = false
    public var fehler: String?

    /// Geschwindigkeit für Hörbücher.
    public var tempo: Float = UserDefaults.standard.object(forKey: "tempo") as? Float ?? 1 {
        didSet {
            UserDefaults.standard.set(tempo, forKey: "tempo")
            guard istHoerbuch else { return }
            player.defaultRate = tempo
            if spielt { player.rate = tempo }
        }
    }

    public var aktuell: Titel? { !istHoerbuch && warteschlange.indices.contains(index) ? warteschlange[index] : nil }
    public var dauer: Double { anzeige?.dauer ?? 0 }
    public var aktuellesKapitel: Kapitel? { kapitel.last { $0.start <= zeit + 0.5 } }

    @ObservationIgnored public var client: NavidromeClient?
    @ObservationIgnored public var hoerbuchClient: AudiobookshelfClient?
    @ObservationIgnored private let player = AVQueuePlayer()
    /// Abspielbare Dateien mit ihrem Beginn im Gesamtverlauf (Musik: immer 0).
    @ObservationIgnored private var spuren: [(url: URL, start: Double)] = []
    @ObservationIgnored private var stellen: [ObjectIdentifier: Int] = [:]
    @ObservationIgnored private var spur = 0
    @ObservationIgnored private var sitzung: String?
    @ObservationIgnored private var gehoertSeitSync: Double = 0
    @ObservationIgnored private var beobachter: [Any] = []

    public init() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        #endif
        beobachter.append(player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] zeit in
            MainActor.assumeIsolated { self?.tick(zeit.seconds.isFinite ? zeit.seconds : 0) }
        })
        beobachter.append(player.observe(\.currentItem) { [weak self] _, _ in
            Task { @MainActor in self?.eintragGewechselt() }
        })
        beobachter.append(player.observe(\.timeControlStatus) { [weak self] p, _ in
            let laeuft = p.timeControlStatus != .paused
            Task { @MainActor in self?.laeuftGeaendert(laeuft) }
        })
        beobachter.append(NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] meldung in
            guard let eintrag = meldung.object as? AVPlayerItem else { return }
            let schluessel = ObjectIdentifier(eintrag)
            Task { @MainActor in self?.gehoert(schluessel) }
        })
        fernsteuerung()
    }

    // MARK: Starten

    public func spiele(_ titel: [Titel], ab start: Int = 0) {
        guard let client, !titel.isEmpty else { return }
        beendeHoerbuch()
        istHoerbuch = false
        kapitel = []
        warteschlange = titel
        spuren = titel.map { (client.streamURL($0.id), 0) }
        player.defaultRate = 1
        lade(ab: start, zeit: 0)
        player.play()
        knoepfe()
    }

    /// Startet ein Hörbuch an der zuletzt gehörten Stelle (von Audiobookshelf).
    public func spiele(hoerbuch: Hoerbuch) async {
        guard let abs = hoerbuchClient else { return }
        beendeHoerbuch()
        player.pause()
        do {
            let neu = try await abs.starte(hoerbuch.id)
            var dateien: [(url: URL, start: Double)] = []
            for s in neu.audioTracks.sorted(by: { $0.startOffset < $1.startOffset }) {
                dateien.append((try await abs.dateiURL(s.contentUrl), s.startOffset))
            }
            guard !dateien.isEmpty else { throw ServerFehler("Das Hörbuch hat keine abspielbaren Dateien.") }
            sitzung = neu.id
            istHoerbuch = true
            warteschlange = []
            kapitel = neu.chapters ?? []
            spuren = dateien
            anzeige = Anzeige(titel: neu.displayTitle ?? hoerbuch.titel, untertitel: neu.displayAuthor ?? hoerbuch.autor,
                              cover: abs.coverURL(hoerbuch.id), dauer: neu.duration)
            let start = neu.currentTime ?? 0
            player.defaultRate = tempo
            lade(ab: spuren.lastIndex { $0.start <= start } ?? 0, zeit: start)
            player.play()
            knoepfe()
            nowPlaying()
        } catch {
            fehler = error.localizedDescription
        }
    }

    // MARK: Steuerung

    public func umschalten() { spielt ? player.pause() : player.play() }

    /// Musik: nächster Titel. Hörbuch: 30 Sekunden vor.
    public func weiter() {
        if istHoerbuch { springe(zu: min(zeit + 30, dauer)); return }
        guard index + 1 < warteschlange.count else { return }
        player.advanceToNextItem()
    }

    /// Musik: Anfang oder vorheriger Titel. Hörbuch: 15 Sekunden zurück.
    public func zurueck() {
        if istHoerbuch { springe(zu: max(zeit - 15, 0)); return }
        if zeit > 3 || index == 0 { springe(zu: 0) } else { lade(ab: index - 1, zeit: 0); player.play() }
    }

    public func springe(zu ziel: Double) {
        guard !spuren.isEmpty else { return }
        let neu = spuren.lastIndex { $0.start <= ziel } ?? 0
        if neu == spur, player.currentItem != nil {
            player.seek(to: CMTime(seconds: ziel - spuren[neu].start, preferredTimescale: 600))
            zeit = ziel
        } else {
            let lief = spielt
            lade(ab: neu, zeit: ziel)
            if lief { player.play() }
        }
        zeitInfo()
    }

    /// Schlaf-Timer: nach Minuten (nil = aus).
    public func schlafen(in minuten: Int?) {
        schlafenAmKapitelende = false
        schlafenUm = minuten.map { Date().addingTimeInterval(Double($0) * 60) }
    }

    public func schlafenAmEndeDesKapitels() {
        schlafenUm = nil
        schlafenAmKapitelende = true
    }

    // MARK: Intern

    private func lade(ab start: Int, zeit ziel: Double) {
        player.removeAllItems()
        stellen = [:]
        spur = start
        haengeAn(ab: start)
        let versatz = ziel - spuren[start].start
        if versatz > 0.5 { player.seek(to: CMTime(seconds: versatz, preferredTimescale: 600)) }
        zeit = ziel
        eintragGewechselt()
    }

    /// Hängt die nächsten Dateien an; immer nur ein Stück, damit lange Mixe schnell starten.
    private func haengeAn(ab start: Int) {
        for i in start..<min(spuren.count, start + 20) {
            let eintrag = AVPlayerItem(url: spuren[i].url)
            stellen[ObjectIdentifier(eintrag)] = i
            player.insert(eintrag, after: nil)
        }
    }

    private func eintragGewechselt() {
        guard let eintrag = player.currentItem, let i = stellen[ObjectIdentifier(eintrag)] else { return }
        spur = i
        if let letzte = stellen.values.max(), letzte < i + 3, letzte + 1 < spuren.count { haengeAn(ab: letzte + 1) }
        guard !istHoerbuch else { return }
        index = i
        if let titel = aktuell {
            anzeige = Anzeige(titel: titel.title, untertitel: titel.artist ?? "",
                              cover: client?.coverURL(titel.coverArt, groesse: 600), dauer: Double(titel.duration ?? 0))
            if let client { Task { try? await client.scrobble(titel.id, fertig: false) } }
        }
        nowPlaying()
    }

    private func tick(_ sekunden: Double) {
        guard spuren.indices.contains(spur) else { return }
        zeit = spuren[spur].start + sekunden
        guard spielt else { return }
        if let um = schlafenUm, Date() >= um { player.pause(); schlafenUm = nil }
        if schlafenAmKapitelende, let k = aktuellesKapitel, zeit >= k.end - 0.6 { player.pause(); schlafenAmKapitelende = false }
        if istHoerbuch {
            gehoertSeitSync += 0.5 * Double(tempo)
            if gehoertSeitSync >= 15 { synchronisiere() }
        }
    }

    private func laeuftGeaendert(_ laeuft: Bool) {
        spielt = laeuft
        if !laeuft { synchronisiere() }
        zeitInfo()
    }

    private func gehoert(_ schluessel: ObjectIdentifier) {
        guard let i = stellen.removeValue(forKey: schluessel), !istHoerbuch, let client, warteschlange.indices.contains(i) else { return }
        let id = warteschlange[i].id
        Task { try? await client.scrobble(id, fertig: true) }
    }

    /// Meldet die Hörposition an Audiobookshelf (alle 15 s, beim Pausieren und am Ende).
    private func synchronisiere(schliessen: Bool = false) {
        guard istHoerbuch, let sitzung, let abs = hoerbuchClient else { return }
        let zeit = zeit, dauer = dauer, gehoert = gehoertSeitSync
        gehoertSeitSync = 0
        Task { try? await abs.synchronisiere(sitzung, zeit: zeit, gehoert: gehoert, dauer: dauer, schliessen: schliessen) }
    }

    private func beendeHoerbuch() {
        guard istHoerbuch else { return }
        synchronisiere(schliessen: true)
        sitzung = nil
    }

    private func fernsteuerung() {
        let c = MPRemoteCommandCenter.shared()
        _ = c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.player.play() }; return .success }
        _ = c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.player.pause() }; return .success }
        _ = c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.umschalten() }; return .success }
        _ = c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.weiter() }; return .success }
        _ = c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.zurueck() }; return .success }
        c.skipForwardCommand.preferredIntervals = [30]
        c.skipBackwardCommand.preferredIntervals = [15]
        _ = c.skipForwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.weiter() }; return .success }
        _ = c.skipBackwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.zurueck() }; return .success }
        _ = c.changePlaybackPositionCommand.addTarget { [weak self] ereignis in
            guard let ziel = (ereignis as? MPChangePlaybackPositionCommandEvent)?.positionTime else { return .commandFailed }
            Task { @MainActor in self?.springe(zu: ziel) }
            return .success
        }
        knoepfe()
    }

    /// Hörbuch: Sprungtasten statt Titel vor/zurück.
    private func knoepfe() {
        let c = MPRemoteCommandCenter.shared()
        c.nextTrackCommand.isEnabled = !istHoerbuch
        c.previousTrackCommand.isEnabled = !istHoerbuch
        c.skipForwardCommand.isEnabled = istHoerbuch
        c.skipBackwardCommand.isEnabled = istHoerbuch
    }

    private func nowPlaying() {
        guard let a = anzeige else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: a.titel,
            MPMediaItemPropertyArtist: a.untertitel,
            MPMediaItemPropertyAlbumTitle: aktuell?.album ?? "",
            MPMediaItemPropertyPlaybackDuration: a.dauer,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: zeit,
            MPNowPlayingInfoPropertyPlaybackRate: spielt ? Double(player.rate) : 0.0,
        ]
        #if canImport(UIKit)
        guard let url = a.cover else { return }
        Task {
            guard let (daten, _) = try? await URLSession.shared.data(from: url), let bild = UIImage(data: daten),
                  anzeige == a else { return }
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: bild.size) { _ in bild }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
        #endif
    }

    private func zeitInfo() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = zeit
        info[MPNowPlayingInfoPropertyPlaybackRate] = spielt ? Double(player.rate) : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
