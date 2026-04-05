import Foundation

// MARK: - Inference Provider Protocol

/// Core protocol abstracting inference backends (MLX, CoreML, etc.)
public protocol InferenceProvider: Sendable {
    /// Current status of the engine
    var status: EngineStatus { get async }

    /// The currently loaded model, if any
    var loadedModel: ModelDescriptor? { get async }

    /// Load a model for inference
    func loadModel(_ descriptor: ModelDescriptor) async throws

    /// Unload the current model, freeing memory
    func unloadModel() async

    /// Generate a streaming completion
    func generate(request: ChatCompletionRequest) -> AsyncThrowingStream<ChatCompletionChunk, Error>

    /// Generate a non-streaming completion (collects all tokens)
    func generateFull(request: ChatCompletionRequest) async throws -> ChatCompletionResponse
}

// MARK: - Default implementation for generateFull

extension InferenceProvider {
    public func generateFull(request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        var fullContent = ""
        let stream = generate(request: request)
        var lastChunkId = "chatcmpl-\(UUID().uuidString)"
        var model = request.model ?? "unknown"

        for try await chunk in stream {
            lastChunkId = chunk.id
            model = chunk.model
            if let content = chunk.choices.first?.delta.content {
                fullContent += content
            }
        }

        return ChatCompletionResponse(
            id: lastChunkId,
            model: model,
            choices: [
                .init(index: 0, message: APIMessage(role: "assistant", content: fullContent), finishReason: "stop")
            ],
            usage: nil
        )
    }
}
