//
//  DepartureBoardSaverView.swift
//  DepartureBoardSaver
//

import ScreenSaver
import AppKit
import CoreText

@objc(DepartureBoardSaverView)
final class DepartureBoardSaverView: ScreenSaverView {

    // Rendered at 1:1, then nearest-neighbour scaled to fill the screen.
    private static let boardWidth:  CGFloat = 256
    private static var boardHeight: CGFloat { CGFloat(DepartureBoard.boardHeight) }

    private let board: DepartureBoard
    private var lastFrameTime: CFTimeInterval = 0
    private var refreshTask: Task<Void, Never>?
    private let sheetController = ConfigureSheetController()
    private var sidePaddingPct: Double = 0
    private var displayStyle: DisplayStyle = .oled
    private var showStationInClock: Bool = true
    private var useMetalRendering: Bool = true

    // Post-Sonoma legacyScreenSaver workaround state. Internal (not private) so the
    // logic in DepartureBoardSaverView+LegacyScreenSaver.swift can reach it.
    var actualIsPreview: Bool = false
    var isGhostInstance: Bool = false
    var isAnimationStarted: Bool = false
    // nonisolated(unsafe): only written during init and read in deinit.
    nonisolated(unsafe) var willStopObserver: NSObjectProtocol?
    var lastSystemSettingsCheck = Date()

    // Metal renderer (dot matrix mode only; nil if Metal is unavailable or disabled).
    private var metalRenderer: DotMatrixMetalRenderer?
    private var metalLayer: CAMetalLayer?

    private var isUsingMetal: Bool {
        displayStyle == .dotMatrix && useMetalRendering && metalRenderer != nil
    }

    // Fixed 256×48 pixel bitmap used as the offscreen canvas every frame.
    private let offscreenRep: NSBitmapImageRep
    private let offscreenImage: NSImage

    override init?(frame: NSRect, isPreview: Bool) {
        Self.registerEmbeddedFonts()
        let bundle = Bundle(for: DepartureBoardSaverView.self)
        self.board = DepartureBoard(bundle: bundle)
        (self.offscreenRep, self.offscreenImage) = Self.makeOffscreen()

        let preview = Self.resolveIsPreview(isPreview)
        actualIsPreview = preview

        super.init(frame: frame, isPreview: preview)
        animationTimeInterval = 1.0 / 60.0

        isGhostInstance = detectGhostInstance(frame: frame)
        if isGhostInstance { return }

        registerWillStopObserverIfNeeded()
    }

    required init?(coder: NSCoder) {
        Self.registerEmbeddedFonts()
        let bundle = Bundle(for: DepartureBoardSaverView.self)
        self.board = DepartureBoard(bundle: bundle)
        (self.offscreenRep, self.offscreenImage) = Self.makeOffscreen()
        super.init(coder: coder)
        animationTimeInterval = 1.0 / 60.0
        registerWillStopObserverIfNeeded()
    }

