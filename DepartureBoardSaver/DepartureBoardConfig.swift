//
//  DepartureBoardConfig.swift
//  DepartureBoardSaver
//

import Foundation
import ScreenSaver

enum DisplayStyle: String {
    case oled       // amber text on black, nearest-neighbour scaled
    case lcd        // white text on dark navy
    case dotMatrix  // each pixel rendered as a physical LED dot with visible grid
}

struct DepartureBoardConfig {
    var apiKey: String
    var station: String
    var sidePaddingPct: Double  // 0–30, a percentage of screen width per side
    var displayStyle: DisplayStyle
    var showStationInClock: Bool
    var useMetalRendering: Bool  // GPU dot-matrix rendering (on by default)

    static let moduleName = "justynhenman.DepartureBoardSaver"

    static func load() -> DepartureBoardConfig {
        let defaults = ScreenSaverDefaults(forModuleWithName: moduleName) ?? ScreenSaverDefaults()
        // Migrate from the old lcdMode bool if no displayStyle key exists yet.
        let style: DisplayStyle
        if let raw = defaults.string(forKey: "displayStyle"), let s = DisplayStyle(rawValue: raw) {
            style = s
        } else {
            style = .dotMatrix
        }
        return DepartureBoardConfig(
            apiKey: defaults.string(forKey: "apiKey") ?? "",
            station: (defaults.string(forKey: "station") ?? "PAD").uppercased(),
            sidePaddingPct: defaults.double(forKey: "sidePaddingPct"),
            displayStyle: style,
            showStationInClock: defaults.object(forKey: "showStationInClock") as? Bool ?? true,
            useMetalRendering: defaults.object(forKey: "useMetalRendering") as? Bool ?? true
        )
    }

    func save() {
        let defaults = ScreenSaverDefaults(forModuleWithName: Self.moduleName) ?? ScreenSaverDefaults()
        defaults.set(apiKey, forKey: "apiKey")
        defaults.set(station.uppercased(), forKey: "station")
        defaults.set(sidePaddingPct, forKey: "sidePaddingPct")
        defaults.set(displayStyle.rawValue, forKey: "displayStyle")
        defaults.set(showStationInClock, forKey: "showStationInClock")
        defaults.set(useMetalRendering, forKey: "useMetalRendering")
        defaults.synchronize()
    }

    var isReady: Bool {
        station.count == 3
    }
}
