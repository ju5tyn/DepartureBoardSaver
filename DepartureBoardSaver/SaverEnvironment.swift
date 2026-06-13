//
//  SaverEnvironment.swift
//  DepartureBoardSaver
//
//  Created by Justyn Henman on 11/06/2026.
//  Workarounds for post-Sonoma legacyScreenSaver bugs, ported from
//  https://github.com/AerialScreensaver/ScreenSaverMinimal
//

import Foundation
import AppKit
import Quartz
import os.log

enum SaverEnvironment {

    static let log = Logger(subsystem: "com.justynhenman.DepartureBoardSaver", category: "Saver")

    /// True when hosted by the system (legacyScreenSaver / System Settings),
    /// false when loaded by the DepartureBoardSaverTestHost app.
    static let isHostedBySystem: Bool =
        Bundle.main.bundleIdentifier?.hasPrefix("com.apple.") ?? false

    /// On Tahoe the isPreview flag passed to init is unreliable. A locked screen
    /// means we are the real screensaver; otherwise we're the Settings preview.
    static func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        return dict["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    /// Tahoe never kills preview instances; they should exit once System
    /// Settings is gone.
    static func isSystemSettingsRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.systempreferences"
                || $0.bundleIdentifier == "com.apple.Preferences"
        }
    }
}
