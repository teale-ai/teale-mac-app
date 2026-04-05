import SwiftUI
import ServiceManagement
import SharedTypes
import ClusterKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var launchAtLogin = false
    @State private var maxStorage: Double = 50.0
    @State private var apiPort: String = "11435"
    @State private var clusterPasscode: String = ""

    var body: some View {
        @Bindable var state = appState

        Form {
            // General
            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            // LAN Cluster
            Section("LAN Cluster") {
                Toggle("Enable LAN Discovery", isOn: $state.clusterEnabled)

                if appState.clusterEnabled {
                    HStack {
                        Text("Cluster Passcode:")
                        SecureField("Optional", text: $clusterPasscode)
                            .frame(width: 150)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: clusterPasscode) { _, newValue in
                                appState.clusterManager.passcode = newValue.isEmpty ? nil : newValue
                            }
                    }

                    let peerCount = appState.clusterManager.clusterState.connectedPeerCount
                    HStack {
                        Circle()
                            .fill(peerCount > 0 ? .green : .orange)
                            .frame(width: 8, height: 8)
                        Text(peerCount > 0 ? "\(peerCount) peer(s) connected" : "Searching for peers...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Storage
            Section("Model Storage") {
                VStack(alignment: .leading) {
                    Text("Maximum storage: \(Int(maxStorage)) GB")
                    Slider(value: $maxStorage, in: 5...200, step: 5)
                }
            }

            // API Server
            Section("Local API Server") {
                HStack {
                    Text("Port:")
                    TextField("Port", text: $apiPort)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }

                if appState.isServerRunning {
                    HStack {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Running at http://localhost:\(appState.serverPort)/v1")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Compatible with any OpenAI API client")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Hardware Info
            Section("Hardware") {
                LabeledContent("Chip", value: appState.hardware.chipName)
                LabeledContent("RAM", value: "\(Int(appState.hardware.totalRAMGB)) GB")
                LabeledContent("GPU Cores", value: "\(appState.hardware.gpuCoreCount)")
                LabeledContent("Memory Bandwidth", value: String(format: "%.0f GB/s", appState.hardware.memoryBandwidthGBs))
                LabeledContent("Device Tier", value: tierDescription)
            }

            // About
            Section("About") {
                LabeledContent("Version", value: "0.1.0")
                LabeledContent("Engine", value: "MLX")
                Link("Source Code", destination: URL(string: "https://github.com/inference-pool")!)
            }

            // Quit
            Section {
                Button("Quit Inference Pool", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            maxStorage = appState.maxStorageGB
            apiPort = String(appState.serverPort)
        }
    }

    private var tierDescription: String {
        switch appState.hardware.tier {
        case .tier1: return "Tier 1 — Desktop (backbone)"
        case .tier2: return "Tier 2 — Laptop"
        case .tier3: return "Tier 3 — Tablet"
        case .tier4: return "Tier 4 — Mobile"
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silently fail — user may not have approved
            launchAtLogin = !enabled
        }
    }
}
