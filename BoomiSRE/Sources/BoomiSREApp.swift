import SwiftUI

@main
struct BoomiSREApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1000, minHeight: 700)
                .onAppear {
                    appState.checkAllServices()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
    }
}
