import Foundation

public enum Adresse {
    /// Macht aus einer Eingabe eine Server-Adresse: ergänzt https://, entfernt / und …/app am Ende.
    /// http:// bleibt nur im Heimnetz (IP-Adresse, .local, localhost); im Internet erlaubt iOS nur https://.
    public static func aufbereiten(_ eingabe: String) -> URL? {
        var text = eingabe.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix("/app") { text.removeLast(4) }
        guard var teile = URLComponents(string: text), let host = teile.host, !host.isEmpty else { return nil }
        if teile.scheme?.lowercased() == "http", !imHeimnetz(host) { teile.scheme = "https" }
        return teile.url
    }

    static func imHeimnetz(_ host: String) -> Bool {
        host == "localhost" || host.hasSuffix(".local") || host.allSatisfy { $0.isNumber || $0 == "." } || host.contains(":")
    }
}

extension Error {
    /// Verständliche deutsche Meldung mit Lösungsvorschlag für Verbindungsfehler.
    public var deutsch: String {
        if let fehler = self as? ServerFehler { return fehler.errorDescription ?? "Unbekannter Fehler." }
        guard let fehler = self as? URLError else { return localizedDescription }
        switch fehler.code {
        case .appTransportSecurityRequiresSecureConnection:
            return "Die Adresse beginnt mit http://. Im Internet ist nur eine sichere Verbindung erlaubt: bitte https:// verwenden."
        case .cannotFindHost, .dnsLookupFailed:
            return "Der Server wurde nicht gefunden. Bitte die Adresse auf Tippfehler prüfen."
        case .cannotConnectToHost:
            return "Der Server antwortet nicht. Läuft er, und ist die Adresse (inklusive Port) richtig?"
        case .timedOut:
            return "Der Server antwortet zu langsam. Bitte später noch einmal versuchen."
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return "Keine Internetverbindung."
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .secureConnectionFailed, .clientCertificateRejected:
            return "Die sichere Verbindung ist fehlgeschlagen: Das Zertifikat des Servers ist ungültig oder abgelaufen."
        case .badURL, .unsupportedURL:
            return "Die Adresse ist ungültig."
        case .userAuthenticationRequired:
            return "Der Server verlangt eine zusätzliche Anmeldung (z. B. über den Reverse-Proxy)."
        case .cancelled:
            return "Abgebrochen."
        default:
            return "Verbindungsfehler (\(fehler.code.rawValue)). Bitte Adresse und Internetverbindung prüfen."
        }
    }
}
