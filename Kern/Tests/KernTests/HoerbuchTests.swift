import XCTest
@testable import Kern

final class HoerbuchTests: XCTestCase {
    func testSitzungLesen() throws {
        let json = """
        {"id":"play_1","libraryItemId":"li_1","currentTime":125.5,"duration":3600,"displayTitle":"Beispielbuch","displayAuthor":"Erika Muster",
         "chapters":[{"id":0,"start":0,"end":1800,"title":"Kapitel 1"},{"id":1,"start":1800,"end":3600,"title":"Kapitel 2"}],
         "audioTracks":[{"index":1,"startOffset":0,"duration":1800,"contentUrl":"/api/items/li_1/file/1"},
                        {"index":2,"startOffset":1800,"duration":1800,"contentUrl":"/api/items/li_1/file/2"}]}
        """
        let s = try JSONDecoder().decode(HoerbuchSitzung.self, from: Data(json.utf8))
        XCTAssertEqual(s.audioTracks.count, 2)
        XCTAssertEqual(s.chapters?.last?.title, "Kapitel 2")
    }

    /// Fehlende und mit null gefüllte Felder dürfen das Lesen nicht verhindern (siehe Dienst/API.md).
    func testWunschTolerant() throws {
        let json = """
        {"id":"w_23e05949","asin":null,"titel":"Beispielbuch","autor":"Erika Muster","sprecher":null,"reihe":null,"teil":null,
         "laufzeitMin":null,"sprache":"de","coverUrl":null,"status":"da","absItemId":"li_1","erstellt":"2026-11-08T13:11:36+00:00",
         "aktualisiert":"2026-11-08T13:14:56+00:00","versuche":1}
        """
        let w = try JSONDecoder().decode(Wunsch.self, from: Data(json.utf8))
        XCTAssertEqual(w.statusText, "ist da")
        XCTAssertNil(w.hinweis)
    }

    func testTrefferMitTextDauer() throws {
        let json = #"[{"title":"Beispielbuch","author":"Erika Muster","asin":"B000TEST00","duration":"612","series":[{"series":"Beispielreihe","sequence":"3"}]},{"title":"Ohne alles"}]"#
        let t = try JSONDecoder().decode([BuchTreffer].self, from: Data(json.utf8))
        XCTAssertEqual(t.first?.duration, 612)
        XCTAssertEqual(t.first?.series?.first?.sequence, "3")
        XCTAssertNil(t.last?.asin)
    }
}

@MainActor
final class HoerverlaufTests: XCTestCase {
    private func titel(_ id: String, kuenstler: String) -> Titel {
        try! JSONDecoder().decode(Titel.self, from: Data(#"{"id":"\#(id)","title":"T\#(id)","artist":"\#(kuenstler)","artistId":"ar-\#(kuenstler)"}"#.utf8))
    }

    func testTopKuenstlerUndUnbeliebt() {
        let verlauf = Hoerverlauf(datei: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        for _ in 0..<3 { verlauf.merke(titel("1", kuenstler: "A"), uebersprungen: false) }
        verlauf.merke(titel("2", kuenstler: "B"), uebersprungen: false)
        verlauf.merke(titel("3", kuenstler: "C"), uebersprungen: true)
        verlauf.merke(titel("3", kuenstler: "C"), uebersprungen: true)
        XCTAssertEqual(verlauf.topKuenstler().map(\.id), ["ar-A", "ar-B"])
        XCTAssertEqual(verlauf.unbeliebt(), ["3"])
        verlauf.merke(titel("3", kuenstler: "C"), uebersprungen: false)
        XCTAssertTrue(verlauf.unbeliebt().isEmpty)
    }
}
