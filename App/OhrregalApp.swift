import Kern
import SwiftUI

@main
struct OhrregalApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                Platzhalter(titel: "Start").tabItem { Label("Start", systemImage: "house.fill") }
                Platzhalter(titel: "Musik").tabItem { Label("Musik", systemImage: "music.note") }
                Platzhalter(titel: "Hörbücher").tabItem { Label("Hörbücher", systemImage: "books.vertical.fill") }
                Platzhalter(titel: "Suchen").tabItem { Label("Suchen", systemImage: "magnifyingglass") }
            }
            .tint(Farben.blau)
            .preferredColorScheme(.dark)
        }
    }
}

private struct Platzhalter: View {
    let titel: String

    var body: some View {
        NavigationStack {
            Text("Kommt bald")
                .foregroundStyle(Farben.textGedaempft)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Farben.hintergrund)
                .navigationTitle(titel)
        }
    }
}
