import Foundation
import CryptoKit

// MARK: - Cluster Security

public struct ClusterSecurity: Sendable {
    /// Hash a passcode for comparison during handshake
    public static func hashPasscode(_ passcode: String) -> String {
        let data = Data(passcode.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Validate that two passcode hashes match
    public static func validatePasscode(local: String?, remote: String?) -> Bool {
        switch (local, remote) {
        case (nil, nil):
            return true  // No passcode required
        case (let l?, let r?):
            return l == r  // Both have passcode, must match
        default:
            return false  // One has passcode, other doesn't
        }
    }
}
