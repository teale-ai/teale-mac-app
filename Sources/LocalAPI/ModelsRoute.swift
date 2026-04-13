import Foundation
import Hummingbird
import SharedTypes
import InferenceEngine

// MARK: - Models Route

enum ModelsRoute {
    static func handle(engine: InferenceEngineManager, peerModelProvider: PeerModelProvider?) async throws -> Response {
        var models: [ModelsListResponse.ModelObject] = []
        var seen: Set<String> = []

        if let loaded = await engine.loadedModel {
            models.append(ModelsListResponse.ModelObject(
                id: loaded.huggingFaceRepo,
                object: "model",
                created: Int(Date().timeIntervalSince1970),
                ownedBy: "local"
            ))
            seen.insert(loaded.huggingFaceRepo)
        }

        // Include models from connected WAN and cluster peers
        if let provider = peerModelProvider {
            let peerModels = await provider()
            for pm in peerModels where !seen.contains(pm.id) {
                models.append(ModelsListResponse.ModelObject(
                    id: pm.id,
                    object: "model",
                    created: Int(Date().timeIntervalSince1970),
                    ownedBy: pm.ownedBy
                ))
                seen.insert(pm.id)
            }
        }

        let response = ModelsListResponse(data: models)
        let data = try JSONEncoder().encode(response)

        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data))
        )
    }
}
