import Foundation
import SharedTypes

// MARK: - Cluster Topology

/// Maintains a sorted view of the cluster and aggregate statistics
public struct ClusterTopology: Sendable {

    /// Peers sorted by capability score (highest first)
    public var sortedPeers: [PeerInfo]

    /// Only connected peers
    public var connectedPeers: [PeerInfo] {
        sortedPeers.filter { $0.status == .connected }
    }

    /// Total RAM across all connected peers
    public var totalRAMGB: Double {
        connectedPeers.reduce(0) { $0 + $1.deviceInfo.hardware.totalRAMGB }
    }

    /// Total estimated memory bandwidth across all connected peers
    public var totalBandwidthGBs: Double {
        connectedPeers.reduce(0) { $0 + $1.deviceInfo.hardware.memoryBandwidthGBs }
    }

    /// Models available across the cluster
    public var availableModels: Set<String> {
        var models = Set<String>()
        for peer in connectedPeers {
            for model in peer.loadedModels {
                models.insert(model)
            }
        }
        return models
    }

    /// Find peers that have a specific model loaded
    public func peersWithModel(_ modelID: String) -> [PeerInfo] {
        connectedPeers.filter { $0.loadedModels.contains(modelID) }
    }

    /// Find the best peer for a given model (loaded, not busy, highest capability)
    public func bestPeerForModel(_ modelID: String) -> PeerInfo? {
        peersWithModel(modelID)
            .filter { !$0.isGenerating && $0.throttleLevel > 0 && $0.thermalLevel < .serious }
            .sorted { $0.capabilityScore > $1.capabilityScore }
            .first
    }

    /// Cluster state summary for UI
    public func toClusterState(isEnabled: Bool) -> ClusterState {
        ClusterState(
            isEnabled: isEnabled,
            peerCount: sortedPeers.count,
            connectedPeerCount: connectedPeers.count,
            totalClusterRAMGB: totalRAMGB,
            totalClusterBandwidthGBs: totalBandwidthGBs
        )
    }

    public init(peers: [PeerInfo] = []) {
        self.sortedPeers = peers.sorted { $0.capabilityScore > $1.capabilityScore }
    }

    /// Update with new peer list
    public mutating func update(peers: [PeerInfo]) {
        self.sortedPeers = peers.sorted { $0.capabilityScore > $1.capabilityScore }
    }
}
