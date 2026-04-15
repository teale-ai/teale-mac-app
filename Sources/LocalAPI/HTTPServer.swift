import Foundation
import Hummingbird
import SharedTypes
import InferenceEngine

// MARK: - HTTP Server

/// Returns model IDs available on connected peers (WAN + cluster).
public typealias PeerModelProvider = @Sendable () async -> [(id: String, ownedBy: String)]

public actor LocalHTTPServer {
    private let engine: InferenceEngineManager
    public let port: Int
    private let apiKeyStore: APIKeyStore
    private let allowNetworkAccess: Bool
    private let controller: (any LocalAppControlling)?
    private let peerModelProvider: PeerModelProvider?

    public init(
        engine: InferenceEngineManager,
        port: Int = 11435,
        apiKeyStore: APIKeyStore = APIKeyStore(),
        allowNetworkAccess: Bool = false,
        controller: (any LocalAppControlling)? = nil,
        peerModelProvider: PeerModelProvider? = nil
    ) {
        self.engine = engine
        self.port = port
        self.apiKeyStore = apiKeyStore
        self.allowNetworkAccess = allowNetworkAccess
        self.controller = controller
        self.peerModelProvider = peerModelProvider
    }

    public func start() async throws {
        let engine = self.engine
        let keyStore = self.apiKeyStore
        let requireAuth = self.allowNetworkAccess
        let controller = self.controller
        let peerModels = self.peerModelProvider

        let router = Router()

        // CORS
        router.addMiddleware {
            CORSMiddleware(
                allowOrigin: .originBased,
                allowHeaders: [.contentType, .authorization],
                allowMethods: [.get, .post, .options]
            )
        }

        // Auth (require key when network access is enabled)
        router.addMiddleware {
            AuthMiddleware(keyStore: keyStore, requireAuth: requireAuth)
        }

        // Health check (no auth needed — middleware passes through if not required)
        router.get("/health") { _, _ in
            return "{\"status\":\"ok\"}"
        }

        // Models endpoint
        router.get("/v1/models") { _, _ -> Response in
            return try await ModelsRoute.handle(engine: engine, peerModelProvider: peerModels)
        }

        // Chat completions endpoint
        router.post("/v1/chat/completions") { request, _ -> Response in
            return try await ChatCompletionsRoute.handle(request: request, engine: engine)
        }

        // Remote control endpoints
        router.get("/v1/app") { _, _ -> Response in
            return try await RemoteControlRoute.snapshot(controller: controller)
        }

        router.patch("/v1/app/settings") { request, _ -> Response in
            return try await RemoteControlRoute.updateSettings(request: request, controller: controller)
        }

        router.post("/v1/app/models/load") { request, _ -> Response in
            return try await RemoteControlRoute.loadModel(request: request, controller: controller)
        }

        router.post("/v1/app/models/download") { request, _ -> Response in
            return try await RemoteControlRoute.downloadModel(request: request, controller: controller)
        }

        router.post("/v1/app/models/unload") { _, _ -> Response in
            return try await RemoteControlRoute.unloadModel(controller: controller)
        }

        // PTN endpoints
        router.get("/v1/app/ptn") { _, _ -> Response in
            return try await RemoteControlRoute.listPTNs(controller: controller)
        }

        router.post("/v1/app/ptn/create") { request, _ -> Response in
            return try await RemoteControlRoute.createPTN(request: request, controller: controller)
        }

        router.post("/v1/app/ptn/invite") { request, _ -> Response in
            return try await RemoteControlRoute.generatePTNInvite(request: request, controller: controller)
        }

        router.post("/v1/app/ptn/leave") { request, _ -> Response in
            return try await RemoteControlRoute.leavePTN(request: request, controller: controller)
        }

        // API Key endpoints
        router.get("/v1/app/apikeys") { _, _ -> Response in
            return try await RemoteControlRoute.listAPIKeys(controller: controller)
        }

        router.post("/v1/app/apikeys") { request, _ -> Response in
            return try await RemoteControlRoute.generateAPIKey(request: request, controller: controller)
        }

        router.post("/v1/app/apikeys/revoke") { request, _ -> Response in
            return try await RemoteControlRoute.revokeAPIKey(request: request, controller: controller)
        }

        // Wallet endpoints
        router.get("/v1/app/wallet") { _, _ -> Response in
            return try await RemoteControlRoute.walletBalance(controller: controller)
        }

        router.get("/v1/app/wallet/transactions") { request, _ -> Response in
            return try await RemoteControlRoute.walletTransactions(request: request, controller: controller)
        }

        router.post("/v1/app/wallet/send") { request, _ -> Response in
            return try await RemoteControlRoute.walletSend(request: request, controller: controller)
        }

        router.get("/v1/app/wallet/solana") { _, _ -> Response in
            return try await RemoteControlRoute.solanaStatus(controller: controller)
        }

        // Peers endpoint
        router.get("/v1/app/peers") { _, _ -> Response in
            return try await RemoteControlRoute.listPeers(controller: controller)
        }

        let bindAddress = allowNetworkAccess ? "0.0.0.0" : "127.0.0.1"
        let app = Application(
            router: router,
            configuration: .init(address: .hostname(bindAddress, port: port))
        )
        try await app.run()
    }
}
