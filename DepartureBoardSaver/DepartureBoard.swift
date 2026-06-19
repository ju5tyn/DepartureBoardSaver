//
//  DepartureBoard.swift
//  DepartureBoardSaver
//

import AppKit

// MARK: - Model types

enum DepartureStatus: Sendable {
    case onTime
    case expected(String)
    case delayed
    case cancelled
}

struct Departure: Sendable {
    let scheduled: String
    let destination: String
    let platform: String
    let status: DepartureStatus
    let callingAt: [String]

    var statusText: String {
        switch status {
        case .onTime:           return "On time"
        case .expected(let t):  return t == scheduled ? "On time" : "Exp \(t)"
        case .delayed:          return "Delayed"
        case .cancelled:        return "Cancelled"
        }
    }
}

enum BoardState {
    case notConfigured
    case loading(stationName: String)
    case error(stationName: String, message: String, retryAt: Date)
    case live(stationName: String, departures: [Departure])
}

// MARK: - Board renderer

final class DepartureBoard {

    // MARK: - Layout constants
    // Adjust rowHeight and clockHeight independently. boardHeight is derived.
    // When changing either value, also update the Metal shader arrays in DotMatrixShaders.metal.
    static let rowHeight:    Int = 9   // height of each departure / calling-at panel
    static let clockHeight:  Int = 14  // height of the clock panel

    static let clockStartRow: Int = 4 * rowHeight
    static let boardHeight:   Int = clockStartRow + clockHeight

    private static let setupInstructions =
        "System Settings  >  Wallpaper  >  Screen Saver  >  scroll down to Other  >  DepartureBoardSaver  >  Options"

    private let fonts: BoardFonts
    var displayStyle: DisplayStyle = .oled
    var showStationInClock: Bool = true
    private let rowPad: CGFloat = 0

