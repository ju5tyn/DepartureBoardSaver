//
//  ConfigureSheetController.swift
//  DepartureBoardSaver
//

import AppKit

@MainActor
final class ConfigureSheetController: NSObject {

    private(set) lazy var window: NSWindow = makeWindow()

    // Data tab
    private let apiKeyField = NSSecureTextField(frame: .zero)
    private let stationCombo = NSComboBox(frame: .zero)
    private var filteredStations: [StationEntry] = []

    // Display tab
    private let paddingSlider = NSSlider(frame: .zero)
    private let paddingValueLabel = NSTextField(labelWithString: "0%")
    private let styleControl = NSSegmentedControl(
        labels: ["Dot Matrix", "OLED", "LCD"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let showStationCheckbox = NSButton(
        checkboxWithTitle: "Show station code in clock corner",
        target: nil, action: nil
    )
    private let useMetalCheckbox = NSButton(
        checkboxWithTitle: "Use GPU (Metal) rendering for Dot Matrix mode",
        target: nil, action: nil
    )

    private var advancedContainer: NSView?
    private var advancedChevronView: NSImageView?

    private var dataAdvancedContainer: NSView?
    private var dataAdvancedChevronView: NSImageView?

    private var onSave: ((DepartureBoardConfig) -> Void)?

    func present(onSave: @escaping (DepartureBoardConfig) -> Void) {
        _ = window  // ensure makeWindow() has run so slider min/max are set before assigning doubleValue
        self.onSave = onSave
        let cfg = DepartureBoardConfig.load()
        apiKeyField.stringValue = cfg.apiKey
        if let entry = StationSearch.shared.entry(forCRS: cfg.station) {
            filteredStations = [entry]
            stationCombo.stringValue = entry.name
        } else {
            filteredStations = []
            stationCombo.stringValue = cfg.station
        }
        stationCombo.reloadData()
        paddingSlider.doubleValue = cfg.sidePaddingPct
        paddingValueLabel.stringValue = "\(Int(cfg.sidePaddingPct))%"
        switch cfg.displayStyle {
        case .dotMatrix: styleControl.selectedSegment = 0
        case .oled:      styleControl.selectedSegment = 1
        case .lcd:       styleControl.selectedSegment = 2
        }
        showStationCheckbox.state = cfg.showStationInClock ? .on : .off
        useMetalCheckbox.state    = cfg.useMetalRendering  ? .on : .off
    }

    // MARK: - Window construction

    private func makeWindow() -> NSWindow {
        let W: CGFloat = 480
        let H: CGFloat = 360

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: W, height: H)),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "DepartureBoardSaver Options"
        win.isReleasedWhenClosed = false

        let root = NSView(frame: NSRect(origin: .zero, size: NSSize(width: W, height: H)))
        win.contentView = root

        // Title strip at top
        let titleLabel = NSTextField(labelWithString: "DepartureBoardSaver Options")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 0, y: H - 37, width: W, height: 30) // Fake window title
        root.addSubview(titleLabel)

        let titleSep = NSBox(frame: NSRect(x: 0, y: H - 31, width: W, height: 1))
        titleSep.boxType = .separator
        root.addSubview(titleSep)

