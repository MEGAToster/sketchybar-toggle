import Foundation

public enum BarState: Equatable {
    case visible
    case hidden
}

/// Pure state machine for coordinating menu bar and SketchyBar visibility.
/// Extracted from EventTapMonitor for testability.
public final class BarStateMachine {
    public private(set) var state: BarState = .visible

    public let triggerZone: CGFloat
    public let menuBarHeight: CGFloat
    /// Height of the real macOS menu bar strip, in pixels from the top of the
    /// screen. Clicks inside it belong to the native menu bar, not to any window
    /// underneath. Distinct from `menuBarHeight`, which is the (deliberately
    /// larger) hysteresis threshold for un-hiding.
    public let nativeMenuBarHeight: CGFloat
    public let debounceInterval: TimeInterval
    /// How long an open popup menu may persist (with the cursor below the
    /// menu-bar zone) before it is treated as stale — e.g. a ghost/lingering
    /// window — and SketchyBar is shown anyway. Guards against the bar getting
    /// permanently stuck hidden. Defaults to 15 seconds.
    public let staleMenuTimeout: TimeInterval

    private let controller: BarController
    private let isMenuOpen: () -> Bool
    private var debounceTimer: DispatchSourceTimer?
    private let timerQueue: DispatchQueue
    /// When the currently-open menu was first observed (nil if none open).
    private var menuOpenSince: TimeInterval?

    public init(
        controller: BarController,
        triggerZone: CGFloat = 10,
        menuBarHeight: CGFloat = 50,
        nativeMenuBarHeight: CGFloat = 24,
        debounceInterval: TimeInterval = 0.15,
        staleMenuTimeout: TimeInterval = 15,
        timerQueue: DispatchQueue = .main,
        isMenuOpen: @escaping () -> Bool = { false }
    ) {
        self.controller = controller
        self.triggerZone = triggerZone
        self.menuBarHeight = menuBarHeight
        self.nativeMenuBarHeight = nativeMenuBarHeight
        self.debounceInterval = debounceInterval
        self.staleMenuTimeout = staleMenuTimeout
        self.timerQueue = timerQueue
        self.isMenuOpen = isMenuOpen
    }

    /// Process a mouse position update. `distanceFromTop` is the distance in pixels
    /// from the mouse cursor to the top edge of the current screen. `now` is the
    /// current time (seconds since reference date); injectable for tests.
    public func handleMousePosition(
        distanceFromTop: CGFloat,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) {
        switch state {
        case .visible:
            if distanceFromTop < triggerZone {
                state = .hidden
                menuOpenSince = nil
                cancelDebounce()
                controller.hide()
            }

        case .hidden:
            // Still inside the menu-bar zone: the native menu bar may be in use,
            // so never start (or keep) a debounce here.
            guard distanceFromTop > menuBarHeight else {
                menuOpenSince = nil
                cancelDebounce()
                return
            }

            if isMenuOpen() {
                // A menu (or something that looks like one) is up. Record when it
                // was first seen so we can detect a stale/ghost window below.
                if menuOpenSince == nil { menuOpenSince = now }
                if let since = menuOpenSince, now - since >= staleMenuTimeout {
                    // The "menu" has outlived any realistic interaction while the
                    // cursor is well below the menu bar — treat it as stale and
                    // let SketchyBar come back rather than staying hidden forever.
                    menuOpenSince = nil
                    startDebounce()
                } else {
                    cancelDebounce()
                }
            } else {
                menuOpenSince = nil
                startDebounce()
            }
        }
    }

    /// Process a mouse click while in the hidden state.
    /// If the click is outside the trigger zone, immediately restore SketchyBar
    /// so that window title bars near the top of the screen remain interactive.
    ///
    /// Two exceptions keep SketchyBar out of the way of the native menu bar:
    /// a click inside the real menu bar strip is menu bar interaction (there is
    /// no window title bar to reach there — the menu bar overlay is on top), and
    /// a click while a popup menu is open would slide SketchyBar over that menu.
    public func handleMouseClick(distanceFromTop: CGFloat) {
        guard state == .hidden, distanceFromTop >= triggerZone else { return }
        guard distanceFromTop >= nativeMenuBarHeight else { return }
        guard !isMenuOpen() else { return }
        cancelDebounce()
        menuOpenSince = nil
        state = .visible
        controller.show()
    }

    /// Force a transition to visible. Used on startup/shutdown to restore SketchyBar.
    public func forceVisible() {
        cancelDebounce()
        menuOpenSince = nil
        state = .visible
        controller.show()
    }

    public var hasPendingDebounce: Bool {
        debounceTimer != nil
    }

    // MARK: - Debounce

    private func startDebounce() {
        guard debounceTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + debounceInterval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.state = .visible
            self.controller.show()
            self.debounceTimer = nil
        }
        debounceTimer = timer
        timer.resume()
    }

    private func cancelDebounce() {
        debounceTimer?.cancel()
        debounceTimer = nil
    }
}