    private var foregroundColor: NSColor {
        switch displayStyle {
        case .oled, .dotMatrix:
            return NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.0, alpha: 1.0)
        case .lcd:
            return NSColor(calibratedRed: 0.9, green: 0.95, blue: 1.0, alpha: 1.0)
        }
    }

    private var boardBackground: NSColor {
        switch displayStyle {
        case .oled, .dotMatrix:
            return .black
        case .lcd:
            return NSColor(calibratedRed: 0.02, green: 0.05, blue: 0.12, alpha: 1.0)
        }
    }

    private(set) var state: BoardState = .notConfigured

    private var scrollX: CGFloat = 0
    private var scrollPauseRemaining: TimeInterval = 1.5
    private let scrollSpeed: CGFloat = 32

    private var loadingElapsed: TimeInterval = 0

    // 3×3 spinner: phase runs 0..<8, one step per position clockwise
    private var spinnerPhase: Double = 0
    private let spinnerSpeed: Double = 8  // positions/second → 1 rev/second

    init(bundle: Bundle) {
        self.fonts = BoardFonts(bundle: bundle)
    }

    // MARK: - State updates (call from main thread)

    func apply(result: DepartureResult) {
        scrollX = 0
        scrollPauseRemaining = 1.5
        state = .live(stationName: result.stationName, departures: result.departures)
    }

    func setLoading(stationName: String) {
        loadingElapsed = 0
        state = .loading(stationName: stationName)
    }

    func setNotConfigured() {
        scrollX = 0
        scrollPauseRemaining = 1.5
        state = .notConfigured
    }

    func setError(stationName: String, message: String) {
        state = .error(stationName: stationName, message: message, retryAt: Date().addingTimeInterval(15))
    }

    // MARK: - Animation tick

    func advance(by delta: TimeInterval) {
        if case .loading = state {
            loadingElapsed += delta
            if loadingElapsed >= 1.0 {
                spinnerPhase = (spinnerPhase + delta * spinnerSpeed).truncatingRemainder(dividingBy: 8)
            }
        }

        let scrollText: String?
        switch state {
        case .live(_, let deps) where deps.first != nil:
            scrollText = callingAtText(for: deps.first!)
        case .notConfigured:
            scrollText = Self.setupInstructions
        default:
            scrollText = nil
        }
        guard let text = scrollText else { return }

        if scrollPauseRemaining > 0 {
            scrollPauseRemaining -= delta
            return
        }
        scrollX -= CGFloat(delta) * scrollSpeed
        let tw = textSize(text, font: fonts.regular).width
        if scrollX < -tw - 12 {
            scrollX = 0
            scrollPauseRemaining = 1.5
        }
    }

    // MARK: - Drawing (called inside a 256×48 flipped graphics context)

    func draw(in rect: CGRect) {
        boardBackground.setFill()
        rect.fill()

        switch state {
        case .notConfigured:
            drawNotConfigured(in: rect)
        case .loading(let name):
            drawLoading(stationName: name, in: rect)
        case .error(_, let msg, let retryAt):
            let secs = max(0, Int(ceil(retryAt.timeIntervalSinceNow)))
            drawCentred(msg, sub: "Retry in \(secs)s", in: rect)
        case .live(let name, let deps) where deps.isEmpty:
            drawBlank(stationName: name, spinner: false, in: rect)
        case .live(let name, let deps):
            drawSignage(deps, stationName: name, in: rect)
        }
    }

    // MARK: - Screen variants

    private func drawBlank(stationName: String, spinner: Bool, in rect: CGRect) {
        let w = rect.width
        let rh = CGFloat(Self.rowHeight)
        centredText("Welcome to", font: fonts.bold, y: rowPad, width: w)
        centredText(stationName, font: fonts.bold, y: rh + rowPad, width: w)
        if spinner { drawSpinner(centredIn: CGRect(x: 0, y: rh * 2, width: w, height: rh)) }
        drawClock(atY: CGFloat(Self.clockStartRow), width: w, stationName: nil)
    }

    // 3×3 grid spinner: 8 edge pixels rotate clockwise, 3 lit at a time (head + 2 trailing).
    private func drawSpinner(centredIn rect: CGRect) {
        drawSpinnerAt(cx: Int(rect.midX), cy: Int(rect.midY))
    }

    private func drawSpinnerAt(cx: Int, cy: Int) {
        // Clockwise offsets from centre: TL, TC, TR, MR, BR, BC, BL, ML
        let offsets: [(Int, Int)] = [(-1,-1),(0,-1),( 1,-1),
                                     ( 1, 0),       ( 1, 1),
                                     ( 0, 1),(-1,1),(-1, 0)]
        let head = Int(spinnerPhase) % 8
        let lit: Set<Int> = [head, (head + 7) % 8, (head + 6) % 8]
        // Each dot is 2×2 px; step between dot origins = 3 (2 px dot + 1 px gap).
        // Top-left of dot at (dx,dy): (cx - 1 + dx*3, cy - 1 + dy*3).
        // Total spinner extent: 8×8 px centred on (cx, cy).
        foregroundColor.setFill()
        for (i, (dx, dy)) in offsets.enumerated() where lit.contains(i) {
            NSRect(x: CGFloat(cx - 1 + dx * 3), y: CGFloat(cy - 1 + dy * 3), width: 2, height: 2).fill()
        }
    }

    // Not configured: rows 2+3 centred, row 4 scrolling setup instructions
    private func drawNotConfigured(in rect: CGRect) {
        let rh = CGFloat(Self.rowHeight)
        let w  = rect.width
        centredText("Open Screen Saver Options", font: fonts.regular, y: rh + rowPad,     width: w)
        centredText("to enter your API key",     font: fonts.regular, y: rh * 2 + rowPad, width: w)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: 0, y: rh * 3, width: w, height: rh)).addClip()
        drawText(Self.setupInstructions, font: fonts.regular, at: CGPoint(x: scrollX, y: rh * 3 + rowPad))
        NSGraphicsContext.restoreGraphicsState()
        drawClock(atY: CGFloat(Self.clockStartRow), width: w, stationName: nil)
    }

    // Loading: "Loading STN [spinner]" on row 2, regular font
    private func drawLoading(stationName: String, in rect: CGRect) {
        let rh  = CGFloat(Self.rowHeight)
        let text = "Loading \(stationName)"
        let tw   = textSize(text, font: fonts.regular).width
        let gap: CGFloat = 5
        let spinW: CGFloat = 8   // 3 dots × 2 px + 2 gaps × 1 px = 8 px wide
        if loadingElapsed >= 1.0 {
            let x = (rect.width - tw - gap - spinW) / 2
            drawText(text, font: fonts.regular, at: CGPoint(x: x, y: rh + rowPad))
            drawSpinnerAt(cx: Int(x + tw + gap + spinW / 2), cy: Int(rh + rh / 2))
        }
        drawClock(atY: CGFloat(Self.clockStartRow), width: rect.width, stationName: nil)
    }

    // Error / not-configured: two lines centred on rows 2 and 3, regular font
    private func drawCentred(_ line1: String, sub line2: String, in rect: CGRect) {
        let rh = CGFloat(Self.rowHeight)
        centredText(line1, font: fonts.regular, y: rh + rowPad,       width: rect.width)
        centredText(line2, font: fonts.regular, y: rh * 2 + rowPad,   width: rect.width)
        drawClock(atY: CGFloat(Self.clockStartRow), width: rect.width, stationName: nil)
    }

    private func drawSignage(_ deps: [Departure], stationName: String, in rect: CGRect) {
        let w = rect.width
        let rh = CGFloat(Self.rowHeight)
        let statusW = ceil(textSize("Exp 00:00", font: fonts.regular).width)
        let platW   = ceil(textSize("Plat 888",  font: fonts.regular).width)
        let callingW = ceil(textSize("Calling at: ", font: fonts.regular).width)

        if deps.count >= 1 {
            drawRow(deps[0], boldDest: true,  atY: 0,      width: w, statusW: statusW, platW: platW)
        }
        drawText("Calling at:", font: fonts.regular, at: CGPoint(x: 0, y: rh + rowPad))
        drawScrolling(deps[0], atY: rh, xStart: callingW, maxX: w)

        if deps.count >= 2 {
            drawRow(deps[1], boldDest: false, atY: rh * 2, width: w, statusW: statusW, platW: platW)
        }
        if deps.count >= 3 {
            drawRow(deps[2], boldDest: false, atY: rh * 3, width: w, statusW: statusW, platW: platW)
        }
        drawClock(atY: CGFloat(Self.clockStartRow), width: w, stationName: showStationInClock ? stationName : nil)
    }

    // MARK: - Row helpers

    private func drawRow(_ d: Departure, boldDest: Bool, atY y: CGFloat,
                         width: CGFloat, statusW: CGFloat, platW: CGFloat) {
        let font = boldDest ? fonts.bold : fonts.regular
        drawText("\(d.scheduled)  \(d.destination)", font: font, at: CGPoint(x: 0, y: y + rowPad))

        if !d.platform.isEmpty {
            let plat = d.platform.lowercased() == "bus" ? "BUS" : "Plat \(d.platform)"
            drawText(plat, font: fonts.regular, at: CGPoint(x: width - statusW - platW, y: y + rowPad))
        }

        let status = d.statusText
        let sw = textSize(status, font: fonts.regular).width
        drawText(status, font: fonts.regular, at: CGPoint(x: width - sw, y: y + rowPad))
    }

    private func drawScrolling(_ d: Departure, atY y: CGFloat, xStart: CGFloat, maxX: CGFloat) {
        let text = callingAtText(for: d)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: xStart, y: y, width: maxX - xStart, height: CGFloat(Self.rowHeight))).addClip()
        drawText(text, font: fonts.regular, at: CGPoint(x: xStart + scrollX, y: y + rowPad))
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawClock(atY y: CGFloat, width: CGFloat, stationName: String?) {
        let comps = Calendar(identifier: .gregorian)
            .dateComponents([.hour, .minute, .second], from: Date())
        let hm = String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
        let ss = String(format: "%02d", comps.second ?? 0)

        let hmCell   = ceil(textSize("0", font: fonts.boldLarge).width)
        let ssCell   = ceil(textSize("0", font: fonts.boldTall).width)
        let colonW   = textSize(":", font: fonts.boldLarge).width
        let hmTotalW = monospacedWidth(hm, font: fonts.boldLarge, cellWidth: hmCell)
        let ssTotalW = colonW + CGFloat(ss.count) * ssCell
        let ox = (width - hmTotalW - ssTotalW) / 2

        drawMonospaced(hm, font: fonts.boldLarge, cellWidth: hmCell, at: CGPoint(x: ox, y: y))
        drawText(":", font: fonts.boldLarge, at: CGPoint(x: ox + hmTotalW, y: y))
        drawMonospaced(ss, font: fonts.boldTall, cellWidth: ssCell, at: CGPoint(x: ox + hmTotalW + colonW, y: y + 5))

        // Station name right-aligned in the clock row so you can confirm which station is live.
        if let name = stationName {
            let nw = textSize(name, font: fonts.regular).width
            drawText(name, font: fonts.regular, at: CGPoint(x: width - nw, y: y + 4))
        }
    }

    // Returns the fixed horizontal pixel extent of the clock in a bitmap of the given width.
    // Uses a monospaced layout so the range never changes as digits update.
    func clockXExtent(boardWidth: CGFloat) -> (min: Int, max: Int) {
        let hmCell   = ceil(textSize("0", font: fonts.boldLarge).width)
        let ssCell   = ceil(textSize("0", font: fonts.boldTall).width)
        let colonW   = textSize(":", font: fonts.boldLarge).width
        let hmTotalW = monospacedWidth("00:00", font: fonts.boldLarge, cellWidth: hmCell)
        let ssTotalW = colonW + 2 * ssCell
        let ox       = (boardWidth - hmTotalW - ssTotalW) / 2
        let minX     = Int(floor(ox))
        let maxX     = showStationInClock ? Int(boardWidth) - 1
                                          : Int(ceil(ox + hmTotalW + ssTotalW)) - 3
        return (minX, maxX)
    }

    private func monospacedWidth(_ text: String, font: NSFont, cellWidth: CGFloat) -> CGFloat {
        text.reduce(0) { sum, ch in
            sum + (ch.isNumber ? cellWidth : textSize(String(ch), font: font).width)
        }
    }

    private func drawMonospaced(_ text: String, font: NSFont, cellWidth: CGFloat, at point: CGPoint) {
        var x = point.x
        for ch in text {
            let s = String(ch)
            let w = textSize(s, font: font).width
            if ch.isNumber {
                drawText(s, font: font, at: CGPoint(x: x + (cellWidth - w) / 2, y: point.y))
                x += cellWidth
            } else {
                drawText(s, font: font, at: CGPoint(x: x, y: point.y))
                x += w
            }
        }
    }

    // MARK: - Primitives

    private func drawText(_ text: String, font: NSFont, at point: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foregroundColor]
        NSAttributedString(string: text, attributes: attrs).draw(at: point)
    }

    private func centredText(_ text: String, font: NSFont, y: CGFloat, width: CGFloat) {
        let w = textSize(text, font: font).width
        drawText(text, font: font, at: CGPoint(x: (width - w) / 2, y: y))
    }

    private func textSize(_ text: String, font: NSFont) -> CGSize {
        NSAttributedString(string: text, attributes: [.font: font]).size()
    }

    private func callingAtText(for d: Departure) -> String {
        let pts = d.callingAt
        if pts.isEmpty  { return "\(d.destination) only." }
        if pts.count == 1 { return "\(pts[0]) only." }
        return pts.dropLast().joined(separator: ", ") + " and \(pts.last!)."
    }
}


