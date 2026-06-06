//
//  ConfigureSheetController.swift
//  DepartureBoardSaver
//

import AppKit

@MainActor
final class ConfigureSheetController: NSObject {

    private(set) lazy var window: NSWindow = makeWindow()
    private let apiKeyField = NSSecureTextField(frame: .zero)
    private let stationField = NSTextField(frame: .zero)
    private let paddingSlider = NSSlider(frame: .zero)
    private let paddingValueLabel = NSTextField(labelWithString: "0%")
    private let styleControl = NSSegmentedControl(
        labels: ["Dot Matrix", "OLED", "LCD"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let showStationCheckbox = NSButton(checkboxWithTitle: "Show station code in clock corner", target: nil, action: nil)
    private let useMetalCheckbox = NSButton(checkboxWithTitle: "Use GPU (Metal) rendering for Dot Matrix mode", target: nil, action: nil)
    private var onSave: ((DepartureBoardConfig) -> Void)?

    func present(onSave: @escaping (DepartureBoardConfig) -> Void) {
        self.onSave = onSave
        let cfg = DepartureBoardConfig.load()
        apiKeyField.stringValue = cfg.apiKey
        stationField.stringValue = cfg.station
        paddingSlider.doubleValue = cfg.sidePaddingPct
        paddingValueLabel.stringValue = "\(Int(cfg.sidePaddingPct))%"
        switch cfg.displayStyle {
        case .dotMatrix: styleControl.selectedSegment = 0
        case .oled:      styleControl.selectedSegment = 1
        case .lcd:       styleControl.selectedSegment = 2
        }
        showStationCheckbox.state = cfg.showStationInClock ? .on : .off
        useMetalCheckbox.state = cfg.useMetalRendering ? .on : .off
    }

    private func makeWindow() -> NSWindow {
        let contentSize = NSSize(width: 460, height: 354)
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "DepartureBoard"
        win.isReleasedWhenClosed = false

        let content = NSView(frame: NSRect(origin: .zero, size: contentSize))
        win.contentView = content

        let title = NSTextField(labelWithString: "Departure Board Settings")
        title.font = NSFont.boldSystemFont(ofSize: 14)
        title.frame = NSRect(x: 20, y: 314, width: 420, height: 20)
        content.addSubview(title)

        let apiLabel = NSTextField(labelWithString: "OpenLDBWS API key:")
        apiLabel.frame = NSRect(x: 20, y: 274, width: 160, height: 20)
        content.addSubview(apiLabel)

        apiKeyField.frame = NSRect(x: 180, y: 272, width: 260, height: 22)
        apiKeyField.placeholderString = "Token from National Rail OpenLDBWS"
        content.addSubview(apiKeyField)

        let stationLabel = NSTextField(labelWithString: "Station CRS code:")
        stationLabel.frame = NSRect(x: 20, y: 234, width: 160, height: 20)
        content.addSubview(stationLabel)

        stationField.frame = NSRect(x: 180, y: 232, width: 80, height: 22)
        stationField.placeholderString = "PAD"
        content.addSubview(stationField)

        let hint = NSTextField(labelWithString: "Three-letter code such as PAD, KGX, EDB")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 20, y: 206, width: 420, height: 16)
        content.addSubview(hint)

        let paddingLabel = NSTextField(labelWithString: "Side padding:")
        paddingLabel.frame = NSRect(x: 20, y: 172, width: 110, height: 20)
        content.addSubview(paddingLabel)

        paddingSlider.minValue = 0
        paddingSlider.maxValue = 30
        paddingSlider.numberOfTickMarks = 7
        paddingSlider.allowsTickMarkValuesOnly = false
        paddingSlider.target = self
        paddingSlider.action = #selector(paddingSliderChanged(_:))
        paddingSlider.frame = NSRect(x: 135, y: 172, width: 220, height: 20)
        content.addSubview(paddingSlider)

        paddingValueLabel.frame = NSRect(x: 362, y: 172, width: 50, height: 20)
        paddingValueLabel.alignment = .right
        content.addSubview(paddingValueLabel)

        let paddingHint = NSTextField(labelWithString: "Black margin on each side of the board (0–30% of screen width).")
        paddingHint.font = NSFont.systemFont(ofSize: 11)
        paddingHint.textColor = .secondaryLabelColor
        paddingHint.frame = NSRect(x: 20, y: 152, width: 420, height: 16)
        content.addSubview(paddingHint)

        let styleLabel = NSTextField(labelWithString: "Display style:")
        styleLabel.frame = NSRect(x: 20, y: 118, width: 105, height: 20)
        content.addSubview(styleLabel)

        styleControl.frame = NSRect(x: 130, y: 114, width: 310, height: 26)
        content.addSubview(styleControl)

        let styleHint = NSTextField(labelWithString: "OLED: amber pixels - LCD: white on dark blue - Dot Matrix: visible LED grid")
        styleHint.font = NSFont.systemFont(ofSize: 11)
        styleHint.textColor = .secondaryLabelColor
        styleHint.frame = NSRect(x: 20, y: 94, width: 420, height: 16)
        content.addSubview(styleHint)

        showStationCheckbox.frame = NSRect(x: 20, y: 68, width: 340, height: 18)
        content.addSubview(showStationCheckbox)

        useMetalCheckbox.frame = NSRect(x: 20, y: 44, width: 420, height: 18)
        content.addSubview(useMetalCheckbox)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded
        cancel.frame = NSRect(x: 260, y: 8, width: 80, height: 32)
        content.addSubview(cancel)

        let save = NSButton(title: "Save", target: self, action: #selector(save))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.frame = NSRect(x: 360, y: 8, width: 80, height: 32)
        content.addSubview(save)

        return win
    }

    @objc private func paddingSliderChanged(_ sender: NSSlider) {
        paddingValueLabel.stringValue = "\(Int(sender.doubleValue))%"
    }

    @objc private func save() {
        var cfg = DepartureBoardConfig.load()
        cfg.apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespaces)
        cfg.station = stationField.stringValue.trimmingCharacters(in: .whitespaces).uppercased()
        cfg.sidePaddingPct = paddingSlider.doubleValue
        switch styleControl.selectedSegment {
        case 1:  cfg.displayStyle = .oled
        case 2:  cfg.displayStyle = .lcd
        default: cfg.displayStyle = .dotMatrix
        }
        cfg.showStationInClock = showStationCheckbox.state == .on
        cfg.useMetalRendering  = useMetalCheckbox.state == .on
        cfg.save()
        onSave?(cfg)
        endSheet()
    }

    @objc private func cancel() {
        endSheet()
    }

    private func endSheet() {
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.endSheet(window)
        }
    }
}
