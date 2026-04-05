import Foundation
import SharedTypes
import HardwareProfile

// MARK: - Adaptive Throttler

@Observable
public final class AdaptiveThrottler: @unchecked Sendable {
    public let thermalMonitor: ThermalMonitor
    public let powerMonitor: PowerMonitor
    public let activityMonitor: UserActivityMonitor
    public let networkMonitor: NetworkMonitor

    public private(set) var throttleLevel: ThrottleLevel = .full
    public private(set) var pauseReason: PauseReason?

    private var timer: Timer?

    public init() {
        self.thermalMonitor = ThermalMonitor()
        self.powerMonitor = PowerMonitor()
        self.activityMonitor = UserActivityMonitor()
        self.networkMonitor = NetworkMonitor()
        startMonitoring()
    }

    deinit {
        timer?.invalidate()
    }

    private func startMonitoring() {
        evaluate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
    }

    /// Evaluate conditions and determine throttle level
    public func evaluate() {
        let thermal = thermalMonitor.thermalLevel
        let power = powerMonitor.powerState
        let isIdle = !activityMonitor.isUserActive

        // Hard stops
        if power.isLowPowerMode {
            throttleLevel = .paused
            pauseReason = .lowPowerMode
            return
        }

        if thermal == .critical {
            throttleLevel = .paused
            pauseReason = .thermal
            return
        }

        if !power.isOnACPower {
            if let battery = power.batteryLevel, battery < 0.1 {
                throttleLevel = .paused
                pauseReason = .battery
                return
            }
        }

        // Graduated throttling
        pauseReason = nil

        if thermal == .serious {
            throttleLevel = .minimal
            return
        }

        if !power.isOnACPower {
            if let battery = power.batteryLevel, battery < 0.25 {
                throttleLevel = .minimal
                return
            }
            throttleLevel = .reduced
            return
        }

        if thermal == .fair {
            throttleLevel = .reduced
            return
        }

        // For contribution (Phase 2+): reduce when user is active
        // For local use: always allow full since user is actively requesting
        throttleLevel = .full
    }

    /// Whether inference should proceed right now
    public var shouldAllowInference: Bool {
        throttleLevel > .paused
    }
}
