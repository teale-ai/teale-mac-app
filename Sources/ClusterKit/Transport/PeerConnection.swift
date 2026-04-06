import Foundation
import Network
import OSLog

// MARK: - Peer Connection

/// Wraps NWConnection to provide typed async message send/receive
public actor PeerConnection {
    private static let logger = Logger(subsystem: "com.teale.app", category: "ClusterTransport")
    public let connection: NWConnection
    public let peerID: UUID?
    private var messageContinuation: AsyncStream<ClusterMessage>.Continuation?
    private var _incomingMessages: AsyncStream<ClusterMessage>?
    public private(set) var isReady: Bool = false
    public private(set) var localNetworkDenied: Bool = false

    public init(connection: NWConnection, peerID: UUID? = nil) {
        self.connection = connection
        self.peerID = peerID
    }

    private static var clusterContentContext: NWConnection.ContentContext {
        let message = NWProtocolFramer.Message(definition: ClusterMessageFramer.definition)
        return NWConnection.ContentContext(
            identifier: ClusterMessageFramer.label,
            metadata: [message]
        )
    }

    private nonisolated func shouldContinueReceiving(
        content: Data?,
        isComplete: Bool,
        error: NWError?
    ) -> Bool {
        if error == nil {
            // For framed messages, receiveMessage() sets isComplete=true when a full
            // message arrives. That is not a connection close signal.
            return content != nil || !isComplete
        }

        switch error {
        case .posix(let code):
            // NWConnection.receiveMessage() on a framed TCP stream can report
            // ENODATA/EAGAIN before the next framed message is ready. Treat that
            // as a transient condition instead of permanently stopping reads.
            return code == .ENODATA || code == .EAGAIN
        default:
            return false
        }
    }

    /// Start the connection and begin receiving messages
    public func start() async {
        let (stream, continuation) = AsyncStream<ClusterMessage>.makeStream()
        self.messageContinuation = continuation
        self._incomingMessages = stream

        connection.stateUpdateHandler = { [weak self] state in
            Task { await self?.handleStateChange(state) }
        }

        connection.start(queue: .global(qos: .userInitiated))
        await waitForReady()
        receiveNextMessage()
    }

    /// Incoming messages as an async stream
    public var incomingMessages: AsyncStream<ClusterMessage> {
        get async {
            if let stream = _incomingMessages {
                return stream
            }
            // Create and return an empty stream if not started
            return AsyncStream { $0.finish() }
        }
    }

    /// Send a message to the peer
    public func send(_ message: ClusterMessage) async throws {
        let data = try JSONEncoder().encode(message)

        return try await withCheckedThrowingContinuation { continuation in
            connection.send(
                content: data,
                contentContext: Self.clusterContentContext,
                isComplete: true,
                completion: .contentProcessed { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }

    /// Cancel the connection
    public func cancel() {
        connection.cancel()
        messageContinuation?.finish()
    }

    // MARK: - Private

    private func handleStateChange(_ state: NWConnection.State) {
        if let currentPath = connection.currentPath,
           currentPath.unsatisfiedReason == .localNetworkDenied {
            localNetworkDenied = true
        }

        switch state {
        case .ready:
            isReady = true
            Self.logger.info("Connection ready endpoint=\(String(describing: self.connection.endpoint), privacy: .public)")
        case .waiting(let error):
            Self.logger.error(
                "Connection waiting endpoint=\(String(describing: self.connection.endpoint), privacy: .public) error=\(error.localizedDescription, privacy: .public) reason=\(String(describing: self.connection.currentPath?.unsatisfiedReason), privacy: .public)"
            )
        case .failed, .cancelled:
            isReady = false
            if case .failed(let error) = state {
                Self.logger.error(
                    "Connection failed endpoint=\(String(describing: self.connection.endpoint), privacy: .public) error=\(error.localizedDescription, privacy: .public) reason=\(String(describing: self.connection.currentPath?.unsatisfiedReason), privacy: .public)"
                )
            }
            messageContinuation?.finish()
        default:
            break
        }
    }

    private func waitForReady() async {
        // Wait up to 10 seconds for connection to be ready
        for _ in 0..<100 {
            if isReady { return }
            if let currentPath = connection.currentPath,
               currentPath.unsatisfiedReason == .localNetworkDenied {
                localNetworkDenied = true
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private nonisolated func receiveNextMessage() {
        connection.receiveMessage { [weak self] content, context, isComplete, error in
            guard let self = self else { return }

            if let content, !content.isEmpty,
               let message = try? JSONDecoder().decode(ClusterMessage.self, from: content) {
                Task { await self.deliverMessage(message) }
            }

            if self.shouldContinueReceiving(content: content, isComplete: isComplete, error: error) {
                self.receiveNextMessage()
            } else if error != nil || isComplete {
                Task { await self.cancel() }
            }
        }
    }

    private func deliverMessage(_ message: ClusterMessage) {
        messageContinuation?.yield(message)
    }
}
