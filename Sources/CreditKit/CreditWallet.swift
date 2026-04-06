import Foundation
import SharedTypes

// MARK: - CreditWallet

/// Observable wrapper around CreditLedger for SwiftUI binding.
@Observable
public final class CreditWallet: @unchecked Sendable {
    public private(set) var balance: CreditAmount = .zero
    public private(set) var recentTransactions: [CreditTransaction] = []
    public private(set) var totalEarned: CreditAmount = .zero
    public private(set) var totalSpent: CreditAmount = .zero

    private var ledger: CreditLedger?

    public init(ledger: CreditLedger) {
        self.ledger = ledger
    }

    /// Create a placeholder wallet (no ledger) for use before async init completes
    public static func placeholder() -> CreditWallet {
        let wallet = CreditWallet()
        return wallet
    }

    private init() {
        self.ledger = nil
    }

    /// Record an earning (we served inference for a peer).
    public func recordEarning(tokens: Int, model: ModelDescriptor, peer: String? = nil) async {
        guard let ledger = ledger else { return }
        let amount = CreditPricing.earning(tokenCount: tokens, model: model)
        let transaction = CreditTransaction(
            type: .earned,
            amount: amount,
            description: "Served \(tokens) tokens of \(model.name)",
            peerNodeID: peer,
            modelID: model.id,
            tokenCount: tokens
        )
        await ledger.credit(amount: amount, transaction: transaction)
        await refreshBalance()
    }

    /// Record spending (we consumed inference from a peer).
    public func recordSpending(tokens: Int, model: ModelDescriptor, peer: String? = nil) async {
        guard let ledger = ledger else { return }
        let amount = CreditPricing.cost(tokenCount: tokens, model: model)
        let transaction = CreditTransaction(
            type: .spent,
            amount: amount,
            description: "Used \(tokens) tokens of \(model.name)",
            peerNodeID: peer,
            modelID: model.id,
            tokenCount: tokens
        )
        await ledger.debit(amount: amount, transaction: transaction)
        await refreshBalance()
    }

    public func recordTransferDebit(
        amount: CreditAmount,
        toPeer peerNodeID: String,
        description: String,
        modelID: String? = nil,
        tokenCount: Int? = nil
    ) async {
        guard let ledger = ledger else { return }
        let transaction = CreditTransaction(
            type: .transfer,
            amount: amount,
            description: description,
            peerNodeID: peerNodeID,
            modelID: modelID,
            tokenCount: tokenCount
        )
        await ledger.debit(amount: amount, transaction: transaction)
        await refreshBalance()
    }

    public func recordTransferCredit(
        amount: CreditAmount,
        fromPeer peerNodeID: String,
        description: String,
        modelID: String? = nil,
        tokenCount: Int? = nil
    ) async {
        guard let ledger = ledger else { return }
        let transaction = CreditTransaction(
            type: .transfer,
            amount: amount,
            description: description,
            peerNodeID: peerNodeID,
            modelID: modelID,
            tokenCount: tokenCount
        )
        await ledger.credit(amount: amount, transaction: transaction)
        await refreshBalance()
    }

    public func recordAdjustmentCredit(
        amount: CreditAmount,
        description: String,
        peerNodeID: String? = nil,
        modelID: String? = nil,
        tokenCount: Int? = nil
    ) async {
        guard let ledger = ledger else { return }
        let transaction = CreditTransaction(
            type: .adjustment,
            amount: amount,
            description: description,
            peerNodeID: peerNodeID,
            modelID: modelID,
            tokenCount: tokenCount
        )
        await ledger.credit(amount: amount, transaction: transaction)
        await refreshBalance()
    }

    public func recordAdjustmentDebit(
        amount: CreditAmount,
        description: String,
        peerNodeID: String? = nil,
        modelID: String? = nil,
        tokenCount: Int? = nil
    ) async {
        guard let ledger = ledger else { return }
        let transaction = CreditTransaction(
            type: .adjustment,
            amount: amount,
            description: description,
            peerNodeID: peerNodeID,
            modelID: modelID,
            tokenCount: tokenCount
        )
        await ledger.debit(amount: amount, transaction: transaction)
        await refreshBalance()
    }

    /// Debit wallet for an outgoing P2P credit transfer. Returns true if balance was sufficient.
    public func sendTransfer(amount: Double, toPeer peerNodeID: String, memo: String? = nil) async -> Bool {
        guard let ledger = ledger else { return false }
        let creditAmount = CreditAmount(amount)
        let currentBal = await ledger.getBalance().currentBalance
        guard currentBal >= creditAmount else { return false }

        let desc = memo.map { "Sent \(String(format: "%.2f", amount)) credits: \($0)" }
            ?? "Sent \(String(format: "%.2f", amount)) credits"
        await recordTransferDebit(amount: creditAmount, toPeer: peerNodeID, description: desc)
        return true
    }

    /// Credit wallet for an incoming P2P credit transfer.
    public func receiveTransfer(amount: Double, fromPeer peerNodeID: String, memo: String? = nil) async {
        let creditAmount = CreditAmount(amount)
        let desc = memo.map { "Received \(String(format: "%.2f", amount)) credits: \($0)" }
            ?? "Received \(String(format: "%.2f", amount)) credits"
        await recordTransferCredit(amount: creditAmount, fromPeer: peerNodeID, description: desc)
    }

    /// Get current balance asynchronously (safe from any context).
    public func currentBalance() async -> CreditAmount {
        guard let ledger = ledger else { return .zero }
        return await ledger.getBalance().currentBalance
    }

    /// Refresh all published properties from the ledger.
    public func refreshBalance() async {
        guard let ledger = ledger else { return }
        let walletBalance = await ledger.getBalance()
        let recent = await ledger.getHistory(limit: 20)

        self.balance = walletBalance.currentBalance
        self.totalEarned = walletBalance.totalEarned
        self.totalSpent = walletBalance.totalSpent
        self.recentTransactions = recent
    }
}
