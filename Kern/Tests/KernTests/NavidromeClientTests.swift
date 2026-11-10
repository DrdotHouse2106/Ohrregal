import XCTest
@testable import Kern

final class NavidromeClientTests: XCTestCase {
    /// Beispiel aus der Subsonic-Dokumentation.
    func testToken() {
        XCTAssertEqual(NavidromeClient.token(passwort: "sesame", salt: "c19b2d"), "26719a1196d2a940705a59634eb18eab")
    }

    func testAdresse() {
        let client = NavidromeClient(server: URL(string: "https://musik.example")!, benutzer: "ich", passwort: "sesame")
        let url = client.adresse("getAlbumList2", ["type": "frequent"], salt: "c19b2d").absoluteString
        XCTAssertTrue(url.hasPrefix("https://musik.example/rest/getAlbumList2?"))
        XCTAssertTrue(url.contains("t=26719a1196d2a940705a59634eb18eab"))
        XCTAssertTrue(url.contains("type=frequent"))
        XCTAssertTrue(url.contains("u=ich"))
        XCTAssertFalse(url.contains("sesame"))
    }

    /// Cover-Adressen bleiben gleich, damit sie zwischengespeichert werden.
    func testCoverAdresseBleibtGleich() {
        let client = NavidromeClient(server: URL(string: "https://musik.example")!, benutzer: "ich", passwort: "x")
        XCTAssertEqual(client.coverURL("al-1", groesse: 300), client.coverURL("al-1", groesse: 300))
    }

    func testAlbenLesen() throws {
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","albumList2":{"album":[
          {"id":"al-1","name":"4630 Bochum","artist":"Herbert Grönemeyer","artistId":"ar-1","coverArt":"al-1","year":1984,"songCount":10}
        ]}}}
        """
        let alben = try NavidromeClient.lies(Data(json.utf8)).albumList2?.album
        XCTAssertEqual(alben?.first?.name, "4630 Bochum")
        XCTAssertEqual(alben?.first?.year, 1984)
    }

    func testMehrfachParameter() {
        let client = NavidromeClient(server: URL(string: "https://musik.example")!, benutzer: "ich", passwort: "x")
        let url = client.adresse("updatePlaylist", ["playlistId": "p1"], mehrfach: [("songIdToAdd", "a"), ("songIdToAdd", "b")]).absoluteString
        XCTAssertTrue(url.contains("songIdToAdd=a&songIdToAdd=b"))
    }

    func testSongtext() throws {
        let json = #"{"subsonic-response":{"status":"ok","lyricsList":{"structuredLyrics":[{"synced":true,"line":[{"start":1500,"value":"Erste Zeile"},{"start":4000,"value":"Zweite"}]}]}}}"#
        let text = try NavidromeClient.lies(Data(json.utf8)).lyricsList?.structuredLyrics?.first?.line
        XCTAssertEqual(text?.first?.value, "Erste Zeile")
        XCTAssertEqual(text?.last?.start, 4000)
    }

    func testFehlerWirdGemeldet() {
        let json = #"{"subsonic-response":{"status":"failed","error":{"code":40,"message":"Wrong username or password"}}}"#
        XCTAssertThrowsError(try NavidromeClient.lies(Data(json.utf8))) { fehler in
            XCTAssertEqual(fehler.localizedDescription, "Benutzername oder Passwort falsch.")
        }
    }
}

final class MusikwunschTests: XCTestCase {
    func testAlbumTolerant() throws {
        let json = #"{"alben":[{"mbid":"m1","titel":"Beispielalbum","kuenstler":"Beispielband","jahr":2003,"typ":"Album","status":"fehlt"},{"mbid":"m2","titel":"Single"}]}"#
        struct Liste: Decodable { let alben: [LidarrAlbum] }
        let alben = try JSONDecoder().decode(Liste.self, from: Data(json.utf8)).alben
        XCTAssertEqual(alben.first?.jahr, "2003")
        XCTAssertEqual(alben.last?.status, "fehlt")
        XCTAssertEqual(alben.first?.statusText, "Fehlt")
    }
}

final class MusikordnerTests: XCTestCase {
    func testIdAlsZahlOderText() throws {
        let json = #"{"subsonic-response":{"status":"ok","musicFolders":{"musicFolder":[{"id":1,"name":"Musik"},{"id":"2","name":"Youtube Musik"}]}}}"#
        let ordner = try NavidromeClient.lies(Data(json.utf8)).musicFolders?.musicFolder
        XCTAssertEqual(ordner?.map(\.id), ["1", "2"])
    }
}

final class AdresseTests: XCTestCase {
    func testAufbereiten() {
        XCTAssertEqual(Adresse.aufbereiten("musik.example.de")?.absoluteString, "https://musik.example.de")
        XCTAssertEqual(Adresse.aufbereiten("http://musik.example.de/app/")?.absoluteString, "https://musik.example.de")
        XCTAssertEqual(Adresse.aufbereiten("http://192.168.1.10:4533")?.absoluteString, "http://192.168.1.10:4533")
        XCTAssertEqual(Adresse.aufbereiten("http://nas.local:13378")?.absoluteString, "http://nas.local:13378")
        XCTAssertNil(Adresse.aufbereiten(""))
    }

    func testDeutscheMeldung() {
        XCTAssertTrue(URLError(.appTransportSecurityRequiresSecureConnection).deutsch.contains("https://"))
        XCTAssertEqual(ServerFehler("Benutzername oder Passwort falsch.").deutsch, "Benutzername oder Passwort falsch.")
    }
}

final class UnscharfTests: XCTestCase {
    func testTippfehlerUndUmlaute() {
        XCTAssertGreaterThan(Unscharf.aehnlichkeit("Grönemeier", "Herbert Grönemeyer"), 0.7)
        XCTAssertGreaterThan(Unscharf.aehnlichkeit("groenemeyer", "Herbert Grönemeyer"), 0.9)
        XCTAssertGreaterThan(Unscharf.aehnlichkeit("fitzk", "Sebastian Fitzek"), 0.7)
        XCTAssertLessThan(Unscharf.aehnlichkeit("Metallica", "Herbert Grönemeyer"), 0.5)
    }
}
