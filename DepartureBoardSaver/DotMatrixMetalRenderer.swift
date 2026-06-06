//
//  DotMatrixMetalRenderer.swift
//  DepartureBoardSaver
//

import Metal
import AppKit

// Must mirror the Uniforms struct in DotMatrixShaders.metal exactly.
struct DotMatrixUniforms {
    var padding:    Float   // drawable pixels from left edge
    var scale:      Float   // drawable pixels per source bitmap pixel
    var dotOriginY: Float   // drawable Y of the top of panel 0 (Y-down)
    var gapSize:    Float   // drawable pixels per inter-panel gap
    var dotRadius:  Float
    var glowRadius: Float
    var hlRadius:   Float
    var clockMinX:  Int32
    var clockMaxX:  Int32
}

final class DotMatrixMetalRenderer {

    let device: MTLDevice
    private let commandQueue:  MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let dotTexture:    MTLTexture            // 256×boardHeight r8Unorm

    private var grayscale  = [UInt8](repeating: 0, count: 256 * DepartureBoard.boardHeight)
    private var clockMinX: Int32 = 0
    private var clockMaxX: Int32 = -1

    // Returns nil if Metal is unavailable or shader compilation fails.
    static func make() -> DotMatrixMetalRenderer? {
        guard let dev = MTLCreateSystemDefaultDevice() else { return nil }
        return try? DotMatrixMetalRenderer(device: dev)
    }

    private init(device: MTLDevice) throws {
        self.device = device

        guard let queue = device.makeCommandQueue() else { throw Err.setup }
        commandQueue = queue

        // .saver bundles embed their Metal library alongside other resources.
        let bundle = Bundle(for: DotMatrixMetalRenderer.self)
        let library: MTLLibrary
        if let lib = try? device.makeDefaultLibrary(bundle: bundle) {
            library = lib
        } else if let url  = bundle.url(forResource: "default", withExtension: "metallib"),
                  let lib  = try? device.makeLibrary(URL: url) {
            library = lib
        } else {
            throw Err.setup
        }

        guard let vert = library.makeFunction(name: "dotMatrixVertex"),
              let frag = library.makeFunction(name: "dotMatrixFragment") else {
            throw Err.setup
        }

        let pd = MTLRenderPipelineDescriptor()
        pd.vertexFunction   = vert
        pd.fragmentFunction = frag
        pd.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineState = try device.makeRenderPipelineState(descriptor: pd)

        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: 256, height: DepartureBoard.boardHeight,
            mipmapped: false
        )
        td.usage       = [.shaderRead]
        td.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: td) else { throw Err.setup }
        dotTexture = tex
    }

    // Upload the bitmap. clockMinX/clockMaxX are the fixed clock-module column bounds,
    // computed from the board layout rather than scanned from lit pixels.
    func updateTexture(from rep: NSBitmapImageRep, clockMinX: Int, clockMaxX: Int) {
        guard let raw = rep.bitmapData else { return }
        let bpr = rep.bytesPerRow

        for py in 0..<DepartureBoard.boardHeight {
            let rowBase  = py * bpr
            let destBase = py * 256
            for px in 0..<256 {
                let b = rowBase + px * 4
                grayscale[destBase + px] = max(raw[b], max(raw[b + 1], raw[b + 2]))
            }
        }
        self.clockMinX = Int32(clockMinX)
        self.clockMaxX = Int32(clockMaxX)

        dotTexture.replace(
            region:       MTLRegionMake2D(0, 0, 256, DepartureBoard.boardHeight),
            mipmapLevel:  0,
            withBytes:    grayscale,
            bytesPerRow:  256
        )
    }

    // Render one frame into the given CAMetalLayer.
    // Call updateTexture(from:) first each frame.
    func render(bounds: CGRect, backingScale: CGFloat, padding: CGFloat,
                scale: CGFloat, into layer: CAMetalLayer) {
        guard let drawable = layer.nextDrawable(),
              let cmdBuf   = commandQueue.makeCommandBuffer() else { return }

        let sf      = Float(backingScale)
        let scalePx = Float(scale) * sf
        let gapPx   = scalePx * 2.5
        let totalH  = Float(DepartureBoard.boardHeight) * scalePx + 4.0 * gapPx
        let drawH   = Float(bounds.height) * sf

        var u = DotMatrixUniforms(
            padding:    Float(padding) * sf,
            scale:      scalePx,
            dotOriginY: (drawH - totalH) / 2.0,
            gapSize:    gapPx,
            dotRadius:  scalePx * 0.38,
            glowRadius: scalePx * 0.58,
            hlRadius:   scalePx * 0.18,
            clockMinX:  clockMinX,
            clockMaxX:  clockMaxX
        )

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture     = drawable.texture
        pass.colorAttachments[0].loadAction  = .clear
        pass.colorAttachments[0].clearColor  = MTLClearColorMake(0, 0, 0, 1)
        pass.colorAttachments[0].storeAction = .store

        guard let enc = cmdBuf.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipelineState)
        enc.setFragmentBytes(&u, length: MemoryLayout<DotMatrixUniforms>.stride, index: 0)
        enc.setFragmentTexture(dotTexture, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()

        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    private enum Err: Error { case setup }
}
