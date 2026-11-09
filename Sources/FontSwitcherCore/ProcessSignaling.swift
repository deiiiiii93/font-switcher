import AppKit

/// Sends a reload signal to running instances of an app (kitty: SIGUSR1, Ghostty: SIGUSR2).
public protocol ProcessSignaling: Sendable {
    func signal(bundleID: String, signal: Int32)
}

public struct RunningAppSignaler: ProcessSignaling {
    public init() {}

    public func signal(bundleID: String, signal: Int32) {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            let pid = app.processIdentifier
            if pid > 0 { kill(pid, signal) }
        }
    }
}
