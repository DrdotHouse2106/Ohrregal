import Kern
import SwiftUI

extension Sitzung {
    /// Wunsch-Dienst mit Navidrome-Anmeldung; erreichbar unter derselben Adresse wie die Hörbuch-Wünsche.
    var musikwunsch: MusikwunschClient? {
        guard let client else { return nil }
        let basis = (hoerbuchClient?.server ?? client.server).appending(path: "wunsch-api")
        return MusikwunschClient(navidrome: client, basis: basis)
    }
}

/// Knopf bzw. Stand eines Lidarr-Albums; „Wünschen“ kann bei neuen Künstlern bis zu einer Minute dauern.
struct AlbumWunschKnopf: View {
    @Environment(Sitzung.self) private var sitzung
    @State var album: LidarrAlbum
    @State private var laeuft = false
    @State private var fehler: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if laeuft {
                ProgressView()
            } else if album.status == "fehlt" {
                Button("Wünschen") { Task { await wuenschen() } }.buttonStyle(.bordered)
            } else {
                Label(album.statusText, systemImage: album.status == "da" ? "checkmark.circle.fill" : "clock")
                    .font(.caption).foregroundStyle(album.status == "da" ? Farben.textGedaempft : Farben.blau)
            }
            if let fehler { Text(fehler).font(.caption2).foregroundStyle(.red).lineLimit(2) }
        }
    }

    private func wuenschen() async {
        guard let dienst = sitzung.musikwunsch else { return }
        laeuft = true
        defer { laeuft = false }
        do {
            album.status = try await dienst.wuensche(album) == .schonVorhanden ? "da" : "gewuenscht"
            await Benachrichtigungen.erlaubnisHolen()
        } catch {
            fehler = error.localizedDescription
        }
    }
}

struct LidarrAlbumZeile: View {
    let album: LidarrAlbum

    var body: some View {
        HStack(spacing: 12) {
            Cover(url: album.cover.flatMap(URL.init(string:)), groesse: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.titel).lineLimit(2)
                Text([album.kuenstler, album.typ == "Single" ? "Single" : nil, album.erscheint ?? album.jahr]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Farben.textGedaempft).lineLimit(1)
            }
            Spacer()
            AlbumWunschKnopf(album: album)
        }
    }
}

/// „Fehlt noch“ auf der Künstlerseite, dazu „Folgen“ (nur neue Alben).
struct FehltNoch: View {
    @Environment(Sitzung.self) private var sitzung
    let name: String
    /// Titel der Alben, die schon in Navidrome liegen.
    let vorhanden: Set<String>
    @State private var info: LidarrKuenstler?
    @State private var alben: [LidarrAlbum] = []
    @State private var folgenLaeuft = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let info, let mbid = info.mbid {
                Button {
                    Task { await folgen(mbid, an: info.folgt != true) }
                } label: {
                    if folgenLaeuft { ProgressView() } else {
                        Label(info.folgt == true ? "Du folgst · neue Alben kommen automatisch" : "Folgen · neue Alben automatisch laden",
                              systemImage: info.folgt == true ? "bell.fill" : "bell")
                    }
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
            }
            if !alben.isEmpty {
                Text("Fehlt noch").font(.title2.bold()).padding(.horizontal)
                VStack(spacing: 10) {
                    ForEach(alben) { LidarrAlbumZeile(album: $0) }
                }
                .padding(.horizontal)
            }
        }
        .task {
            guard info == nil, let dienst = sitzung.musikwunsch,
                  let seite = try? await dienst.kuenstler(name) else { return }
            info = seite.kuenstler
            let schon = Set(vorhanden.map { $0.lowercased() })
            alben = seite.alben.filter { $0.status != "da" && !schon.contains($0.titel.lowercased()) }
        }
    }

    private func folgen(_ mbid: String, an: Bool) async {
        guard let dienst = sitzung.musikwunsch else { return }
        folgenLaeuft = true
        defer { folgenLaeuft = false }
        if (try? await dienst.folgen(mbid, name: name, an: an)) != nil { info?.folgt = an }
    }
}

