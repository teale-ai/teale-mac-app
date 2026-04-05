import Foundation

// MARK: - Conversation Store (in-memory)

@MainActor
@Observable
public final class ConversationStore {
    public private(set) var conversations: [Conversation] = []

    public init() {}

    public func createConversation(title: String = "New Chat") -> Conversation {
        let conversation = Conversation(title: title)
        conversations.insert(conversation, at: 0)
        return conversation
    }

    public func deleteConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
    }

    public func addMessage(to conversation: Conversation, role: String, content: String) -> Message {
        let message = Message(role: role, content: content)
        conversation.messages.append(message)
        conversation.updatedAt = Date()
        // Move to top
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            let conv = conversations.remove(at: index)
            conversations.insert(conv, at: 0)
        }
        return message
    }
}
