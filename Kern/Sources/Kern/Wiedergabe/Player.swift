import AVFoundation
import MediaPlayer
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Spielt Titel von Navidrome lückenlos ab und meldet sich bei Sperrbildschirm, Kopfhörern, CarPlay und Watch.
@MainActor @Observable
public final class Player {
    public private(set) var warteschlange: [Titel] = []
    public private(set) var index = 0
    public private(set) var spielt = false
    public private(set) var zeit: Double = 0

    public var aktuell: Titel? { warteschlange.indices.contains(index) ? warteschlange[index] : nil }
    public var dauer: Double { Double(aktuell?.duration ?? 0) }

    @ObservationIgnored public var client: NavidromeClient?
    @ObservationIgnored private let player = AVQueuePlayer()
    /// Welcher geladene Eintrag zu welcher Stelle der Warteschlange gehört.
    @ObservationIgnored private var stellen: [ObjectIdentifier: Int] = [:]
    @ObservationIgnored private var beobachter: [Any] = []

    public init() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        #endif
        beobachter.append(player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] zeit in
            MainActor.assumeIsolated { self?.zeit = zeit.seconds.isFinite ? zeit.seconds : 0 }
        })
        beobachter.append(player.observe(\.currentItem) { [weak self] _, _ in
            Task { @MainActor in self?.eintragGewechselt() }
        })
        beobachter.append(player.observe(\.timeControlStatus) { [weak self] p, _ in
            let laeuft = p.timeControlStatus != .paused
            Task { @MainActor in
                self?.spielt = laeuft
                self?.zeitInfo()
            }
        })
        beobachter.append(NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] meldung in
            guard let eintrag = meldung.object as? AVPlayerItem else { return }
            let schluessel = ObjectIdentifier(eintrag)
            Task { @MainActor in self?.gehoert(schluessel) }
        })
        fernsteuerung()
    }

    // MARK: Steuerung

    public func spiele(_ titel: [Titel], ab start: Int = 0) {
        guard !titel.isEmpty else { return }
        warteschlange = titel
        lade(ab: start)
        player.play()
    }

    public func umschalten() { spielt ? player.pause() : player.play() }

    public func weiter() {
        guard index + 1 < warteschlange.count else { return }
        player.advanceToNextItem()
    }

    public func zurueck() {
        if zeit > 3 || index == 0 { springe(zu: 0) } else { lade(ab: index - 1); player.play() }
    }

    public func springe(zu sekunden: Double) {
        player.seek(to: CMTime(seconds: sekunden, preferredTimescale: 600))
        zeit = sekunden
        zeitInfo()
    }

    // MARK: Intern

    private func lade(ab start: Int) {
        player.removeAllItems()
        stellen = [:]
        index = start
        zeit = 0
        haengeAn(ab: start)
        eintragGewechselt()
    }

    /// Hängt die nächsten Titel an; immer nur ein Stück, damit lange Mixe schnell starten.
    private func haengeAn(ab start: Int) {
        guard let client else { return }
        for i in start..<min(warteschlange.count, start + 20) {
            let eintrag = AVPlayerItem(url: client.streamURL(warteschlange[i].id))
            stellen[ObjectIdentifier(eintrag)] = i
            player.insert(eintrag, after: nil)
        }
    }

    private func eintragGewechselt() {
        guard let eintrag = player.currentItem, let i = stellen[ObjectIdentifier(eintrag)] else { return }
        index = i
        if let letzte = stellen.values.max(), letzte < i + 3, letzte + 1 < warteschlange.count { haengeAn(ab: letzte + 1) }
        if let titel = aktuell, let client { Task { try? await client.scrobble(titel.id, fertig: false) } }
        nowPlaying()
    }

    private func gehoert(_ schluessel: ObjectIdentifier) {
        guard let i = stellen.removeValue(forKey: schluessel), let client else { return }
        let id = warteschlange[i].id
        Task { try? await client.scrobble(id, fertig: true) }
    }

    private func fernsteuerung() {
        let c = MPRemoteCommandCenter.shared()
        _ = c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.player.play() }; return .success }
        _ = c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.player.pause() }; return .success }
        _ = c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.umschalten() }; return .success }
        _ = c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.weiter() }; return .success }
        _ = c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.zurueck() }; return .success }
        _ = c.changePlaybackPositionCommand.addTarget { [weak self] ereignis in
            guard let ziel = (ereignis as? MPChangePlaybackPositionCommandEvent)?.positionTime else { return .commandFailed }
            Task { @MainActor in self?.springe(zu: ziel) }
            return .success
        }
    }

    private func nowPlaying() {
        guard let titel = aktuell else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: titel.title,
            MPMediaItemPropertyArtist: titel.artist ?? "",
            MPMediaItemPropertyAlbumTitle: titel.album ?? "",
            MPMediaItemPropertyPlaybackDuration: dauer,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: zeit,
            MPNowPlayingInfoPropertyPlaybackRate: spielt ? 1.0 : 0.0,
        ]
        #if canImport(UIKit)
        guard let url = client?.coverURL(titel.coverArt, groesse: 600) else { return }
        Task {
            guard let (daten, _) = try? await URLSession.shared.data(from: url), let bild = UIImage(data: daten),
                  aktuell?.id == titel.id else { return }
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: bild.size) { _ in bild }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
        #endif
    }

    private func zeitInfo() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = zeit
        info[MPNowPlayingInfoPropertyPlaybackRate] = spielt ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
