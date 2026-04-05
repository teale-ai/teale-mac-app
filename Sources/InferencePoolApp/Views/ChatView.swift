import SwiftUI
import SharedTypes

struct ChatView: View {
    @Environment(AppState.self) private var appState
    @State private var store = ConversationStore()
    @State private var selectedConversation: Conversation?
    @State private var messageText: String = ""
    @State private var streamingText: String = ""
    @State private var isGenerating: Bool = false

    var body: some View {
        HSplitView {
            // Conversation list
            VStack(spacing: 0) {
                List(store.conversations, selection: $selectedConversation) { conversation in
                    Text(conversation.title)
                        .lineLimit(1)
                        .tag(conversation)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                store.deleteConversation(conversation)
                                if selectedConversation?.id == conversation.id {
                                    selectedConversation = nil
                                }
                            }
                        }
                }
                .listStyle(.sidebar)

                Divider()

                Button {
                    let conv = store.createConversation()
                    selectedConversation = conv
                } label: {
                    Label("New Chat", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(8)
            }
            .frame(minWidth: 120, maxWidth: 180)

            // Chat area
            VStack(spacing: 0) {
                if let conversation = selectedConversation {
                    // Messages
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(conversation.messages) { message in
                                    ChatBubbleView(role: message.role, content: message.content)
                                        .id(message.id)
                                }

                                if isGenerating && !streamingText.isEmpty {
                                    ChatBubbleView(role: "assistant", content: streamingText)
                                        .id("streaming")
                                }

                                if isGenerating && streamingText.isEmpty {
                                    HStack {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("Thinking...")
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal)
                                    .id("loading")
                                }
                            }
                            .padding()
                        }
                        .onChange(of: streamingText) {
                            withAnimation {
                                proxy.scrollTo("streaming", anchor: .bottom)
                            }
                        }
                    }

                    Divider()

                    // Input
                    HStack(spacing: 8) {
                        TextField("Type a message...", text: $messageText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...5)
                            .onSubmit { sendMessage() }

                        Button(action: sendMessage) {
                            Image(systemName: isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating)
                    }
                    .padding(12)
                } else {
                    ContentUnavailableView(
                        "No Chat Selected",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Select a conversation or create a new one")
                    )
                }
            }
        }
        .navigationTitle("Chat")
        .onAppear {
            if selectedConversation == nil, let first = store.conversations.first {
                selectedConversation = first
            }
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let conversation = selectedConversation else { return }
        guard !isGenerating else { return }

        let userText = messageText
        messageText = ""

        let _ = store.addMessage(to: conversation, role: "user", content: userText)

        if conversation.messages.count == 1 {
            conversation.title = String(userText.prefix(40))
        }

        Task {
            await generateResponse(for: conversation)
        }
    }

    private func generateResponse(for conversation: Conversation) async {
        guard await appState.engine.loadedModel != nil else {
            let _ = store.addMessage(to: conversation, role: "assistant", content: "No model loaded. Go to Models to download and load one.")
            return
        }

        isGenerating = true
        streamingText = ""

        let apiMessages = conversation.messages.map { msg in
            APIMessage(role: msg.role, content: msg.content)
        }

        let request = ChatCompletionRequest(messages: apiMessages, stream: true)
        let stream = appState.engine.generate(request: request)

        do {
            for try await chunk in stream {
                if let content = chunk.choices.first?.delta.content {
                    streamingText += content
                }
            }
            let _ = store.addMessage(to: conversation, role: "assistant", content: streamingText)
        } catch {
            let _ = store.addMessage(to: conversation, role: "assistant", content: "Error: \(error.localizedDescription)")
        }

        streamingText = ""
        isGenerating = false
    }
}

// MARK: - Chat Bubble

private struct ChatBubbleView: View {
    let role: String
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: role == "user" ? "person.circle.fill" : "brain.head.profile")
                .font(.title3)
                .foregroundStyle(role == "user" ? .blue : .purple)

            VStack(alignment: .leading, spacing: 4) {
                Text(role == "user" ? "You" : "Assistant")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(LocalizedStringKey(content))
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
