import Foundation
import Security

/// Speichert Passwörter und Schlüssel im Schlüsselbund.
public enum Schluesselbund {
    private static func anfrage(_ konto: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Bundle.main.bundleIdentifier ?? "Ohrregal",
         kSecAttrAccount as String: konto]
    }

    public static func speichere(_ wert: String, fuer konto: String) {
        loesche(konto)
        var neu = anfrage(konto)
        neu[kSecValueData as String] = Data(wert.utf8)
        neu[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(neu as CFDictionary, nil)
    }

    public static func lies(_ konto: String) -> String? {
        var frage = anfrage(konto)
        frage[kSecReturnData as String] = true
        frage[kSecMatchLimit as String] = kSecMatchLimitOne
        var ergebnis: CFTypeRef?
        guard SecItemCopyMatching(frage as CFDictionary, &ergebnis) == errSecSuccess, let daten = ergebnis as? Data else { return nil }
        return String(data: daten, encoding: .utf8)
    }

    public static func loesche(_ konto: String) {
        SecItemDelete(anfrage(konto) as CFDictionary)
    }
}
