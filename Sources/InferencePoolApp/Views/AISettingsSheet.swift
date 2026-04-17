import SwiftUI
import ChatKit

struct AISettingsSheet: View {
    let conversation: Conversation
    let chatService: ChatService

    @Environment(\.dismiss) private var dismiss
    @State private var autoRespond: Bool
    @State private var mentionOnly: Bool
    @State private var systemPrompt: String
    @State private var title: String

    init(conversation: Conversation, chatService: ChatService) {
        self.conversation = conversation
        self.chatService = chatService
        _autoRespond = State(initialValue: conversation.agentConfig.autoRespond)
        _mentionOnly = State(initialValue: conversation.agentConfig.mentionOnly)
        _systemPrompt = State(initialValue: conversation.agentConfig.systemPrompt ?? "")
        _title = State(initialValue: conversation.title ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI Settings")
                .font(.title2.weight(.semibold))

            Form {
                Section("Conversation") {
                    TextField("Title", text: $title)
                }

                Section("AI Behavior") {
                    Toggle("Auto-respond to every message", isOn: $autoRespond)
                        .onChange(of: autoRespond) { _, newValue in
                            if newValue { mentionOnly = false }
                        }
                    Toggle("Only respond when @mentioned", isOn: $mentionOnly)
                        .onChange(of: mentionOnly) { _, newValue in
                            if newValue { autoRespond = false }
                        }
                        .help("@teale or @agent triggers a response.")
                }

                Section("Custom System Prompt (optional)") {
                    TextEditor(text: $systemPrompt)
                        .frame(minHeight: 80)
                        .font(.callout)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 460)
    }

    private func save() {
        let newConfig = AgentConfig(
            model: conversation.agentConfig.model,
            systemPrompt: systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : systemPrompt,
            autoRespond: autoRespond,
            mentionOnly: mentionOnly,
            persona: conversation.agentConfig.persona
        )
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            await chatService.updateConversation(
                id: conversation.id,
                title: newTitle.isEmpty ? nil : newTitle,
                agentConfig: newConfig
            )
            dismiss()
        }
    }
}