/// Musik wünschen: Suche bei Lidarr, Neuerscheinungen deiner Künstler, eigene Wünsche.
struct MusikWunschView: View {
    @Environment(Sitzung.self) private var sitzung
    @State var text = ""
    @State private var treffer: [LidarrAlbum]?
    @State private var neu: [LidarrAlbum] = []
    @State private var wuensche: [MusikWunsch] = []
    @State private var sucht = false
    @State private var meldung: String?

    var body: some View {
        List {
            if let meldung { Section { Text(meldung).font(.callout) } }
            if let treffer {
                Section("Bei Lidarr") {
                    if treffer.isEmpty { Text("Bei Lidarr nicht gefunden.").foregroundStyle(Farben.textGedaempft) }
                    ForEach(treffer) { LidarrAlbumZeile(album: $0) }
                }
            }
            Section("Meine Musikwünsche") {
                if wuensche.isEmpty { Text("Noch keine Wünsche.").foregroundStyle(Farben.textGedaempft) }
                ForEach(wuensche) { w in
                    Group {
                        if w.status == "da" {
                            NavigationLink(value: Ziel.albumFinden(w.titel, w.kuenstler ?? "")) { zeile(w) }
                        } else {
                            zeile(w)
                        }
                    }
                    .swipeActions {
                        Button("Entfernen", role: .destructive) {
                            Task {
                                try? await sitzung.musikwunsch?.zurueckziehen(w.id)
                                await liste()
                            }
                        }
                    }
                }
            }
            if !neu.isEmpty {
                Section("Neuerscheinungen deiner Künstler") {
                    ForEach(neu.prefix(30)) { LidarrAlbumZeile(album: $0) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Farben.hintergrund)
        .safeAreaInset(edge: .top) {
            Suchfeld(prompt: "Album oder Künstler bei Lidarr suchen", text: $text, laeuft: sucht) { Task { await suchen() } }
        }
        .navigationTitle("Musik wünschen")
        .task {
            if !text.isEmpty, treffer == nil { await suchen() }
            neu = (try? await sitzung.musikwunsch?.neuerscheinungen()) ?? []
            while !Task.isCancelled {
                await liste()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private func zeile(_ w: MusikWunsch) -> some View {
        HStack(spacing: 12) {
            Cover(url: w.cover.flatMap(URL.init(string:)), groesse: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(w.titel).lineLimit(1)
                Text([w.kuenstler, w.statusText].compactMap { $0 }.joined(separator: " · ")).font(.caption)
                    .foregroundStyle(w.status == "da" ? Farben.blau : w.status == "fehler" ? .red : Farben.textGedaempft)
                if let hinweis = w.hinweis { Text(hinweis).font(.caption2).foregroundStyle(Farben.textGedaempft) }
            }
        }
    }

    private func suchen() async {
        guard let dienst = sitzung.musikwunsch, !text.isEmpty else { return }
        sucht = true
        defer { sucht = false }
        do {
            treffer = try await dienst.suche(text)
            meldung = nil
        } catch {
            meldung = "Suche fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func liste() async {
        guard let dienst = sitzung.musikwunsch else { return }
        do {
            wuensche = try await dienst.wuensche()
        } catch {
            meldung = "Wunsch-Dienst nicht erreichbar: \(error.localizedDescription)"
        }
    }
}

/// Öffnet ein gewünschtes Album, sobald es in Navidrome liegt (Suche nach Titel und Künstler).
struct AlbumFinden: View {
    @Environment(\.client) private var client
    let titel: String
    let kuenstler: String
    @State private var album: Album?
    @State private var gesucht = false

    var body: some View {
        Group {
            if let album {
                AlbumView(album: album)
            } else if gesucht {
                ContentUnavailableView("Noch nicht in Navidrome", systemImage: "music.note",
                                       description: Text("Navidrome hat „\(titel)“ noch nicht eingelesen. Bitte etwas später noch einmal versuchen."))
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Farben.hintergrund)
        .task {
            let alben = (try? await client.suche("\(titel)"))?.album ?? []
            album = alben.first { $0.name.lowercased() == titel.lowercased() && ($0.artist ?? "").lowercased() == kuenstler.lowercased() }
                ?? alben.first { $0.name.lowercased() == titel.lowercased() }
            gesucht = true
        }
    }
}
