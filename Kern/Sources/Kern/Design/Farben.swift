import SwiftUI

/// Farben im Quallenkino-Stil.
public enum Farben {
    public static let hintergrund = Color(hex: 0x0B0E14)
    public static let flaeche = Color(hex: 0x161B24)
    public static let flaecheHervorgehoben = Color(hex: 0x1F2633)
    public static let blau = Color(hex: 0x2E96E0)
    public static let violett = Color(hex: 0x7F76D6)
    public static let text = Color(hex: 0xE8EAF0)
    public static let textGedaempft = Color(hex: 0xA9B1C2)

    /// Verlauf Blau → Violett, z. B. für Fortschritt und „Spiel etwas für mich“.
    public static let verlauf = LinearGradient(colors: [blau, violett], startPoint: .leading, endPoint: .trailing)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
