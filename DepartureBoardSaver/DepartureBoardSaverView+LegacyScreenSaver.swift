//
//  DepartureBoardSaverView+LegacyScreenSaver.swift
//  DepartureBoardSaver
//
//  Workarounds for post-Sonoma legacyScreenSaver bugs (see SaverEnvironment.swift).
//  Stored state for these lives in DepartureBoardSaverView itself, since Swift
//  extensions cannot add stored properties.
//

import ScreenSaver
import AppKit

extension DepartureBoardSaverView {

    /// Tahoe passes an unreliable isPreview under legacyScreenSaver: a locked
    /// screen means a real screensaver run, anything else is the Settings preview.
    static func resolveIsPreview(_ isPreview: Bool) -> Bool {
        guard SaverEnvironment.isHostedBySystem else { return isPreview }
        return !SaverEnvironment.isScreenLocked()
    }

    /// Tahoe also spawns zero-sized "ghost" preview instances that never draw.
    func detectGhostInstance(frame: NSRect) -> Bool {
        guard SaverEnvironment.isHostedBySystem && actualIsPreview && frame == .zero else {
            return false
        }
        SaverEnvironment.log.info("init: ghost instance detected - skipping setup")
        return true
    }

    // legacyScreenSaver never deallocates savers after dismissal (Sonoma+), so the
    // refresh task would keep polling the rail API in the background forever.
    // Listen for willStop and exit the hosting process instead.
    func registerWillStopObserverIfNeeded() {
        guard SaverEnvironment.isHostedBySystem && !actualIsPreview else { return }
        willStopObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screensaver.willstop"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue per the observer registration above.
            MainActor.assumeIsolated {
                self?.handleWillStopNotification()
            }
        }
    }

    func handleWillStopNotification() {
        guard !actualIsPreview else { return }
        SaverEnvironment.log.info("willStop received - exiting in 2 seconds")
        cancelRefresh()
        isAnimationStarted = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            exit(0)
        }
    }

    /// Tahoe never kills preview instances; exit once System Settings is gone
    /// so we don't keep polling the rail API from an invisible process.
    func exitPreviewIfSystemSettingsClosed(now: Date) {
        guard SaverEnvironment.isHostedBySystem && actualIsPreview,
              now.timeIntervalSince(lastSystemSettingsCheck) >= 1.0 else { return }
        lastSystemSettingsCheck = now
        if !SaverEnvironment.isSystemSettingsRunning() {
            SaverEnvironment.log.info("System Settings closed - exiting preview instance")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                exit(0)
            }
        }
    }
}
