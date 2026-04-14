import SwiftUI
import AppCore
import SharedTypes
import TealeNetKit

struct PTNSettingsSection: View {
    @Environment(AppState.self) private var appState
    @State private var newPTNName = ""
    @State private var joinCode = ""
    @State private var showInviteCode: String?
    @State private var error: String?
    @State private var isCreating = false
    @State private var isJoining = false

    var body: some View {
        // Existing memberships
        if !appState.ptnManager.memberships.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your TealeNets")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(appState.ptnManager.memberships) { membership in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(membership.ptnName)
                                    .font(.body.weight(.medium))
                                roleBadge(membership.role)
                            }
                            Text(membership.ptnID.prefix(16) + "...")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                        }

                        Spacer()

                        if membership.role == .admin {
                            Button("Invite") {
                                generateInvite(ptnID: membership.ptnID)
                            }
                            .controlSize(.small)
                        }

                        Button("Leave") {
                            Task {
                                try? await appState.ptnManager.leavePTN(ptnID: membership.ptnID)
                            }
                        }
                        .controlSize(.small)
                        .foregroundStyle(.red)
                    }
                    .padding(.vertical, 2)
                }
            }
        }

        // Show invite code if generated
        if let code = showInviteCode {
            VStack(alignment: .leading, spacing: 4) {
                Text("Invite Code (share with the person joining)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                }
                .controlSize(.small)
            }
        }

        // Create new PTN
        HStack {
            TextField("New TealeNet name", text: $newPTNName)
                .textFieldStyle(.roundedBorder)
            Button("Create") {
                createPTN()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(newPTNName.isEmpty || isCreating)
        }

        // Join existing PTN
        HStack {
            TextField("Paste invite code", text: $joinCode)
                .textFieldStyle(.roundedBorder)
            Button("Join") {
                joinPTN()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(joinCode.isEmpty || isJoining)
        }

        if let error {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }

        Text("Private TealeNets let trusted devices form a private inference network with custom pricing and priority routing.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private func roleBadge(_ role: PTNRole) -> some View {
        let (text, color): (String, Color) = {
            switch role {
            case .admin: return ("ADMIN", .orange)
            case .provider: return ("PROVIDER", .blue)
            case .consumer: return ("CONSUMER", .green)
            }
        }()
        return Text(text)
            .font(.caption2.weight(.medium))
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func createPTN() {
        isCreating = true
        error = nil
        Task {
            do {
                let membership = try await appState.ptnManager.createPTN(name: newPTNName)
                newPTNName = ""
                // Auto-generate invite code for the new PTN
                showInviteCode = try appState.ptnManager.generateInviteToken(ptnID: membership.ptnID)
            } catch {
                self.error = error.localizedDescription
            }
            isCreating = false
        }
    }

    private func joinPTN() {
        isJoining = true
        error = nil
        Task {
            do {
                let token = try PTNInviteToken.decode(from: joinCode)
                // For now, complete join locally (full relay exchange is Phase 2)
                // This validates the invite code format
                _ = token
                self.error = "Invite code valid for \"\(token.ptnName)\". Relay-based join exchange coming soon."
            } catch {
                self.error = error.localizedDescription
            }
            isJoining = false
            joinCode = ""
        }
    }

    private func generateInvite(ptnID: String) {
        do {
            showInviteCode = try appState.ptnManager.generateInviteToken(ptnID: ptnID)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
