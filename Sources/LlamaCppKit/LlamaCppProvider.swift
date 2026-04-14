import Foundation
import SharedTypes

// MARK: - LlamaCpp Inference Provider

/// Manages a llama-server subprocess and communicates via its OpenAI-compatible HTTP API.
public actor LlamaCppProvider: InferenceProvider {
    private var serverProcess: Process?
    private var currentDescriptor: ModelDescriptor?
    private var _status: EngineStatus = .idle
    private var serverPort: Int
    private let session: URLSession

    /// Path to the llama-server binary. Defaults to searching PATH.
    private let binaryPath: String

    /// GPU layers to offload (999 = all layers).
    private let gpuLayers: Int

    /// Context size for the server.
    private let contextSize: Int

    /// Number of parallel request slots.
    private let parallelSlots: Int

    public init(
        binaryPath: String = "llama-server",
        port: Int = 11436,
        gpuLayers: Int = 999,
        contextSize: Int = 8192,
        parallelSlots: Int = 2
    ) {
        self.binaryPath = binaryPath
        self.serverPort = port
        self.gpuLayers = gpuLayers
        self.contextSize = contextSize
        self.parallelSlots = parallelSlots

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }

    // MARK: - InferenceProvider

    public var status: EngineStatus { _status }

    public var loadedModel: ModelDescriptor? { currentDescriptor }

    public func loadModel(_ descriptor: ModelDescriptor) async throws {
        // Stop any existing server
        await stopServer()

        _status = .loadingModel(descriptor)

        // Resolve model path — huggingFaceRepo holds the local file path for GGUF models
        let modelPath = descriptor.huggingFaceRepo
        guard FileManager.default.fileExists(atPath: modelPath) else {
            _status = .error("GGUF file not found: \(modelPath)")
            throw LlamaCppError.modelNotFound(modelPath)
        }

        try await startServer(modelPath: modelPath)

        currentDescriptor = descriptor
        _status = .ready(descriptor)
    }

    public func unloadModel() async {
        await stopServer()
        currentDescriptor = nil
        _status = .idle
    }

    public nonisolated func generate(request: ChatCompletionRequest) -> AsyncThrowingStream<ChatCompletionChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self._generate(request: request, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Server Lifecycle

    private func startServer(modelPath: String) async throws {
        let resolvedBinary = resolvedBinaryPath()
        guard FileManager.default.isExecutableFile(atPath: resolvedBinary) else {
            throw LlamaCppError.binaryNotFound(resolvedBinary)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedBinary)
        process.arguments = [
            "--model", modelPath,
            "--host", "127.0.0.1",
            "--port", "\(serverPort)",
            "--n-gpu-layers", "\(gpuLayers)",
            "--ctx-size", "\(contextSize)",
            "--parallel", "\(parallelSlots)",
            "--no-webui",
        ]

        // Silence server output by default
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        serverProcess = process

        // Wait for the server to become healthy
        try await waitForHealth(timeoutSeconds: 60)
    }

    private func stopServer() async {
        guard let process = serverProcess, process.isRunning else {
            serverProcess = nil
            return
        }
        process.terminate()
        process.waitUntilExit()
        serverProcess = nil
    }

    private func waitForHealth(timeoutSeconds: Int) async throws {
        let url = serverBaseURL.appendingPathComponent("health")
        let deadline = Date().addingTimeInterval(Double(timeoutSeconds))

        while Date() < deadline {
            do {
                let (_, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    return
                }
            } catch {
                // Server not ready yet
            }
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        }

        // Timed out — kill the server
        await stopServer()
        throw LlamaCppError.serverStartTimeout
    }

    // MARK: - Generation

    private func _generate(
        request: ChatCompletionRequest,
        continuation: AsyncThrowingStream<ChatCompletionChunk, Error>.Continuation
    ) async throws {
        guard let descriptor = currentDescriptor else {
            throw LlamaCppError.noModelLoaded
        }

        _status = .generating(descriptor, tokensGenerated: 0)

        let url = serverBaseURL.appendingPathComponent("v1/chat/completions")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 600

        var proxiedRequest = request
        proxiedRequest.stream = true
        urlRequest.httpBody = try JSONEncoder().encode(proxiedRequest)

        do {
            let (bytes, response) = try await session.bytes(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LlamaCppError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                throw LlamaCppError.serverError("HTTP \(httpResponse.statusCode)")
            }

            var tokenCount = 0
            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let payload = String(line.dropFirst(6))

                if payload == "[DONE]" {
                    break
                }

                guard let data = payload.data(using: .utf8) else { continue }
                let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: data)
                if let content = chunk.choices.first?.delta.content, !content.isEmpty {
                    tokenCount += 1
                    _status = .generating(descriptor, tokensGenerated: tokenCount)
                }
                continuation.yield(chunk)
            }

            _status = .ready(descriptor)
            continuation.finish()
        } catch {
            _status = .error(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Helpers

    private var serverBaseURL: URL {
        URL(string: "http://127.0.0.1:\(serverPort)")!
    }

    private func resolvedBinaryPath() -> String {
        // If an absolute path was given, use it directly
        if binaryPath.hasPrefix("/") {
            return binaryPath
        }

        // Search common locations
        let searchPaths = [
            "/usr/local/bin/\(binaryPath)",
            "/opt/homebrew/bin/\(binaryPath)",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/\(binaryPath)",
            // App bundle
            Bundle.main.bundlePath + "/Contents/MacOS/\(binaryPath)",
            Bundle.main.bundlePath + "/Contents/Resources/\(binaryPath)",
        ]

        for path in searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fall back to PATH resolution via /usr/bin/which
        if let whichResult = try? shellWhich(binaryPath) {
            return whichResult
        }

        return binaryPath
    }

    private func shellWhich(_ name: String) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Check if the server process is currently running.
    public var isServerRunning: Bool {
        serverProcess?.isRunning ?? false
    }

    /// Update the port number (takes effect on next model load).
    public func updatePort(_ port: Int) {
        serverPort = port
    }
}

// MARK: - Errors

public enum LlamaCppError: LocalizedError {
    case binaryNotFound(String)
    case modelNotFound(String)
    case serverStartTimeout
    case noModelLoaded
    case invalidResponse
    case serverError(String)

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound(let path):
            return "llama-server binary not found at: \(path). Install llama.cpp or set the binary path."
        case .modelNotFound(let path):
            return "GGUF model file not found: \(path)"
        case .serverStartTimeout:
            return "llama-server failed to start within the timeout period."
        case .noModelLoaded:
            return "No model is loaded in llama-server."
        case .invalidResponse:
            return "llama-server returned an invalid response."
        case .serverError(let message):
            return "llama-server error: \(message)"
        }
    }
}
