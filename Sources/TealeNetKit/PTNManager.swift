import Foundation
import CryptoKit
import SharedTypes

// MARK: - PTN Manager

/// Top-level PTN coordinator. Manages memberships, handles create/join/invite flows.
@Observable
public final class PTNManager: @unchecked Sendable {
    public private(set) var memberships: [PTNMembershipInfo] = []

    private let store = PTNStore()

    /// The local node's identity (Ed25519 public key hex).
    public let localNodeID: String
    public let localDisplayName: String

    /// Pending join requests from other nodes (inviter side).
    public private(set) var pendingJoinRequests: [PTNJoinRequestPayload] = []

    public init(localNodeID: String, localDisplayName: String) {
        self.localNodeID = localNodeID
        self.localDisplayName = localDisplayName
    }

    /// Load all persisted PTN memberships on startup.
    public func loadMemberships() async {
        do {
            memberships = try await store.loadAll()
        } catch {
            FileHandle.standardError.write(Data("[PTN] Failed to load memberships: \(error.localizedDescription)\n".utf8))
        }
    }

    /// Active PTN identifiers for broadcasting in WAN capabilities.
    public var activePTNIDs: [PTNIdentifier] {
        memberships.filter(\.isCertificateValid).map(\.identifier)
    }

    // MARK: - Create PTN

    /// Create a new PTN. This device becomes the admin and holds the CA private key.
    public func createPTN(name: String) async throws -> PTNMembershipInfo {
        let ca = PTNCertificateAuthority()

        // Self-sign an admin certificate for the creator
        let certificate = try ca.issueCertificate(
            nodeID: localNodeID,
            role: .admin,
            issuerNodeID: localNodeID
        )

        let membership = PTNMembershipInfo(
            ptnID: ca.ptnID,
            ptnName: name,
            caPublicKeyHex: ca.ptnID,
            certificate: certificate,
            role: .admin,
            isCreator: true
        )

        // Persist membership and CA key
        try await store.save(membership)
        try await store.saveCAKey(ca.privateKeyData, ptnID: ca.ptnID)

        memberships.append(membership)
        return membership
    }

    // MARK: - Generate Invite

    /// Generate an invite code for a PTN this device administers.
    public func generateInviteToken(ptnID: String, validForSeconds: TimeInterval = 3600) throws -> String {
        guard let membership = memberships.first(where: { $0.ptnID == ptnID }) else {
            throw PTNError.ptnNotFound
        }
        guard membership.role == .admin else {
            throw PTNError.notPTNAdmin
        }

        let token = PTNInviteToken(
            ptnID: ptnID,
            ptnName: membership.ptnName,
            inviterNodeID: localNodeID,
            validForSeconds: validForSeconds
        )
        return try token.encode()
    }

    // MARK: - Handle Join Request (inviter side)

    /// Process a join request from a remote node. Called when a PTNJoinRequestPayload arrives.
    /// Returns the signed certificate to send back, or throws if rejected.
    public func handleJoinRequest(_ request: PTNJoinRequestPayload) async throws -> PTNJoinResponsePayload {
        let ptnID = request.inviteToken.ptnID

        guard let membership = memberships.first(where: { $0.ptnID == ptnID }) else {
            throw PTNError.ptnNotFound
        }
        guard membership.role == .admin || membership.isCreator else {
            throw PTNError.notPTNAdmin
        }

        // Load CA key to sign the certificate
        guard let caKeyData = try await store.loadCAKey(ptnID: ptnID) else {
            throw PTNError.caKeyNotFound
        }
        let ca = try PTNCertificateAuthority(privateKeyData: caKeyData)

        // Verify the invite token is for this PTN and not expired
        guard request.inviteToken.ptnID == ptnID, !request.inviteToken.isExpired else {
            throw PTNError.inviteExpired
        }

        // Issue certificate for the joiner
        let certificate = try ca.issueCertificate(
            nodeID: request.joinerNodeID,
            role: .provider,  // Default role for new members
            issuerNodeID: localNodeID
        )

        return PTNJoinResponsePayload(
            certificate: certificate,
            ptnName: membership.ptnName,
            caPublicKeyHex: membership.caPublicKeyHex
        )
    }

    // MARK: - Join PTN (joiner side, after receiving response)

    /// Complete the join flow after receiving a signed certificate from the inviter.
    public func completeJoin(response: PTNJoinResponsePayload) async throws -> PTNMembershipInfo {
        // Verify the certificate
        guard response.accepted else {
            throw PTNError.joinRejected
        }
        guard response.certificate.verify(caPublicKeyHex: response.caPublicKeyHex) else {
            throw PTNError.certificateVerificationFailed
        }
        guard response.certificate.payload.nodeID == localNodeID else {
            throw PTNError.certificateVerificationFailed
        }

        let membership = PTNMembershipInfo(
            ptnID: response.certificate.payload.ptnID,
            ptnName: response.ptnName,
            caPublicKeyHex: response.caPublicKeyHex,
            certificate: response.certificate,
            role: response.certificate.payload.role,
            isCreator: false
        )

        try await store.save(membership)
        memberships.append(membership)
        return membership
    }

    // MARK: - Leave PTN

    /// Leave a PTN and delete local membership data.
    public func leavePTN(ptnID: String) async throws {
        try await store.delete(ptnID: ptnID)
        memberships.removeAll { $0.ptnID == ptnID }
    }

    // MARK: - Verification

    /// Verify a remote peer's PTN certificate.
    public func verifyCertificate(_ cert: PTNCertificate, forPTN ptnID: String) -> Bool {
        guard let membership = memberships.first(where: { $0.ptnID == ptnID }) else {
            return false
        }
        return cert.verify(caPublicKeyHex: membership.caPublicKeyHex) && cert.isValid
    }

    /// Get this device's certificate for a specific PTN (for sending to peers).
    public func certificateForPTN(_ ptnID: String) -> PTNCertificate? {
        memberships.first(where: { $0.ptnID == ptnID })?.certificate
    }

    /// Check if this device is a member of a PTN.
    public func isMember(of ptnID: String) -> Bool {
        memberships.contains { $0.ptnID == ptnID && $0.isCertificateValid }
    }
}
