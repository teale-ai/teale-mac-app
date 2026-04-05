import Foundation
import Hummingbird
import SharedTypes
import InferenceEngine

// MARK: - HTTP Server

public actor LocalHTTPServer {
    private let engine: InferenceEngineManager
    public let port: Int

    public init(engine: InferenceEngineManager, port: Int = 11435) {
        self.engine = engine
        self.port = port
    }

    public func start() async throws {
        let engine = self.engine

        let router = Router()

        // CORS
        router.addMiddleware {
            CORSMiddleware(
                allowOrigin: .originBased,
                allowHeaders: [.contentType, .authorization],
                allowMethods: [.get, .post, .options]
            )
        }

        // Health check
        router.get("/health") { _, _ in
            return "{\"status\":\"ok\"}"
        }

        // Models endpoint
        router.get("/v1/models") { _, _ -> Response in
            return try await ModelsRoute.handle(engine: engine)
        }

        // Chat completions endpoint
        router.post("/v1/chat/completions") { request, _ -> Response in
            return try await ChatCompletionsRoute.handle(request: request, engine: engine)
        }

        let app = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: port))
        )
        try await app.run()
    }
}
