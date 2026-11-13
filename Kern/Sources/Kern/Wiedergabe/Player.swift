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
    public private(set) var istRadio = false
    public private(set) var kapitel: [Kapitel] = []
    public private(set) var schlafenUm: Date?
    public private(set) var schlafenAmKapitelende = false
    public var fehler: String?

    /// Autoplay wie bei Apple Music: Läuft die Warteschlange aus, geht es mit ähnlichen Titeln weiter.
    public var autoplay: Bool = UserDefaults.standard.object(forKey: "autoplay") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoplay, forKey: "autoplay") }
    }
    @ObservationIgnored private var autoplayLaeuft = false

    /// Geschwindigkeit für Hörbücher.
    public var tempo: Float = UserDefaults.standard.object(forKey: "tempo") as? Float ?? 1 {
        didSet {
            UserDefaults.standard.set(tempo, forKey: "tempo")
            guard istHoerbuch else { return }
            Protokoll.geteilt.merke("tempo", art: "hoerbuch", position: zeit, wert: String(tempo), id: hoerbuchId, name: anzeige?.titel)
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
    /// Woher die laufende Musik kommt (für das Hörprotokoll), z. B. „Mix: Dein Mix“.
    @ObservationIgnored private var quelle: String?
    @ObservationIgnored private var letzterStart: String?
    @ObservationIgnored private var hoerbuchId: String?
    @ObservationIgnored private var folgeId: String?
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
        #if os(iOS)
        // Anruf, Siri oder Navigationsansage: danach weiterspielen wie Apple Music.
        beobachter.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] meldung in
            let info = meldung.userInfo
            let beginn = (info?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            let weiter = AVAudioSession.InterruptionOptions(rawValue: info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0).contains(.shouldResume)
            MainActor.assumeIsolated { self?.unterbrochen(beginn: beginn, weiter: weiter) }
        })
        #endif
        fernsteuerung()
    }

    @ObservationIgnored private var liefVorUnterbrechung = false

    private func unterbrochen(beginn: Bool, weiter: Bool) {
        if beginn {
            liefVorUnterbrechung = spielt || player.rate > 0
        } else if liefVorUnterbrechung && weiter {
            liefVorUnterbrechung = false
            player.play()
        }
    }

    // MARK: Starten

    public func spiele(_ titel: [Titel], ab start: Int = 0, quelle: String? = nil) {
        guard let client, !titel.isEmpty else { return }
        self.quelle = quelle
        beendeHoerbuch()
        istHoerbuch = false
        istRadio = false
        kapitel = []
        warteschlange = titel
        spuren = titel.map { (Offline.geteilt.datei(fuerTitel: $0.id) ?? client.streamURL($0.id), 0) }
        player.defaultRate = 1
        lade(ab: start, zeit: 0)
        player.play()
        knoepfe()
    }

    /// Internetradio: ein endloser Stream ohne Warteschlange.
    public func spiele(sender: Sender) {
        guard let url = URL(string: sender.streamUrl) else { return }
        beendeHoerbuch()
        istHoerbuch = false
        istRadio = true
        kapitel = []
        warteschlange = []
        spuren = [(url, 0)]
        anzeige = Anzeige(titel: sender.name, untertitel: "Internetradio", cover: nil, dauer: 0)
        player.defaultRate = 1
        Protokoll.geteilt.merke("start", art: "musik", quelle: "Internetradio", id: sender.id, name: sender.name)
        lade(ab: 0, zeit: 0)
        player.play()
        knoepfe()
        nowPlaying()
    }

    /// Startet ein Hörbuch an der zuletzt gehörten Stelle.
    /// Ist es geladen, spielt es von der Datei auf dem iPhone, auch ohne Verbindung zum Server.
    public func spiele(hoerbuch: Hoerbuch) async {
        await starte(id: hoerbuch.id, titel: hoerbuch.titel, autor: hoerbuch.autor, hoerbuch: hoerbuch)
    }

    /// Podcast-Folge an der zuletzt gehörten Stelle (nur vom Server, Fortschritt je Folge).
    public func spiele(folge: Folge, podcast: String, podcastTitel: String) async {
        await starte(id: podcast, titel: folge.titel, autor: podcastTitel, folge: folge.id)
    }

    private func starte(id: String, titel: String, autor: String, hoerbuch: Hoerbuch? = nil, folge: String? = nil) async {
        guard let abs = hoerbuchClient else { return }
        beendeHoerbuch()
        player.pause()
        let offline = folge == nil ? Offline.geteilt.hoerbuch(id) : nil
        if offline != nil { await Offline.geteilt.nachtragen(abs) }
        do {
            // Sitzung beim Server: für Fortschritt und Statistik. Ohne Verbindung geht es mit der Datei weiter.
            var neu: HoerbuchSitzung?
            do { neu = try await abs.starte(id, folge: folge) } catch { if offline == nil { throw error } }
            var dateien: [(url: URL, start: Double)] = []
            if let offline {
                dateien = offline.dateien.map { (Offline.pfad(offline, $0), $0.start) }
            } else if let neu {
                for s in neu.audioTracks.sorted(by: { $0.startOffset < $1.startOffset }) {
                    dateien.append((try await abs.dateiURL(s.contentUrl), s.startOffset))
                }
            }
            guard !dateien.isEmpty else { throw ServerFehler("Das Hörbuch hat keine abspielbaren Dateien.") }
            sitzung = neu?.id
            hoerbuchId = id
            folgeId = folge
            istHoerbuch = true
            istRadio = false
            warteschlange = []
            kapitel = neu?.chapters ?? offline?.kapitel ?? []
            spuren = dateien
            anzeige = Anzeige(titel: folge != nil ? titel : neu?.displayTitle ?? titel, untertitel: folge != nil ? autor : neu?.displayAuthor ?? autor,
                              cover: abs.coverURL(id), dauer: neu?.duration ?? offline?.dauer ?? 0)
            let start = neu?.currentTime ?? offline?.position ?? 0
            player.defaultRate = tempo
            Protokoll.geteilt.merke("start", art: folge != nil ? "podcast" : "hoerbuch", position: start, dauer: anzeige?.dauer,
                                    quelle: offline != nil ? "Geladen" : nil, id: folge ?? id, name: titel, urheber: autor)
            lade(ab: spuren.lastIndex { $0.start <= start } ?? 0, zeit: start)
            player.play()
            knoepfe()
            nowPlaying()
            // Was man hört, kommt automatisch aufs iPhone.
            if offline == nil, let hoerbuch, Offline.geteilt.hoerbuecherAutomatisch {
                Task { try? await Offline.geteilt.lade(hoerbuch: hoerbuch, abs) }
            }
        } catch {
            fehler = error.deutsch
        }
    }

    // MARK: Steuerung

    public func umschalten() { spielt ? player.pause() : player.play() }

    public func pause() { player.pause() }

    /// Musik: nächster Titel. Hörbuch: 30 Sekunden vor.
    public func weiter() {
        if istHoerbuch { springe(zu: min(zeit + 30, dauer)); return }
        guard index + 1 < warteschlange.count else { return }
        // Früh weitergeschaltet zählt als „übersprungen“ und wirkt auf die Mixe.
        if let titel = aktuell {
            if zeit < 30 { Hoerverlauf.geteilt.merke(titel, uebersprungen: true) }
            Protokoll.geteilt.merke("uebersprungen", titel: titel, position: zeit)
        }
        player.advanceToNextItem()
    }

    /// Musik: Anfang oder vorheriger Titel. Hörbuch: 15 Sekunden zurück.
    public func zurueck() {
        if istHoerbuch { springe(zu: max(zeit - 15, 0)); return }
        if zeit > 3 || index == 0 { springe(zu: 0) } else { lade(ab: index - 1, zeit: 0); player.play() }
    }

    public func springe(zu ziel: Double) {
        guard !spuren.isEmpty else { return }
        Protokoll.geteilt.merke("gespult", titel: aktuell, art: istHoerbuch ? "hoerbuch" : "musik", position: zeit,
                                wert: String(Int(ziel)), id: hoerbuchId, name: istHoerbuch ? anzeige?.titel : nil)
        // Hörbuch: Datei zur Stelle suchen. Musik: immer im laufenden Titel (alle beginnen bei 0).
        let neu = istHoerbuch ? (spuren.lastIndex { $0.start <= ziel } ?? 0) : spur
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

    // MARK: Warteschlange (Musik)

    /// Spielt den Titel direkt nach dem aktuellen.
    public func alsNaechstes(_ titel: [Titel]) {
        guard !istHoerbuch, !warteschlange.isEmpty else { spiele(titel); return }
        warteschlange.insert(contentsOf: titel, at: index + 1)
        neuAufbauen()
    }

    public func anhaengen(_ titel: [Titel]) {
        guard !istHoerbuch, !warteschlange.isEmpty else { spiele(titel); return }
        warteschlange.append(contentsOf: titel)
        neuAufbauen()
    }

    public func springeZu(_ stelle: Int) {
        guard !istHoerbuch, warteschlange.indices.contains(stelle) else { return }
        lade(ab: stelle, zeit: 0)
        player.play()
    }

    public func verschiebe(von: IndexSet, nach: Int) {
        guard !istHoerbuch else { return }
        // Der laufende Titel wird markiert, damit er nach dem Verschieben wiedergefunden wird.
        var markiert = warteschlange.enumerated().map { ($0.element, $0.offset == index) }
        let bewegt = von.map { markiert[$0] }
        for i in von.sorted(by: >) { markiert.remove(at: i) }
        markiert.insert(contentsOf: bewegt, at: nach - von.filter { $0 < nach }.count)
        warteschlange = markiert.map(\.0)
        index = markiert.firstIndex { $0.1 } ?? 0
        neuAufbauen()
    }

    /// Entfernt Titel; der laufende bleibt.
    public func entferne(_ stellen: IndexSet) {
        guard !istHoerbuch else { return }
        var markiert = warteschlange.enumerated().map { ($0.element, $0.offset == index) }
        for i in stellen.sorted(by: >) where !markiert[i].1 { markiert.remove(at: i) }
        warteschlange = markiert.map(\.0)
        index = markiert.firstIndex { $0.1 } ?? 0
        neuAufbauen()
    }

    /// Lässt den laufenden Titel weiterspielen und stellt alles danach neu ein.
    private func neuAufbauen() {
        guard let client else { return }
        spuren = warteschlange.map { (Offline.geteilt.datei(fuerTitel: $0.id) ?? client.streamURL($0.id), 0) }
        guard let laufend = player.currentItem else { return }
        for eintrag in player.items() where eintrag !== laufend { player.remove(eintrag) }
        stellen = [ObjectIdentifier(laufend): index]
        spur = index
        haengeAn(ab: index + 1)
    }

    /// Schlaf-Timer: nach Minuten (nil = aus).
    public func schlafen(in minuten: Int?) {
        Protokoll.geteilt.merke("schlaftimer", art: istHoerbuch ? "hoerbuch" : "musik", position: zeit,
                                wert: minuten.map(String.init) ?? "aus", id: hoerbuchId, name: anzeige?.titel)
        schlafenAmKapitelende = false
        schlafenUm = minuten.map { Date().addingTimeInterval(Double($0) * 60) }
    }

    public func schlafenAmEndeDesKapitels() {
        Protokoll.geteilt.merke("schlaftimer", art: "hoerbuch", position: zeit, wert: "kapitel", id: hoerbuchId, name: anzeige?.titel)
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
        eintragGewechselt()
        zeit = ziel
        zeitInfo()
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
        // Neue Datei beginnt vorn; sonst zeigt der Sperrbildschirm noch die Zeit der vorherigen.
        let sekunden = player.currentTime().seconds
        zeit = spuren[i].start + (sekunden.isFinite ? sekunden : 0)
        if let letzte = stellen.values.max(), letzte < i + 3, letzte + 1 < spuren.count { haengeAn(ab: letzte + 1) }
        guard !istHoerbuch else { zeitInfo(); return }
        index = i
        if let titel = aktuell {
            if letzterStart != "\(i)|\(titel.id)" {
                letzterStart = "\(i)|\(titel.id)"
                Protokoll.geteilt.merke("start", titel: titel, position: 0, quelle: quelle)
            }
            anzeige = Anzeige(titel: titel.title, untertitel: titel.artist ?? "",
                              cover: client?.coverURL(titel.coverArt, groesse: 600), dauer: Double(titel.duration ?? 0))
            if let client { Task { try? await client.scrobble(titel.id, fertig: false) } }
            if autoplay, index >= warteschlange.count - 2 { autoplayNachladen(ab: titel) }
        }
        nowPlaying()
    }

    /// Hängt ähnliche Titel an (über Last.fm), damit die Musik nicht aufhört; sonst Zufallstitel.
    private func autoplayNachladen(ab titel: Titel) {
        guard !autoplayLaeuft, let client else { return }
        autoplayLaeuft = true
        Task {
            defer { autoplayLaeuft = false }
            let schon = Set(warteschlange.map(\.id))
            let endeVorher = warteschlange.last?.id
            var neu = Mixe.bereinigt((try? await client.aehnlicheTitel(titel.id, anzahl: 40)) ?? []).filter { !schon.contains($0.id) }
            if neu.count < 5 { neu += ((try? await client.zufaelligeTitel(anzahl: 20)) ?? []).filter { !schon.contains($0.id) } }
            // Inzwischen etwas anderes gestartet? Dann nichts anhängen.
            guard !neu.isEmpty, !istHoerbuch, !istRadio, warteschlange.last?.id == endeVorher else { return }
            let anfang = warteschlange.count
            let dazu = Array(neu.shuffled().prefix(20))
            warteschlange += dazu
            spuren += dazu.map { (Offline.geteilt.datei(fuerTitel: $0.id) ?? client.streamURL($0.id), 0) }
            quelle = "Autoplay"
            // Nur anhängen, wenn der Player die bisherigen schon alle geladen hat; sonst holt sie eintragGewechselt.
            if let letzte = stellen.values.max(), letzte == anfang - 1 { haengeAn(ab: anfang) }
            if player.currentItem == nil { lade(ab: anfang, zeit: 0); player.play() }
        }
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
        if spielt && !laeuft {
            Protokoll.geteilt.merke("pause", titel: aktuell, art: istHoerbuch ? "hoerbuch" : "musik", position: zeit,
                                    id: hoerbuchId, name: istHoerbuch ? anzeige?.titel : nil)
        }
        spielt = laeuft
        if !laeuft { synchronisiere() }
        zeitInfo()
    }

    private func gehoert(_ schluessel: ObjectIdentifier) {
        guard let i = stellen.removeValue(forKey: schluessel), !istHoerbuch, let client, warteschlange.indices.contains(i) else { return }
        let titel = warteschlange[i]
        Hoerverlauf.geteilt.merke(titel, uebersprungen: false)
        Protokoll.geteilt.merke("ende", titel: titel, position: Double(titel.duration ?? 0))
        Task { try? await client.scrobble(titel.id, fertig: true) }
    }

    /// Meldet die Hörposition an Audiobookshelf (alle 15 s, beim Pausieren und am Ende).
    private func synchronisiere(schliessen: Bool = false) {
        guard istHoerbuch, let abs = hoerbuchClient else { return }
        let zeit = zeit, dauer = dauer, gehoert = gehoertSeitSync
        gehoertSeitSync = 0
        // Geladene Hörbücher merken sich die Stelle immer selbst; ohne Server-Sitzung wird sie später nachgetragen.
        // Podcast-Folgen merkt sich nur der Server (die Offline-Stelle gilt dem ganzen Eintrag).
        if let id = hoerbuchId, folgeId == nil { Offline.geteilt.merke(position: zeit, hoerbuch: id, offen: sitzung == nil) }
        guard let sitzung else { return }
        Task {
            do {
                try await abs.synchronisiere(sitzung, zeit: zeit, gehoert: gehoert, dauer: dauer, schliessen: schliessen)
            } catch {
                if let id = self.hoerbuchId, self.folgeId == nil { Offline.geteilt.merke(position: zeit, hoerbuch: id, offen: true) }
            }
        }
    }

    private func beendeHoerbuch() {
        guard istHoerbuch else { return }
        synchronisiere(schliessen: true)
        sitzung = nil
        hoerbuchId = nil
        folgeId = nil
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
            MPNowPlayingInfoPropertyIsLiveStream: istRadio,
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
