import Foundation

// MARK: - Conversation (in-memory for CLI build; SwiftData for Xcode build)

public final class Conversation: Identifiable, ObservableObject, Hashable {
    public let id: UUID
    @Published public var title: String
    @Published public var createdAt: Date
    @Published public var updatedAt: Date
    @Published public var messages: [Message]

    public init(title: String = "New Chat") {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.messages = []
    }

    public static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Message

public final class Message: Identifiable, ObservableObject {
    public let id: UUID
    public var role: String
    public var content: String
    public var timestamp: Date

    public init(role: String, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}
