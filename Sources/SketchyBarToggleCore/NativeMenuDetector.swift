import CoreGraphics
import Foundation

/// Detects whether a native macOS popup menu (e.g. an open NSMenu from a menu
/// bar item) is currently on screen, without holding a continuous timer.
///
/// The underlying query (`CGWindowListCopyWindowInfo` → WindowServer IPC) is
/// relatively expensive, so results are cached and re-queried at most every
/// `pollInterval` (default 10 Hz). Reads within the interval return the cached
/// value, keeping per-tick cost negligible.
public final class NativeMenuDetector {
    /// Maximum rate at which the WindowServer is actually queried (seconds).
    public let pollInterval: TimeInterval

    private var lastCheck: TimeInterval = 0
    private var cachedOpen = false

    public init(pollInterval: TimeInterval = 0.1) {
        self.pollInterval = pollInterval
    }

    /// Returns `true` if a popup menu is currently open. Cached; the underlying
    /// query runs at most once per `pollInterval`.
    public func isMenuOpen() -> Bool {
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastCheck >= pollInterval else {
            return cachedOpen
        }
        lastCheck = now
        cachedOpen = queryMenuOpen()
        return cachedOpen
    }

    /// Runs the actual WindowServer query for any window at the popup-menu level.
    /// Fails safe (returns `false`) on any cast/deserialization failure so a bad
    /// window entry never keeps SketchyBar hidden.
    private func queryMenuOpen() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }
        let popUpMenuLevel = CGWindowLevelForKey(.popUpMenuWindow)
        return windows.contains { dict in
            guard let layer = dict[kCGWindowLayer as String] as? NSNumber else {
                return false
            }
            return layer.int32Value == popUpMenuLevel
        }
    }
}