    deinit {
        if let observer = willStopObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    override var isFlipped: Bool { true }

    // MARK: - Animation lifecycle

    override func startAnimation() {
        guard !isGhostInstance else { return }
        // legacyScreenSaver can deliver duplicate start/stop calls (Sonoma+).
        guard !isAnimationStarted else { return }
        super.startAnimation()
        isAnimationStarted = true
        startRefresh()
    }

    override func stopAnimation() {
        guard isAnimationStarted else { return }
        super.stopAnimation()
        isAnimationStarted = false
        cancelRefresh()
        tearDownMetal()
    }

    // Internal (not private) so the legacyScreenSaver workaround extension can
    // stop refreshing without direct access to refreshTask.
    func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func startRefresh() {
        refreshTask?.cancel()
        let cfg = DepartureBoardConfig.load()
        sidePaddingPct = cfg.sidePaddingPct
        displayStyle = cfg.displayStyle
        showStationInClock = cfg.showStationInClock
        useMetalRendering = cfg.useMetalRendering
        updateMetalState()
        guard cfg.isReady else {
            board.setNotConfigured()
            return
        }
        board.setLoading(stationName: cfg.station)
        let service = DepartureService(apiKey: cfg.apiKey, crs: cfg.station)
        let station = cfg.station
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                let sleepSeconds: Int
                do {
                    let result = try await service.fetch()
                    await MainActor.run { [weak self] in
                        self?.board.apply(result: result)
                    }
                    sleepSeconds = 60
                } catch {
                    let msg = Self.friendlyMessage(for: error)
                    await MainActor.run { [weak self] in
                        self?.board.setError(stationName: station, message: msg)
                    }
                    sleepSeconds = 15
                }
                try? await Task.sleep(for: .seconds(sleepSeconds))
            }
        }
    }

    // MARK: - Drawing

    override func draw(_ rect: NSRect) {
        // When Metal is active and its layer is ready, the CAMetalLayer handles all output.
        // Guard requires metalLayer too: on the first frame the layer may not be set up yet,
        // and we must not return a blank screen while waiting for it.
        guard !(isUsingMetal && metalLayer != nil) else {
            NSColor.black.setFill()
            bounds.fill()
            return
        }

        renderBoardToBitmap()

        // Black letterbox behind the board.
        NSColor.black.setFill()
        bounds.fill()

        // Compute layout — used by both display paths below.
        let padding = bounds.width * CGFloat(sidePaddingPct / 100.0)
        let availableW = bounds.width - 2 * padding
        let scale = availableW / Self.boardWidth
        let scaledH = Self.boardHeight * scale
        let originY = (bounds.height - scaledH) / 2

        if displayStyle == .dotMatrix {
            // CPU fallback: draw each bitmap pixel as a physical LED dot.
            if let cgCtx = NSGraphicsContext.current?.cgContext {
                drawDotMatrix(padding: padding, scale: scale, originY: originY, into: cgCtx)
            }
        } else {
            // Nearest-neighbour scale — each source pixel becomes a crisp rectangle on screen.
            let destRect = NSRect(x: padding, y: originY, width: availableW, height: scaledH)
            offscreenImage.draw(
                in: destRect,
                from: NSRect(origin: .zero, size: offscreenImage.size),
                operation: .copy,
                fraction: 1.0,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.none]
            )
        }
    }

    // Render board text content into the fixed 256×48 offscreen bitmap.
    // Using NSGraphicsContext(bitmapImageRep:) guarantees 1pt=1px regardless of
    // the screen's Retina backing scale.
    private func renderBoardToBitmap() {
        guard let bitmapCtx = NSGraphicsContext(bitmapImageRep: offscreenRep) else { return }
        let cgCtx = bitmapCtx.cgContext
        cgCtx.translateBy(x: 0, y: Self.boardHeight)
        cgCtx.scaleBy(x: 1, y: -1)
        let flippedCtx = NSGraphicsContext(cgContext: cgCtx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = flippedCtx
        flippedCtx.shouldAntialias = false
        flippedCtx.imageInterpolation = .none
        board.displayStyle = displayStyle
        board.showStationInClock = showStationInClock
        board.draw(in: CGRect(x: 0, y: 0, width: Self.boardWidth, height: Self.boardHeight))
        NSGraphicsContext.restoreGraphicsState()
    }

    // Reads every pixel from the offscreen bitmap and renders it as a physical LED dot,
    // replicating the real hardware structure:
    //  - Five separate LED matrix panels separated by black housing gaps.
    //  - The clock panel (bottom) is narrower — unlit dots only appear within the
    //    horizontal extent actually occupied by the clock, with no dots outside it.
    private func drawDotMatrix(padding: CGFloat, scale: CGFloat, originY: CGFloat, into ctx: CGContext) {
        guard let rawData = offscreenRep.bitmapData else { return }
        let bytesPerRow = offscreenRep.bytesPerRow

        let dotRadius  = scale * 0.38
        let glowRadius = scale * 0.58
        let hlRadius   = scale * 0.18

        // Each tuple is the (firstRow, lastRow) in the bitmap that belongs to one panel.
        // Between consecutive panels there is a physical gap with no LED dots.
        let rh = DepartureBoard.rowHeight
        let ch = DepartureBoard.clockHeight
        let panels: [(start: Int, end: Int)] = [
            (0,        rh - 1),          // departure row 1
            (rh,       rh * 2 - 1),      // "calling at" row
            (rh * 2,   rh * 3 - 1),      // departure row 2
            (rh * 3,   rh * 4 - 1),      // departure row 3
            (rh * 4,   rh * 4 + ch - 1), // clock
        ]
        let gapSize = scale * 2.5   // housing gap between panels in screen points

        // Recompute the vertical origin so the taller total height stays centred.
        let totalH     = Self.boardHeight * scale + CGFloat(panels.count - 1) * gapSize
        let dotOriginY = (bounds.height - totalH) / 2

        // Screen-space top of the dot cell at bitmap row `row`.
        func cellTop(_ row: Int) -> CGFloat {
            for (i, p) in panels.enumerated() {
                if row >= p.start && row <= p.end {
                    return dotOriginY + CGFloat(row) * scale + CGFloat(i) * gapSize
                }
            }
            return dotOriginY + CGFloat(row) * scale
        }

        // Clock module boundary from layout — fixed regardless of which digits are currently lit.
        let (clockMinX, clockMaxX) = board.clockXExtent(boardWidth: Self.boardWidth)

        let litPath     = CGMutablePath()
        let glowPath    = CGMutablePath()
        let unlitPath   = CGMutablePath()
        let unlitHlPath = CGMutablePath()

        for py in 0..<DepartureBoard.boardHeight {
            let cy = cellTop(py) + 0.5 * scale
            let inClockPanel = py >= DepartureBoard.clockStartRow
            for px in 0..<Int(Self.boardWidth) {
                // Clock panel: nothing outside the physical module boundary.
                if inClockPanel && (clockMaxX < 0 || px < clockMinX || px > clockMaxX) { continue }

                let base = py * bytesPerRow + px * 4
                let isLit = rawData[base] > 20 || rawData[base + 1] > 20 || rawData[base + 2] > 20
                let cx = padding + (CGFloat(px) + 0.5) * scale
                if isLit {
                    litPath.addEllipse(in: CGRect(x: cx - dotRadius,  y: cy - dotRadius,
                                                  width: dotRadius * 2,  height: dotRadius * 2))
                    glowPath.addEllipse(in: CGRect(x: cx - glowRadius, y: cy - glowRadius,
                                                   width: glowRadius * 2, height: glowRadius * 2))
                } else {
                    unlitPath.addEllipse(in: CGRect(x: cx - dotRadius, y: cy - dotRadius,
                                                    width: dotRadius * 2, height: dotRadius * 2))
                    unlitHlPath.addEllipse(in: CGRect(x: cx - hlRadius, y: cy - hlRadius,
                                                      width: hlRadius * 2, height: hlRadius * 2))
                }
            }
        }

        ctx.setFillColor(CGColor(red: 0.10, green: 0.04, blue: 0.0, alpha: 1.0))
        ctx.addPath(unlitPath)
        ctx.fillPath()

        ctx.setFillColor(CGColor(red: 0.22, green: 0.10, blue: 0.01, alpha: 1.0))
        ctx.addPath(unlitHlPath)
        ctx.fillPath()

        ctx.setFillColor(CGColor(red: 1.0, green: 0.60, blue: 0.0, alpha: 0.22))
        ctx.addPath(glowPath)
        ctx.fillPath()

        ctx.setFillColor(CGColor(red: 1.0, green: 0.78, blue: 0.0, alpha: 1.0))
        ctx.addPath(litPath)
        ctx.fillPath()
    }

    override func animateOneFrame() {
        let now = CACurrentMediaTime()
        exitPreviewIfSystemSettingsClosed(now: Date())
        let delta = lastFrameTime == 0 ? 0 : now - lastFrameTime
        lastFrameTime = now
        board.advance(by: delta)
        if isUsingMetal, let renderer = metalRenderer {
            setupMetalLayerIfNeeded()
            if let ml = metalLayer {
                let sf = window?.backingScaleFactor ?? 2.0
                ml.frame = bounds
                ml.drawableSize = CGSize(width: bounds.width * sf, height: bounds.height * sf)
                renderBoardToBitmap()
                let clockRange = board.clockXExtent(boardWidth: Self.boardWidth)
                renderer.updateTexture(from: offscreenRep, clockMinX: clockRange.min, clockMaxX: clockRange.max)
                let padding = bounds.width * CGFloat(sidePaddingPct / 100.0)
                let scale   = (bounds.width - 2 * padding) / Self.boardWidth
                renderer.render(bounds: bounds, backingScale: sf, padding: padding, scale: scale, into: ml)
                return
            }
        }
        setNeedsDisplay(bounds)
    }

    // MARK: - Metal lifecycle

    // Create or destroy the renderer based on current style + preference.
    private func updateMetalState() {
        if displayStyle == .dotMatrix && useMetalRendering {
            if metalRenderer == nil {
                metalRenderer = DotMatrixMetalRenderer.make()
            }
        } else {
            tearDownMetal()
        }
    }

    private func setupMetalLayerIfNeeded() {
        guard metalLayer == nil, let renderer = metalRenderer else { return }
        wantsLayer = true
        let ml = CAMetalLayer()
        ml.device       = renderer.device
        ml.pixelFormat  = .bgra8Unorm
        ml.framebufferOnly = true
        ml.isOpaque     = true
        layer?.addSublayer(ml)
        metalLayer = ml
    }

    private func tearDownMetal() {
        metalLayer?.removeFromSuperlayer()
        metalLayer   = nil
        metalRenderer = nil
    }

    // MARK: - Configure sheet

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        sheetController.present { [weak self] _ in
            self?.startRefresh()
        }
        return sheetController.window
    }

    // MARK: - Test state injection (called by DepartureBoardSaverTestHost via perform(_:))

    @objc func testSetStateNotConfigured() {
        cancelRefresh()
        board.setNotConfigured()
    }

    @objc func testSetStateLoading() {
        cancelRefresh()
        board.setLoading(stationName: "PAD")
    }

    @objc func testSetStateError() {
        cancelRefresh()
        board.setError(stationName: "PAD", message: "No Internet Connection")
    }

    @objc func testSetStateLive0() {
        cancelRefresh()
        board.apply(result: DepartureResult(stationName: "London Paddington", departures: []))
    }

    @objc func testSetStateLive1() {
        cancelRefresh()
        board.apply(result: DepartureResult(stationName: "London Paddington", departures: Self.fakeDepartures(count: 1)))
    }

    @objc func testSetStateLive2() {
        cancelRefresh()
        board.apply(result: DepartureResult(stationName: "London Paddington", departures: Self.fakeDepartures(count: 2)))
    }

    @objc func testSetStateLive3() {
        cancelRefresh()
        board.apply(result: DepartureResult(stationName: "London Paddington", departures: Self.fakeDepartures(count: 3)))
    }

    private static func fakeDepartures(count: Int) -> [Departure] {
        let all: [Departure] = [
            Departure(scheduled: "12:30", destination: "London Paddington", platform: "1",
                      status: .onTime,
                      callingAt: ["Reading", "Didcot Parkway", "Swindon", "Bristol Parkway"]),
            Departure(scheduled: "12:45", destination: "Bristol Temple Meads", platform: "2",
                      status: .expected("12:47"),
                      callingAt: ["Reading", "Bath Spa"]),
            Departure(scheduled: "13:00", destination: "Oxford", platform: "3",
                      status: .cancelled,
                      callingAt: ["Slough", "Maidenhead"]),
        ]
        return Array(all.prefix(count))
    }

    // MARK: - Setup helpers

    private static let fontsRegistered: Void = {
        let bundle = Bundle(for: DepartureBoardSaverView.self)
        let urls = (bundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
                 + (bundle.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    static func registerEmbeddedFonts() { _ = fontsRegistered }

    private static func friendlyMessage(for error: Error) -> String {
        let nsErr = error as NSError
        if nsErr.domain == NSURLErrorDomain {
            switch nsErr.code {
            case NSURLErrorNotConnectedToInternet: return "No Internet Connection"
            case NSURLErrorTimedOut:               return "Request Timed Out"
            case NSURLErrorNetworkConnectionLost:  return "Connection Lost"
            case NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost:          return "Cannot Reach Server"
            default: break
            }
        }
        if let svcErr = error as? DepartureServiceError {
            switch svcErr {
            case .badStatus(401):      return "Invalid API Key"
            case .badStatus(let code): return "Server Error (\(code))"
            case .parseFailure:        return "Data Error"
            }
        }
        return nsErr.localizedDescription
    }

    private static func makeOffscreen() -> (NSBitmapImageRep, NSImage) {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(boardWidth),
            pixelsHigh: Int(boardHeight),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        )!
        rep.size = NSSize(width: boardWidth, height: boardHeight)
        let image = NSImage(size: NSSize(width: boardWidth, height: boardHeight))
        image.addRepresentation(rep)
        return (rep, image)
    }
}
