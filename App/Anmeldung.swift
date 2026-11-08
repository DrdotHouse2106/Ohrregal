import Kern
import SwiftUI

/// Zugänge zu allen Diensten. Wird beim ersten Start und später über „Zugänge“ geöffnet.
/// Alles bleibt bei Updates erhalten: Adressen in UserDefaults, Passwörter und Tokens im Schlüsselbund.
struct Anmeldung: View {
    @Environment(Sitzung.self) private var sitzung
    @Environment(\.dismiss) private var schliessen
    @State private var z = Zugaenge.geladen()
    @State private var laeuft = false
    @State private var fehler: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Feld("Adresse, z. B. musik.example.de", text: $z.server)
                    Feld("Benutzer", text: $z.benutzer)
                    SecureField("Passwort", text: $z.passwort)
                } header: {
                    Text("Navidrome (Musik)")
                }
                Section {
                    Feld("Adresse, z. B. hoerbuch.example.de", text: $z.absServer)
                    Feld("Benutzer", text: $z.absBenutzer)
                    SecureField("Passwort", text: $z.absPasswort)
                } header: {
                    Text("Audiobookshelf (Hörbücher)")
                } footer: {
                    Text("Optional. Für Hörbücher und Hörbuch-Wünsche, sobald sie in Ohrregal da sind. Die Zugangsdaten bleiben auf diesem iPhone, Passwörter liegen im Schlüsselbund.")
                }
                if let fehler {
                    Section { Text(fehler).foregroundStyle(.red) }
                }
                Section {
                    Button {
                        Task { await speichern() }
                    } label: {
                        HStack {
                            Text("Verbinden und speichern")
                            if laeuft { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(laeuft || z.server.isEmpty || z.benutzer.isEmpty || z.passwort.isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Farben.hintergrund)
            .navigationTitle(sitzung.client == nil ? "Willkommen" : "Zugänge")
        }
    }

    private func speichern() async {
        laeuft = true
        defer { laeuft = false }
        z.speichereZusatz()
        sitzung.ladeHoerbuch()
        do {
            try await sitzung.anmelden(server: z.server, benutzer: z.benutzer, passwort: z.passwort)
        } catch {
            fehler = "Anmeldung bei Navidrome fehlgeschlagen: \(error.localizedDescription)"
            return
        }
        do {
            try await sitzung.hoerbuchClient?.anmelden()
            await Benachrichtigungen.geraetMelden()
            schliessen()
        } catch {
            fehler = "Navidrome ist verbunden, aber Audiobookshelf nicht: \(error.localizedDescription)"
        }
    }
}

private struct Feld: View {
    let titel: String
    @Binding var text: String

    init(_ titel: String, text: Binding<String>) {
        self.titel = titel
        _text = text
    }

    var body: some View {
        TextField(titel, text: $text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }
}

/// Alle Zugänge; Navidrome speichert `Sitzung.anmelden`, den Rest `speichereZusatz`.
struct Zugaenge {
    var server = "", benutzer = "", passwort = ""
    var absServer = "", absBenutzer = "", absPasswort = ""

    static func geladen() -> Zugaenge {
        let d = UserDefaults.standard
        return Zugaenge(
            server: d.string(forKey: "server") ?? "", benutzer: d.string(forKey: "benutzer") ?? "",
            passwort: Schluesselbund.lies("navidrome") ?? "",
            absServer: d.string(forKey: "absServer") ?? "", absBenutzer: d.string(forKey: "absBenutzer") ?? "",
            absPasswort: Schluesselbund.lies("audiobookshelf") ?? "")
    }

    func speichereZusatz() {
        let d = UserDefaults.standard
        d.set(absServer.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "absServer")
        d.set(absBenutzer, forKey: "absBenutzer")
        if absPasswort.isEmpty { Schluesselbund.loesche("audiobookshelf") } else { Schluesselbund.speichere(absPasswort, fuer: "audiobookshelf") }
        // Hörbuch-Wünsche: Adresse = Audiobookshelf-Adresse + "/wunsch-api", Anmeldung mit dem Audiobookshelf-Token.
        d.removeObject(forKey: "wunschServer")
        Schluesselbund.loesche("hoerbuchwunsch")
    }
}
