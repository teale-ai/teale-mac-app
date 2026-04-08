import Foundation
import SharedTypes
import CreditKit

// MARK: - Contributor State

public enum ContributorState: Sendable {
    case idle
    case waitingForConsent
    case connecting
    case contributing(ContributionInfo)
    case paused(PauseReason)
    case error(String)
}

// MARK: - Contribution Info

public struct ContributionInfo: Sendable {
    public var connectedPeers: Int
    public var requestsServed: Int
    public var tokensGenerated: Int
    public var creditsEarned: CreditAmount
    public var currentModel: String?
    public var uptime: TimeInterval

    public init(
        connectedPeers: Int = 0,
        requestsServed: Int = 0,
        tokensGenerated: Int = 0,
        creditsEarned: CreditAmount = .zero,
        currentModel: String? = nil,
        uptime: TimeInterval = 0
    ) {
        self.connectedPeers = connectedPeers
        self.requestsServed = requestsServed
        self.tokensGenerated = tokensGenerated
        self.creditsEarned = creditsEarned
        self.currentModel = currentModel
        self.uptime = uptime
    }
}

// MARK: - Contribution Earnings

public struct ContributionEarnings: Sendable {
    public var totalCredits: CreditAmount
    public var todayCredits: CreditAmount
    public var requestsServed: Int
    public var tokensGenerated: Int

    public init(
        totalCredits: CreditAmount = .zero,
        todayCredits: CreditAmount = .zero,
        requestsServed: Int = 0,
        tokensGenerated: Int = 0
    ) {
        self.totalCredits = totalCredits
        self.todayCredits = todayCredits
        self.requestsServed = requestsServed
        self.tokensGenerated = tokensGenerated
    }
}
