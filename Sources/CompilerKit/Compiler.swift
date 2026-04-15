import Foundation
import SharedTypes

// MARK: - Compiler

/// The main entry point for Mixture of Models (MoM) compilation.
/// Conforms to InferenceProvider — drop-in replacement for any existing provider.
///
/// Pipeline: Analyze → Decompose → Select Models → Execute in Parallel → Synthesize
public actor Compiler: InferenceProvider {

    // MARK: - Components

    private let analyzer: RequestAnalyzer
    private let decomposer: TaskDecomposer
    private let selector: ModelSelector
    private let executor: FanOutExecutor
    private let synthesizer: ResponseSynthesizer
    private let fallbackProvider: any InferenceProvider

    // MARK: - Network State

    private var availableModels: [ModelOnNetwork] = []

    /// Callback fired after a compiled response completes, with contribution records.
    private let onCompilationCompleted: (@Sendable ([ContributionRecord]) async -> Void)?

    // MARK: - InferenceProvider Conformance (delegated)

    public var status: EngineStatus {
        get async { await fallbackProvider.status }
    }

    public var loadedModel: ModelDescriptor? {
        get async { await fallbackProvider.loadedModel }
    }

    // MARK: - Init

    /// Create a Compiler.
    ///
    /// - Parameters:
    ///   - compilerProvider: Small/fast model for decomposition (the "compiler" model).
    ///     Can be the same as fallbackProvider on single-model setups.
    ///   - fallbackProvider: Provider for passthrough requests and synthesis.
    ///   - onCompilationCompleted: Called with contribution records after a compiled response.
    public init(
        compilerProvider: any InferenceProvider,
        fallbackProvider: any InferenceProvider,
        synthesisProvider: (any InferenceProvider)? = nil,
        onCompilationCompleted: (@Sendable ([ContributionRecord]) async -> Void)? = nil
    ) {
        self.analyzer = RequestAnalyzer()
        self.decomposer = TaskDecomposer(provider: compilerProvider)
        self.selector = ModelSelector()
        self.executor = FanOutExecutor()
        self.synthesizer = ResponseSynthesizer(synthesisProvider: synthesisProvider ?? fallbackProvider)
        self.fallbackProvider = fallbackProvider
        self.onCompilationCompleted = onCompilationCompleted
    }

    // MARK: - Network State

    /// Update the list of models currently available on the network.
    /// Call this when peers connect/disconnect or models load/unload.
    public func updateAvailableModels(_ models: [ModelOnNetwork]) {
        self.availableModels = models
    }

    // MARK: - Model Loading (delegated to fallback)

    public func loadModel(_ descriptor: ModelDescriptor) async throws {
        try await fallbackProvider.loadModel(descriptor)
    }

    public func loadModel(_ descriptor: ModelDescriptor, onProgress: LoadProgressCallback?) async throws {
        try await fallbackProvider.loadModel(descriptor, onProgress: onProgress)
    }

    public func unloadModel() async {
        await fallbackProvider.unloadModel()
    }

    // MARK: - Generation

    public nonisolated func generate(request: ChatCompletionRequest) -> AsyncThrowingStream<ChatCompletionChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self._generate(request: request, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func generateFull(request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        let shouldCompile = analyzer.shouldCompile(
            request: request,
            availableModelCount: availableModels.count
        )

        if !shouldCompile {
            return try await fallbackProvider.generateFull(request: request)
        }

        // Compile the request
        let result = try await compile(request: request)
        return ChatCompletionResponse(
            id: "chatcmpl-\(UUID().uuidString)",
            model: "mom-compiler",
            choices: [
                .init(index: 0, message: APIMessage(role: "assistant", content: result), finishReason: "stop")
            ]
        )
    }

    // MARK: - Core Compilation Pipeline

    private func compile(request: ChatCompletionRequest) async throws -> String {
        // Stage 1 & 2: Decompose
        guard let decomposition = try await decomposer.decompose(request: request) else {
            // Decomposer decided this isn't decomposable — fallback
            return try await fallbackFull(request: request)
        }

        let subTasks = decomposition.subTasks
        guard !subTasks.isEmpty else {
            return try await fallbackFull(request: request)
        }

        // Stage 3: Select models for each sub-task
        let assignments = selector.assign(subTasks: subTasks, available: availableModels)

        // Verify we have assignments for all sub-tasks
        let unassigned = subTasks.filter { assignments[$0.id] == nil }
        if !unassigned.isEmpty {
            // Some sub-tasks couldn't be assigned — fall back
            return try await fallbackFull(request: request)
        }

        // Stage 4: Execute in parallel
        // The generateFn closure is what actually calls inference on a device.
        // In the current architecture, we use the fallback provider for all sub-tasks.
        // When integrated with ClusterKit, this will dispatch to specific peers.
        let generateFn: @Sendable (SubTask, ModelOnNetwork, [SubTaskResult]) async throws -> SubTaskResult = {
            [fallbackProvider] subTask, model, depResults in

            let start = CFAbsoluteTimeGetCurrent()

            // Build the sub-task request, optionally including dependency context
            var messages = [APIMessage(role: "user", content: subTask.prompt)]
            if !depResults.isEmpty {
                let context = depResults.map(\.content).joined(separator: "\n\n")
                messages.insert(
                    APIMessage(role: "system", content: "Context from prior steps:\n\(context)"),
                    at: 0
                )
            }

            let subRequest = ChatCompletionRequest(
                model: model.model,
                messages: messages,
                maxTokens: subTask.estimatedTokens
            )

            let response = try await fallbackProvider.generateFull(request: subRequest)
            let content = response.choices.first?.message.content ?? ""
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

            return SubTaskResult(
                subTaskID: subTask.id,
                content: content,
                model: model.model,
                deviceID: model.deviceID,
                tokenCount: response.usage?.completionTokens ?? content.split(separator: " ").count,
                latencyMs: elapsed
            )
        }

        let results = try await executor.execute(
            subTasks: subTasks,
            assignments: assignments,
            generateFn: generateFn
        )

        // Stage 5: Synthesize
        let finalResponse = try await synthesizer.synthesize(
            results: results,
            originalRequest: request,
            synthesisPrompt: decomposition.synthesisPrompt
        )

        // Record contributions
        let totalTokens = results.reduce(0) { $0 + $1.tokenCount }
        let contributions = results.map { result in
            ContributionRecord(
                deviceID: result.deviceID,
                model: result.model,
                subTaskID: result.subTaskID,
                tokenCount: result.tokenCount,
                weight: totalTokens > 0 ? Double(result.tokenCount) / Double(totalTokens) : 0
            )
        }
        if let callback = onCompilationCompleted {
            await callback(contributions)
        }

        return finalResponse
    }

    // MARK: - Streaming Compilation

    private func _generate(
        request: ChatCompletionRequest,
        continuation: AsyncThrowingStream<ChatCompletionChunk, Error>.Continuation
    ) async throws {
        let shouldCompile = analyzer.shouldCompile(
            request: request,
            availableModelCount: availableModels.count
        )

        if !shouldCompile {
            // Passthrough: stream directly from fallback
            let stream = fallbackProvider.generate(request: request)
            for try await chunk in stream {
                continuation.yield(chunk)
            }
            continuation.finish()
            return
        }

        // Compile and stream the result
        let result = try await compile(request: request)

        // Stream the compiled result as chunks
        let chunkID = "chatcmpl-\(UUID().uuidString)"
        let words = result.components(separatedBy: " ")

        // Emit role chunk
        continuation.yield(ChatCompletionChunk(
            id: chunkID,
            model: "mom-compiler",
            choices: [.init(index: 0, delta: .init(role: "assistant"), finishReason: nil)]
        ))

        // Emit content in word-sized chunks for natural streaming feel
        for (i, word) in words.enumerated() {
            let content = i == 0 ? word : " \(word)"
            continuation.yield(ChatCompletionChunk(
                id: chunkID,
                model: "mom-compiler",
                choices: [.init(index: 0, delta: .init(content: content), finishReason: nil)]
            ))
        }

        // Emit finish chunk
        continuation.yield(ChatCompletionChunk(
            id: chunkID,
            model: "mom-compiler",
            choices: [.init(index: 0, delta: .init(), finishReason: "stop")]
        ))

        continuation.finish()
    }

    // MARK: - Helpers

    private func fallbackFull(request: ChatCompletionRequest) async throws -> String {
        let response = try await fallbackProvider.generateFull(request: request)
        return response.choices.first?.message.content ?? ""
    }
}
