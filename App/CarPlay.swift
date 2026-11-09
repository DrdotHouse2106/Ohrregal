import CarPlay
import Kern

/// CarPlay: Tabs Start, Musik, Hörbücher und Radio. Gespielt wird über denselben Player wie auf dem iPhone,
/// „Läuft gerade“ zeigt CarPlay selbst an (über Sperrbildschirm-Infos und Fernbedienung).
final class CarPlayDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var steuerung: CPInterfaceController?

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        steuerung = interfaceController
        Task { @MainActor in Protokoll.geteilt.geraet = "CarPlay" }
        Task { @MainActor in await aufbauen() }
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        steuerung = nil
        Task { @MainActor in Protokoll.geteilt.geraet = "iPhone" }
    }

    // MARK: Aufbau

    @MainActor private func aufbauen() async {
        let start = CPListTemplate(title: "Start", sections: [])
        start.tabImage = UIImage(systemName: "house.fill")
        let musik = CPListTemplate(title: "Musik", sections: [])
        musik.tabImage = UIImage(systemName: "music.note")
        let buecher = CPListTemplate(title: "Hörbücher", sections: [])
        buecher.tabImage = UIImage(systemName: "books.vertical.fill")

        let radio = CPListTemplate(title: "Radio", sections: [])
        radio.tabImage = UIImage(systemName: "dot.radiowaves.left.and.right")

        var tabs = [start, musik]
        if geteilteSitzung.hoerbuchClient != nil { tabs.append(buecher) }
        tabs.append(radio)
        steuerung?.setRootTemplate(CPTabBarTemplate(templates: tabs), animated: false, completion: nil)

        guard let client = geteilteSitzung.client else {
            start.updateSections([CPListSection(items: [CPListItem(text: "Bitte zuerst auf dem iPhone anmelden", detailText: nil)])])
            return
        }
        await fuelleStart(start, client)
        fuelleMusik(musik, client)
        await fuelleRadio(radio, client)
        if let abs = geteilteSitzung.hoerbuchClient { await fuelleHoerbuecher(buecher, abs) }
    }

    /// Start wie bei Apple Music: Zeilen mit großen Covern zum Seitwärtswischen.
    /// Antippen eines Covers spielt ab, Antippen der Überschrift öffnet die ganze Liste.
    @MainActor private func fuelleStart(_ liste: CPListTemplate, _ client: NavidromeClient) async {
        let mixe = StartVorrat.laden()?.mixe ?? []
        let spiel = abspielen("Spiel etwas für mich", nil, bild: nil) {
            var titel = mixe.first?.titel.shuffled() ?? []
            if titel.isEmpty { titel = (try? await client.zufaelligeTitel()) ?? [] }
            geteilterPlayer.spiele(titel, quelle: "CarPlay: Spiel etwas für mich")
        }
        spiel.setImage(UIImage(systemName: "sparkles"))

        var zeilen: [CPListImageRowItem] = []
        if !mixe.isEmpty {
            zeilen.append(await bildzeile("Für dich", mixe.map { m in
                (client.coverURL(m.cover.first, groesse: 300), { geteilterPlayer.spiele(m.titel, quelle: "CarPlay: Mix: \(m.name)") })
            }))
        }
        if let abs = geteilteSitzung.hoerbuchClient {
            let hoerbuecher = (try? await abs.angefangen()) ?? []
            if !hoerbuecher.isEmpty {
                zeilen.append(await bildzeile("Hörbücher weiterhören", hoerbuecher.map { h in
                    (abs.coverURL(h.id), { await geteilterPlayer.spiele(hoerbuch: h) })
                }))
            }
        }
        async let zuletzt = client.alben("recent", anzahl: 12)
        async let neu = client.alben("newest", anzahl: 12)
        async let haeufig = client.alben("frequent", anzahl: 12)
        for (titel, alben) in [("Zuletzt gespielt", (try? await zuletzt) ?? []), ("Kürzlich hinzugefügt", (try? await neu) ?? []),
                               ("Am häufigsten gespielt", (try? await haeufig) ?? [])] where !alben.isEmpty {
            zeilen.append(await bildzeile(titel, alben.map { a in
                (client.coverURL(a.coverArt, groesse: 300), {
                    geteilterPlayer.spiele((try? await client.album(a.id))?.song ?? [], quelle: "CarPlay: \(titel)")
                })
            }, liste: alben.map { albumEintrag($0, client) }))
        }
        liste.updateSections([CPListSection(items: [spiel]), CPListSection(items: zeilen)])
    }

    /// Zeile mit Covern; die Bilder werden geladen, bevor die Zeile erscheint.
    @MainActor private func bildzeile(_ titel: String, _ eintraege: [(URL?, @MainActor () async -> Void)],
                                      liste: [CPListItem]? = nil) async -> CPListImageRowItem {
        let teil = Array(eintraege.prefix(Int(CPMaximumNumberOfGridImages)))
        var bilder = Array(repeating: UIImage(systemName: "music.note") ?? UIImage(), count: teil.count)
        await withTaskGroup(of: (Int, UIImage?).self) { gruppe in
            for (i, e) in teil.enumerated() {
                gruppe.addTask {
                    guard let url = e.0, let (daten, _) = try? await URLSession.shared.data(from: url) else { return (i, nil) }
                    return (i, UIImage(data: daten))
                }
            }
            for await (i, bild) in gruppe { if let bild { bilder[i] = bild } }
        }
        let zeile = CPListImageRowItem(text: titel, images: bilder)
        zeile.listImageRowHandler = { [weak self] _, index, fertig in
            Task { @MainActor in
                if teil.indices.contains(index) { await teil[index].1() }
                self?.zeigeWiedergabe()
                fertig()
            }
        }
        zeile.handler = { [weak self] _, fertig in
            Task { @MainActor in
                if let liste {
                    let vorlage = CPListTemplate(title: titel, sections: [CPListSection(items: Array(liste.prefix(CPListTemplate.maximumItemCount)))])
                    self?.steuerung?.pushTemplate(vorlage, animated: true, completion: nil)
                }
                fertig()
            }
        }
        return zeile
    }

    @MainActor private func fuelleRadio(_ liste: CPListTemplate, _ client: NavidromeClient) async {
        let sender = (try? await client.sender()) ?? []
        let eintraege = sender.map { s in
            let e = abspielen(s.name, nil, bild: nil) { geteilterPlayer.spiele(sender: s) }
            e.setImage(UIImage(systemName: "dot.radiowaves.left.and.right"))
            return e
        }
        liste.updateSections([CPListSection(items: eintraege.isEmpty
            ? [CPListItem(text: "Keine Sender", detailText: "Sender werden in Navidrome eingerichtet.")] : eintraege)])
    }

    @MainActor private func fuelleMusik(_ liste: CPListTemplate, _ client: NavidromeClient) {
        liste.updateSections([CPListSection(items: [
            ordner("Playlists", symbol: "music.note.list") { [self] in
                ((try? await client.playlists()) ?? []).map { p in
                    abspielen(p.name, "\(p.songCount ?? 0) Titel", bild: client.coverURL(p.coverArt, groesse: 200)) {
                        geteilterPlayer.spiele((try? await client.playlist(p.id))?.entry ?? [], quelle: "CarPlay: Playlist")
                    }
                }
            },
            ordner("Gefällt mir", symbol: "heart.fill") { [self] in
                let titel = (try? await client.favoriten())?.song ?? []
                return titel.enumerated().map { i, t in
                    abspielen(t.title, t.artist, bild: client.coverURL(t.coverArt, groesse: 200)) { geteilterPlayer.spiele(titel, ab: i) }
                }
            },
            ordner("Kürzlich hinzugefügt", symbol: "clock") { [self] in
                ((try? await client.alben("newest", anzahl: 24)) ?? []).map { albumEintrag($0, client) }
            },
            ordner("Zufällige Alben", symbol: "shuffle") { [self] in
                ((try? await client.alben("random", anzahl: 24)) ?? []).map { albumEintrag($0, client) }
            },
        ])])
    }

    @MainActor private func fuelleHoerbuecher(_ liste: CPListTemplate, _ abs: AudiobookshelfClient) async {
        let angefangen = ((try? await abs.angefangen()) ?? []).map { h in
            abspielen(h.titel, h.autor, bild: abs.coverURL(h.id)) { await geteilterPlayer.spiele(hoerbuch: h) }
        }
        var bereiche = [CPListSection(items: angefangen, header: "Weiterhören", sectionIndexTitle: nil)]
        let bibliotheken = (try? await abs.bibliotheken()) ?? []
        bereiche.append(CPListSection(items: bibliotheken.map { b in
            ordner(b.name, symbol: "books.vertical") { [self] in
                ((try? await abs.hoerbuecher(in: b.id, seite: 0)) ?? []).map { h in
                    abspielen(h.titel, h.autor, bild: abs.coverURL(h.id)) { await geteilterPlayer.spiele(hoerbuch: h) }
                }
            }
        }, header: "Bibliotheken", sectionIndexTitle: nil))
        liste.updateSections(bereiche.filter { !$0.items.isEmpty })
    }

    // MARK: Bausteine

    @MainActor private func albumEintrag(_ album: Album, _ client: NavidromeClient) -> CPListItem {
        abspielen(album.name, album.artist, bild: client.coverURL(album.coverArt, groesse: 200)) {
            geteilterPlayer.spiele((try? await client.album(album.id))?.song ?? [], quelle: "CarPlay: Album")
        }
    }

    /// Eintrag, der beim Antippen abspielt und „Läuft gerade“ öffnet.
    @MainActor private func abspielen(_ text: String, _ detail: String?, bild: URL?, aktion: @escaping @MainActor () async -> Void) -> CPListItem {
        let eintrag = CPListItem(text: text, detailText: detail)
        eintrag.handler = { [weak self] _, fertig in
            Task { @MainActor in
                await aktion()
                self?.zeigeWiedergabe()
                fertig()
            }
        }
        if let bild {
            Task {
                guard let (daten, _) = try? await URLSession.shared.data(from: bild), let b = UIImage(data: daten) else { return }
                eintrag.setImage(b)
            }
        }
        return eintrag
    }

    /// Eintrag, der eine weitere Liste öffnet.
    @MainActor private func ordner(_ text: String, symbol: String, inhalt: @escaping @MainActor () async -> [CPListItem]) -> CPListItem {
        let eintrag = CPListItem(text: text, detailText: nil, image: UIImage(systemName: symbol), accessoryImage: nil, accessoryType: .disclosureIndicator)
        eintrag.handler = { [weak self] _, fertig in
            Task { @MainActor in
                let eintraege = Array(await inhalt().prefix(CPListTemplate.maximumItemCount))
                let liste = CPListTemplate(title: text, sections: [CPListSection(items: eintraege)])
                self?.steuerung?.pushTemplate(liste, animated: true, completion: nil)
                fertig()
            }
        }
        return eintrag
    }

    @MainActor private func zeigeWiedergabe() {
        guard let steuerung, steuerung.topTemplate !== CPNowPlayingTemplate.shared else { return }
        steuerung.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
    }
}
