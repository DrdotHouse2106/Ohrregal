import Kern
import SwiftUI

struct Anmeldung: View {
    @Environment(Sitzung.self) private var sitzung
    @State private var server = UserDefaults.standard.string(forKey: "server") ?? ""
    @State private var benutzer = UserDefaults.standard.string(forKey: "benutzer") ?? ""
    @State private var passwort = ""
    @State private var laeuft = false
    @State private var fehler: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Adresse, z. B. musik.example.de", text: $server)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Benutzer", text: $benutzer)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Passwort", text: $passwort)
                        .textContentType(.password)
                } header: {
                    Text("Navidrome")
                } footer: {
                    Text("Die Zugangsdaten bleiben auf diesem iPhone. Das Passwort liegt im Schlüsselbund.")
                }
                if let fehler {
                    Section { Text(fehler).foregroundStyle(.red) }
                }
                Section {
                    Button {
                        Task { await anmelden() }
                    } label: {
                        HStack {
                            Text("Verbinden")
                            if laeuft { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(laeuft || server.isEmpty || benutzer.isEmpty || passwort.isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Farben.hintergrund)
            .navigationTitle("Willkommen")
        }
    }

    private func anmelden() async {
        laeuft = true
        defer { laeuft = false }
        do {
            try await sitzung.anmelden(server: server, benutzer: benutzer, passwort: passwort)
        } catch {
            fehler = "Verbindung fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
