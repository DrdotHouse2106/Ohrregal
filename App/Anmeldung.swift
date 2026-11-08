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
                    Text("Optional. Wird genutzt, sobald die Hörbücher in Ohrregal da sind.")
                }
                Section {
                    Feld("Adresse, z. B. http://server:8097", text: $z.wunschServer)
                    SecureField("Token", text: $z.wunschToken)
                } header: {
                    Text("Hörbuch-Wünsche")
                } footer: {
                    Text("Optional. Funktioniert nur zu Hause oder über VPN. Die Zugangsdaten bleiben auf diesem iPhone, Passwörter und Token liegen im Schlüsselbund.")
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
        do {
            try await sitzung.anmelden(server: z.server, benutzer: z.benutzer, passwort: z.passwort)
            schliessen()
        } catch {
            fehler = "Navidrome nicht erreichbar: \(error.localizedDescription)"
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
    var wunschServer = "", wunschToken = ""

    static func geladen() -> Zugaenge {
        let d = UserDefaults.standard
        return Zugaenge(
            server: d.string(forKey: "server") ?? "", benutzer: d.string(forKey: "benutzer") ?? "",
            passwort: Schluesselbund.lies("navidrome") ?? "",
            absServer: d.string(forKey: "absServer") ?? "", absBenutzer: d.string(forKey: "absBenutzer") ?? "",
            absPasswort: Schluesselbund.lies("audiobookshelf") ?? "",
            wunschServer: d.string(forKey: "wunschServer") ?? "", wunschToken: Schluesselbund.lies("hoerbuchwunsch") ?? "")
    }

    func speichereZusatz() {
        let d = UserDefaults.standard
        d.set(absServer.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "absServer")
        d.set(absBenutzer, forKey: "absBenutzer")
        d.set(wunschServer.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "wunschServer")
        for (wert, konto) in [(absPasswort, "audiobookshelf"), (wunschToken, "hoerbuchwunsch")] {
            if wert.isEmpty { Schluesselbund.loesche(konto) } else { Schluesselbund.speichere(wert, fuer: konto) }
        }
    }
}
