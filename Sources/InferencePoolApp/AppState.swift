import Foundation
import SharedTypes
import HardwareProfile
import InferenceEngine
import ModelManager
import MLXInference
import LocalAPI
import ClusterKit

// MARK: - App State

@MainActor
@Observable
public final class AppState {
    // Hardware
    public let hardware: HardwareCapability
    public let throttler: AdaptiveThrottler

    // Engine
    public let engine: InferenceEngineManager

    // Local inference provider
    private let localProvider: MLXProvider

    // Models
    public let modelManager: ModelManagerService

    // Cluster
    public let clusterManager: ClusterManager
    public var clusterEnabled: Bool = false {
        didSet { toggleCluster() }
    }

    // Server
    public var serverPort: Int = 11435
    public var isServerRunning: Bool = false

    // UI State
    public var selectedModel: ModelDescriptor?
    public var engineStatus: EngineStatus = .idle
    public var currentView: AppView = .dashboard

    // Settings
    public var launchAtLogin: Bool = false
    public var maxStorageGB: Double = 50.0

    public init() {
        let detector = HardwareDetector()
        let hw = detector.detect()
        self.hardware = hw
        self.throttler = AdaptiveThrottler()

        let mlxProvider = MLXProvider()
        self.localProvider = mlxProvider
        self.engine = InferenceEngineManager(provider: mlxProvider, throttler: throttler)
        self.modelManager = ModelManagerService(hardware: hw, maxStorageGB: 50.0)

        let hostname = ProcessInfo.processInfo.hostName
        let deviceInfo = DeviceInfo(name: hostname, hardware: hw)
        self.clusterManager = ClusterManager(localDeviceInfo: deviceInfo)
    }

    // MARK: - Actions

    public func loadModel(_ descriptor: ModelDescriptor) async {
        do {
            selectedModel = descriptor
            engineStatus = .loadingModel(descriptor)
            try await engine.loadModel(descriptor)
            engineStatus = .ready(descriptor)
        } catch {
            engineStatus = .error(error.localizedDescription)
        }
    }

    public func unloadModel() async {
        await engine.unloadModel()
        selectedModel = nil
        engineStatus = .idle
    }

    public func startServer() async {
        guard !isServerRunning else { return }
        isServerRunning = true
        let server = LocalHTTPServer(engine: engine, port: serverPort)
        Task.detached {
            try? await server.start()
        }
    }

    public func refreshStatus() async {
        engineStatus = await engine.status
    }

    // MARK: - Cluster

    private func toggleCluster() {
        if clusterEnabled {
            enableCluster()
        } else {
            disableCluster()
        }
    }

    private func enableCluster() {
        let clusterProvider = ClusterProvider(localProvider: localProvider, clusterManager: clusterManager)
        Task {
            await engine.setProvider(clusterProvider)
        }
        clusterManager.enable()
    }

    private func disableCluster() {
        clusterManager.disable()
        Task {
            await engine.setProvider(localProvider)
        }
    }
}

// MARK: - App View

public enum AppView: Hashable {
    case dashboard
    case chat
    case models
    case cluster
    case settings
}
