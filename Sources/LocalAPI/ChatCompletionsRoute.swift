import Foundation
import Hummingbird
import NIOCore
import SharedTypes
import InferenceEngine

// MARK: - Chat Completions Route

enum ChatCompletionsRoute {
    static func handle(request: Request, engine: InferenceEngineManager) async throws -> Response {
        let body = try await request.body.collect(upTo: 1_048_576)
        let chatRequest = try JSONDecoder().decode(ChatCompletionRequest.self, from: body)

        guard await engine.loadedModel != nil else {
            let error = APIErrorResponse(message: "No model loaded. Load a model first.", type: "invalid_request_error")
            let data = try JSONEncoder().encode(error)
            return Response(
                status: .badRequest,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(data: data))
            )
        }

        let isStreaming = chatRequest.stream ?? false

        if isStreaming {
            return try await handleStreaming(request: chatRequest, engine: engine)
        } else {
            return try await handleNonStreaming(request: chatRequest, engine: engine)
        }
    }

    private static func handleNonStreaming(
        request: ChatCompletionRequest,
        engine: InferenceEngineManager
    ) async throws -> Response {
        let response = try await engine.generateFull(request: request)
        let data = try JSONEncoder().encode(response)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data))
        )
    }

    private static func handleStreaming(
        request: ChatCompletionRequest,
        engine: InferenceEngineManager
    ) async throws -> Response {
        let stream = engine.generate(request: request)
        let encoder = JSONEncoder()

        let responseBody = ResponseBody(contentLength: nil) { writer in
            do {
                for try await chunk in stream {
                    let data = try encoder.encode(chunk)
                    if let str = String(data: data, encoding: .utf8) {
                        try await writer.write(.init(string: "data: \(str)\n\n"))
                    }
                }
                try await writer.write(.init(string: "data: [DONE]\n\n"))
            } catch {
                let errorMsg = "data: {\"error\": \"\(error.localizedDescription)\"}\n\n"
                try await writer.write(.init(string: errorMsg))
            }
        }

        return Response(
            status: .ok,
            headers: [
                .contentType: "text/event-stream",
                .cacheControl: "no-cache",
                .connection: "keep-alive",
            ],
            body: responseBody
        )
    }
}
