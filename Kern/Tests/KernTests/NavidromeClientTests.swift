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

    func testFehlerWirdGemeldet() {
        let json = #"{"subsonic-response":{"status":"failed","error":{"code":40,"message":"Wrong username or password"}}}"#
        XCTAssertThrowsError(try NavidromeClient.lies(Data(json.utf8))) { fehler in
            XCTAssertEqual(fehler.localizedDescription, "Wrong username or password")
        }
    }
}
