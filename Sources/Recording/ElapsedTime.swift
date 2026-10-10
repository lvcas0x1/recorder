import Foundation

/// Recorded time of a session: finished segments plus the segment currently being written. Paused time is excluded.
public struct ElapsedTime: Equatable {
    /// Total length of the finished segments, in seconds.
    public private(set) var completed: TimeInterval = 0
    /// When the current segment started; `nil` while paused or stopped.
    public private(set) var runningSince: Date?

    public init() {}

    public var isRunning: Bool { runningSince != nil }

    public mutating func resume(at date: Date) {
        guard runningSince == nil else { return }
        runningSince = date
    }

    /// Ends the current segment. `measured` is the segment's recorded duration when known; otherwise the wall-clock
    /// time since `resume` is used.
    public mutating func pause(at date: Date, measured: TimeInterval? = nil) {
        guard let start = runningSince else { return }
        completed += measured ?? max(0, date.timeIntervalSince(start))
        runningSince = nil
    }

    public func value(at date: Date) -> TimeInterval {
        completed + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    /// `mm:ss`, with minutes growing past 99 when needed.
    public static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
