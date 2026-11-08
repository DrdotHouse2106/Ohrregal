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
}