        // Bottom bar — Support always visible, Cancel + Save at right
        let koFi = NSButton(title: "", target: self, action: #selector(openKoFi))
        koFi.bezelStyle = .push
        koFi.bezelColor = .systemRed
        koFi.attributedTitle = NSAttributedString(
            string: "♥ Support",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13, weight: .medium)
            ]
        )
        koFi.frame = NSRect(x: 16, y: 10, width: 105, height: 30)
        root.addSubview(koFi)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        cancel.bezelStyle = .rounded
        cancel.frame = NSRect(x: W - 200, y: 10, width: 85, height: 30)
        root.addSubview(cancel)

        let save = NSButton(title: "Save", target: self, action: #selector(saveAction))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.frame = NSRect(x: W - 105, y: 10, width: 85, height: 30)
        root.addSubview(save)

        let sep = NSBox(frame: NSRect(x: 0, y: 50, width: W, height: 1))
        sep.boxType = .separator
        root.addSubview(sep)

        // Tab view fills the space between the bottom bar and title strip
        let tabView = NSTabView(frame: NSRect(x: 0, y: 51, width: W, height: H - 51 - 31))
        root.addSubview(tabView)

        let cs = tabView.contentRect.size  // actual content area inside the bezel

        let dataItem = NSTabViewItem(identifier: "data")
        dataItem.label = "Data"
        dataItem.view = buildDataTab(cs)
        tabView.addTabViewItem(dataItem)

        let displayItem = NSTabViewItem(identifier: "display")
        displayItem.label = "Display"
        displayItem.view = buildDisplayTab(cs)
        tabView.addTabViewItem(displayItem)

        return win
    }

    // MARK: - Tab content builders

    private func buildDataTab(_ size: NSSize) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        let h = size.height
        let lx: CGFloat = 16
        let rx: CGFloat = 16
        let rw = size.width - lx - rx
        let labelW: CGFloat = 80
        let fx = lx + labelW + 8

        // Station row (primary)
        var ty = h - 20 - 22
        view.addSubview(label("Station:", width: labelW, x: lx, y: ty))
        stationCombo.frame = NSRect(x: fx, y: ty, width: rw - labelW - 8, height: 22)
        stationCombo.placeholderString = "Search by name or CRS code…"
        stationCombo.usesDataSource = true
        stationCombo.dataSource = self
        stationCombo.delegate = self
        stationCombo.numberOfVisibleItems = 8
        stationCombo.completes = false
        view.addSubview(stationCombo)

        ty -= 8 + 14
        view.addSubview(smallLabel(
            "Type a station name or 3-letter code — e.g. \"Paddington\" or \"PAD\"",
            x: lx, y: ty, width: rw
        ))

        // Advanced disclosure
        ty -= 16 + 18
        let disclosureRow = NSView(frame: NSRect(x: 0, y: ty, width: size.width, height: 18))
        disclosureRow.alphaValue = 0.55
        disclosureRow.addGestureRecognizer(
            NSClickGestureRecognizer(target: self, action: #selector(toggleDataAdvanced))
        )
        view.addSubview(disclosureRow)

        let dataChevron = NSImageView(frame: NSRect(x: lx, y: 3, width: 12, height: 12))
        dataChevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        dataChevron.imageScaling = .scaleNone
        dataChevron.imageAlignment = .alignCenter
        dataChevron.contentTintColor = .labelColor
        disclosureRow.addSubview(dataChevron)
        dataAdvancedChevronView = dataChevron

        let advLabel = NSTextField(labelWithString: "Advanced options")
        advLabel.font = NSFont.systemFont(ofSize: 12)
        advLabel.frame = NSRect(x: lx + 16, y: 1, width: 200, height: 16)
        disclosureRow.addSubview(advLabel)

        // Advanced container — API key (hidden by default)
        // Contents: API key row (22) + gap (4) + hint (14) = 40
        let advH: CGFloat = 40
        ty -= 10 + advH
        let dataContainer = NSView(frame: NSRect(x: 0, y: ty, width: size.width, height: advH))
        dataContainer.isHidden = true
        view.addSubview(dataContainer)
        dataAdvancedContainer = dataContainer

        let apiY: CGFloat = advH - 22
        dataContainer.addSubview(label("API key:", width: labelW, x: lx, y: apiY))

        let getApiKeyButton = NSButton(title: "Get free key ↗", target: self, action: #selector(openAPIKeyPage))
        getApiKeyButton.bezelStyle = .glass
        getApiKeyButton.controlSize = .small
        let btnW: CGFloat = 115
        getApiKeyButton.frame = NSRect(x: size.width - rx - btnW, y: apiY + 2, width: btnW, height: 18)
        dataContainer.addSubview(getApiKeyButton)

        apiKeyField.frame = NSRect(x: fx, y: apiY, width: getApiKeyButton.frame.minX - fx - 8, height: 22)
        apiKeyField.placeholderString = "Optional — leave blank to use shared service"
        dataContainer.addSubview(apiKeyField)

        dataContainer.addSubview(smallLabel(
            "Leave blank for shared service, or paste your raildata.org.uk key.",
            x: lx, y: apiY - 4 - 14, width: rw
        ))

        // Attribution — fixed at bottom
        view.addSubview(smallLabel(
            "Train data provided by Rail Delivery Group (raildata.org.uk).",
            x: lx, y: 16, width: rw
        ))

        return view
    }

    private func buildDisplayTab(_ size: NSSize) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        let h = size.height
        let lx: CGFloat = 16
        let rx: CGFloat = 16
        let rw = size.width - lx - rx
        let labelW: CGFloat = 108

        // Padding row
        var ty = h - 20 - 22
        view.addSubview(label("Side padding:", width: labelW, x: lx, y: ty))
        paddingSlider.minValue = 0
        paddingSlider.maxValue = 30
        paddingSlider.numberOfTickMarks = 7
        paddingSlider.allowsTickMarkValuesOnly = false
        paddingSlider.target = self
        paddingSlider.action = #selector(paddingSliderChanged(_:))
        paddingSlider.frame = NSRect(x: lx + labelW + 8, y: ty, width: 210, height: 22)
        view.addSubview(paddingSlider)
        paddingValueLabel.frame = NSRect(x: paddingSlider.frame.maxX + 6, y: ty + 1, width: 44, height: 20)
        paddingValueLabel.alignment = .right
        view.addSubview(paddingValueLabel)

        ty -= 8 + 14
        view.addSubview(smallLabel(
            "Black margin on each side of the board (0–30% of screen width).",
            x: lx, y: ty, width: rw
        ))

        ty -= 16 + 18
        showStationCheckbox.frame = NSRect(x: lx, y: ty, width: rw, height: 18)
        view.addSubview(showStationCheckbox)

        // Advanced options disclosure
        ty -= 16 + 18
        let disclosureRow = NSView(frame: NSRect(x: 0, y: ty, width: size.width, height: 18))
        disclosureRow.alphaValue = 0.55
        disclosureRow.addGestureRecognizer(
            NSClickGestureRecognizer(target: self, action: #selector(toggleAdvanced))
        )
        view.addSubview(disclosureRow)

        let chevronView = NSImageView(frame: NSRect(x: lx, y: 3, width: 12, height: 12))
        chevronView.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        chevronView.imageScaling = .scaleNone
        chevronView.imageAlignment = .alignCenter
        chevronView.contentTintColor = .labelColor
        disclosureRow.addSubview(chevronView)
        advancedChevronView = chevronView

        let advLabel = NSTextField(labelWithString: "Advanced options")
        advLabel.font = NSFont.systemFont(ofSize: 12)
        advLabel.frame = NSRect(x: lx + 16, y: 1, width: 200, height: 16)
        disclosureRow.addSubview(advLabel)

        // Advanced container (hidden by default)
        // Contents: style row (26) + gap (6) + style hint (14) + gap (8) + metal checkbox (18) = 72
        let advH: CGFloat = 26 + 6 + 14 + 8 + 18
        ty -= 10 + advH
        let container = NSView(frame: NSRect(x: 0, y: ty, width: size.width, height: advH))
        container.isHidden = true
        view.addSubview(container)
        advancedContainer = container

        useMetalCheckbox.frame = NSRect(x: lx, y: 0, width: rw, height: 18)
        container.addSubview(useMetalCheckbox)

        container.addSubview(smallLabel(
            "Dot Matrix: GPU-accelerated LED grid · OLED: amber pixels · LCD: white on dark blue",
            x: lx, y: 18 + 8, width: rw
        ))

        let styleY: CGFloat = 18 + 8 + 14 + 6
        container.addSubview(label("Display style:", width: labelW, x: lx, y: styleY + 2))
        styleControl.frame = NSRect(x: lx + labelW + 8, y: styleY, width: rw - labelW - 8, height: 26)
        container.addSubview(styleControl)

        return view
    }

    // MARK: - Layout helpers

    private func label(_ text: String, width: CGFloat, x: CGFloat, y: CGFloat) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.frame = NSRect(x: x, y: y + 1, width: width, height: 20)
        return f
    }

    private func smallLabel(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = NSFont.systemFont(ofSize: 11)
        f.textColor = .secondaryLabelColor
        f.frame = NSRect(x: x, y: y, width: width, height: 14)
        return f
    }

    // MARK: - Actions

    @objc private func paddingSliderChanged(_ sender: NSSlider) {
        paddingValueLabel.stringValue = "\(Int(sender.doubleValue))%"
    }

    @objc private func toggleAdvanced() {
        let expanding = advancedContainer?.isHidden == true
        advancedContainer?.isHidden = !expanding
        let symbolName = expanding ? "chevron.down" : "chevron.right"
        advancedChevronView?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
    }

    @objc private func toggleDataAdvanced() {
        let expanding = dataAdvancedContainer?.isHidden == true
        dataAdvancedContainer?.isHidden = !expanding
        let symbolName = expanding ? "chevron.down" : "chevron.right"
        dataAdvancedChevronView?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
    }

    @objc private func saveAction() {
        var cfg = DepartureBoardConfig.load()
        cfg.apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespaces)
        let stationText = stationCombo.stringValue.trimmingCharacters(in: .whitespaces)
        if let match = StationSearch.shared.exactMatch(byName: stationText) {
            cfg.station = match.crs
        } else if stationText.count == 3 {
            cfg.station = stationText.uppercased()
        } else {
            let alert = NSAlert()
            alert.messageText = "Station not recognised"
            alert.informativeText = "Select a station from the dropdown, or enter a valid 3-letter CRS code."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        cfg.sidePaddingPct = paddingSlider.doubleValue
        switch styleControl.selectedSegment {
        case 1:  cfg.displayStyle = .oled
        case 2:  cfg.displayStyle = .lcd
        default: cfg.displayStyle = .dotMatrix
        }
        cfg.showStationInClock = showStationCheckbox.state == .on
        cfg.useMetalRendering  = useMetalCheckbox.state  == .on
        cfg.save()
        onSave?(cfg)
        endSheet()
    }

    @objc private func cancelAction() {
        endSheet()
    }

    @objc private func openKoFi() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/justynhenman")!)
    }
    
    @objc private func openAPIKeyPage() {
        NSWorkspace.shared.open(URL(string: "https://raildata.org.uk")!)
    }

    private func endSheet() {
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.endSheet(window)
        }
    }
}

// MARK: - NSComboBoxDataSource

extension ConfigureSheetController: NSComboBoxDataSource {
    func numberOfItems(in comboBox: NSComboBox) -> Int {
        filteredStations.count
    }

    func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
        filteredStations[index].name
    }
}

// MARK: - NSComboBoxDelegate

extension ConfigureSheetController: NSComboBoxDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let combo = obj.object as? NSComboBox, combo === stationCombo else { return }
        let text = combo.stringValue
        if text.count >= 2 {
            filteredStations = StationSearch.shared.search(text)
        } else {
            filteredStations = []
        }
        stationCombo.reloadData()
    }
}
