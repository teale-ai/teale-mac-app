import Foundation
import SharedTypes

// MARK: - Request Router

/// Routes inference requests to the best available node in the cluster
public struct RequestRouter: Sendable {

    public init() {}

    /// Decide where to route a request
    public func route(
        request: ChatCompletionRequest,
        clusterManager: ClusterManager,
        localModelLoaded: String?
    ) -> RouteDecision {
        let modelID = request.model ?? localModelLoaded ?? ""

        // First: check if any remote peer has the model loaded and is available
        if let bestPeer = clusterManager.bestPeer(forModel: modelID) {
            return .remote(peerID: bestPeer.id, peer: bestPeer)
        }

        // Second: if local model is loaded, use local
        if localModelLoaded != nil {
            return .local
        }

        // Third: check if any remote peer has any model loaded
        let anyAvailablePeer = clusterManager.topology.connectedPeers
            .filter { !$0.isGenerating && $0.throttleLevel > 0 && !$0.loadedModels.isEmpty }
            .sorted { $0.capabilityScore > $1.capabilityScore }
            .first

        if let peer = anyAvailablePeer {
            return .remote(peerID: peer.id, peer: peer)
        }

        // No model available anywhere
        return .noModelAvailable
    }
}

// MARK: - Route Decision

public enum RouteDecision: Sendable {
    case local
    case remote(peerID: UUID, peer: PeerInfo)
    case noModelAvailable
}
