import Foundation
import Network
import SharedTypes
import HardwareProfile

// MARK: - Cluster Manager

/// Central orchestrator for LAN cluster mode
@Observable
public final class ClusterManager: @unchecked Sendable {
    // State
    public private(set) var isEnabled: Bool = false
    public private(set) var peers: [UUID: PeerInfo] = [:]
    public private(set) var topology: ClusterTopology = ClusterTopology()
    public private(set) var clusterState: ClusterState = ClusterState()

    // Configuration
    public var passcode: String?
    public var deviceName: String

    // Components
    private let localDeviceInfo: DeviceInfo
    private var bonjourService: BonjourService?
    private var peerResolver: PeerResolver?
    private let healthMonitor = PeerHealthMonitor()
    private var heartbeatTask: Task<Void, Never>?
    private var healthCheckTask: Task<Void, Never>?

    // Callbacks for inference handling
    public var onInferenceRequest: ((InferenceRequestPayload, PeerConnection) async -> Void)?

    public init(localDeviceInfo: DeviceInfo) {
        self.localDeviceInfo = localDeviceInfo
        self.deviceName = localDeviceInfo.name
    }

    // MARK: - Enable/Disable

    public func enable() {
        guard !isEnabled else { return }
        isEnabled = true

        let passcodeHash = passcode.map { ClusterSecurity.hashPasscode($0) }
        let parameters = NWParameters.clusterParameters(passcode: passcode)

        bonjourService = BonjourService(localDeviceID: localDeviceInfo.id, parameters: parameters)
        peerResolver = PeerResolver(localDeviceInfo: localDeviceInfo, passcodeHash: passcodeHash, parameters: parameters)

        // Handle discovered peers
        bonjourService?.onPeerDiscovered = { [weak self] endpoint, txtDict in
            Task { await self?.handlePeerDiscovered(endpoint: endpoint, txtDict: txtDict) }
        }

        bonjourService?.onPeerRemoved = { [weak self] endpoint in
            Task { await self?.handlePeerRemoved(endpoint: endpoint) }
        }

        // Handle incoming connections
        bonjourService?.onIncomingConnection = { [weak self] connection in
            Task { await self?.handleIncomingConnection(connection) }
        }

        // Start advertising and browsing
        try? bonjourService?.startAdvertising(deviceInfo: localDeviceInfo)
        bonjourService?.startBrowsing()

        // Start heartbeat and health check loops
        startHeartbeatLoop()
        startHealthCheckLoop()

        updateState()
    }

    public func disable() {
        guard isEnabled else { return }
        isEnabled = false

        bonjourService?.stop()
        bonjourService = nil
        peerResolver = nil

        heartbeatTask?.cancel()
        healthCheckTask?.cancel()

        // Disconnect all peers
        for (_, peer) in peers {
            Task { await peer.connection.cancel() }
        }
        peers.removeAll()

        updateState()
    }

    // MARK: - Peer Management

    private func handlePeerDiscovered(endpoint: NWEndpoint, txtDict: [String: String]) async {
        guard let resolver = peerResolver else { return }

        do {
            let peerInfo = try await resolver.resolve(endpoint: endpoint)
            peers[peerInfo.id] = peerInfo
            startListening(to: peerInfo)
            updateState()
        } catch {
            // Discovery failed, will retry on next Bonjour update
        }
    }

    private func handlePeerRemoved(endpoint: NWEndpoint) {
        // Remove peer associated with this endpoint
        // Since we can't easily match endpoint to peer, mark all as needing revalidation
        // The health monitor will handle cleanup
    }

    private func handleIncomingConnection(_ connection: NWConnection) async {
        guard let resolver = peerResolver else { return }

        do {
            let peerInfo = try await resolver.acceptIncoming(connection: connection)
            // Avoid duplicate connections
            if peers[peerInfo.id] == nil {
                peers[peerInfo.id] = peerInfo
                startListening(to: peerInfo)
                updateState()
            } else {
                await peerInfo.connection.cancel()
            }
        } catch {
            // Incoming connection failed
        }
    }

    // MARK: - Message Handling

    private func startListening(to peer: PeerInfo) {
        Task {
            let messages = await peer.connection.incomingMessages
            for await message in messages {
                await handleMessage(message, from: peer)
            }
            // Connection ended
            peer.status = .disconnected
            updateState()
        }
    }

    private func handleMessage(_ message: ClusterMessage, from peer: PeerInfo) async {
        switch message {
        case .heartbeat(let payload):
            peer.lastHeartbeat = Date()
            peer.loadedModels = payload.loadedModels
            peer.isGenerating = payload.isGenerating
            peer.thermalLevel = payload.thermalLevel
            peer.throttleLevel = payload.throttleLevel
            if peer.status == .degraded {
                peer.status = .connected
            }
            // Send ack
            let ack = HeartbeatPayload(deviceID: localDeviceInfo.id)
            try? await peer.connection.send(.heartbeatAck(ack))
            updateState()

        case .heartbeatAck:
            peer.lastHeartbeat = Date()
            if peer.status == .degraded {
                peer.status = .connected
                updateState()
            }

        case .inferenceRequest(let payload):
            // Delegate to the inference handler
            await onInferenceRequest?(payload, peer.connection)

        case .inferenceChunk, .inferenceComplete, .inferenceError:
            // These are handled by the ClusterProvider waiting on specific requestIDs
            break

        default:
            break
        }
    }

    // MARK: - Heartbeat Loop

    private func startHeartbeatLoop() {
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self = self else { return }

                let heartbeat = await self.healthMonitor.makeHeartbeat(
                    deviceID: self.localDeviceInfo.id,
                    thermalLevel: .nominal,  // TODO: wire to actual throttler
                    throttleLevel: 100,
                    loadedModels: self.localDeviceInfo.loadedModels,
                    isGenerating: false
                )

                for (_, peer) in self.peers where peer.status == .connected || peer.status == .degraded {
                    try? await peer.connection.send(.heartbeat(heartbeat))
                }
            }
        }
    }

    private func startHealthCheckLoop() {
        healthCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self = self else { return }

                let updates = await self.healthMonitor.checkHealth(peers: Array(self.peers.values))
                for (peerID, newStatus) in updates {
                    if let peer = self.peers[peerID] {
                        peer.status = newStatus
                        if newStatus == .disconnected {
                            await peer.connection.cancel()
                        }
                    }
                }

                // Remove disconnected peers after a grace period
                let disconnectedIDs = self.peers.filter { $0.value.status == .disconnected }.map { $0.key }
                for id in disconnectedIDs {
                    self.peers.removeValue(forKey: id)
                }

                if !updates.isEmpty {
                    self.updateState()
                }
            }
        }
    }

    // MARK: - State Updates

    private func updateState() {
        topology.update(peers: Array(peers.values))
        clusterState = topology.toClusterState(isEnabled: isEnabled)
    }

    /// Get summaries of all peers for UI
    public var peerSummaries: [PeerSummary] {
        Array(peers.values).map { $0.toSummary() }
    }

    /// Find the best peer to handle inference for a given model
    public func bestPeer(forModel modelID: String) -> PeerInfo? {
        topology.bestPeerForModel(modelID)
    }
}
