import SwiftUI
import SharedTypes
import AuthKit

@main
struct TealeCompanionApp: App {
    @State private var appState = CompanionAppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if let authManager = appState.authManager, authManager.authState.canUseApp {
                    TabView {
                        CompanionChatView(appState: appState)
                            .tabItem {
                                Label("Chat", systemImage: "bubble.left.and.bubble.right")
                            }

                        NavigationStack {
                            LocalModelsView()
                        }
                        .environment(appState)
                        .tabItem {
                            Label("Models", systemImage: "cpu")
                        }

                        NetworkView(appState: appState)
                            .tabItem {
                                Label("Network", systemImage: "network")
                            }

                        CompanionWalletView(appState: appState)
                            .tabItem {
                                Label("Wallet", systemImage: "creditcard")
                            }

                        if authManager.authState.isAuthenticated {
                            DevicesView(authManager: authManager)
                                .tabItem {
                                    Label("Devices", systemImage: "laptopcomputer.and.iphone")
                                }
                        }

                        CompanionSettingsView(appState: appState)
                            .tabItem {
                                Label("Settings", systemImage: "gear")
                            }
                    }
                } else if let authManager = appState.authManager {
                    LoginView(authManager: authManager)
                } else {
                    ProgressView("Loading...")
                }
            }
            .task {
                await appState.initialize()
            }
            .onOpenURL { url in
                if let authManager = appState.authManager {
                    Task { await authManager.handleOAuthCallback(url: url) }
                }
            }
        }
    }
}
