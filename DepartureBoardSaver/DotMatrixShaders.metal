//
//  DotMatrixShaders.metal
//  DepartureBoardSaver
//

#include <metal_stdlib>
using namespace metal;

// Layout constants — keep in sync with DepartureBoard.rowHeight / clockHeight in DepartureBoard.swift.
constant int rowHeight    = 9;
constant int clockHeight  = 14;
constant int clockStartRow = 4 * rowHeight;
constant int boardHeight   = clockStartRow + clockHeight;

constant int panelStarts[5] = {0,           rowHeight,   rowHeight*2, rowHeight*3, clockStartRow};
constant int panelEnds[5]   = {rowHeight-1, rowHeight*2-1, rowHeight*3-1, clockStartRow-1, boardHeight-1};

// Must mirror DotMatrixUniforms in DotMatrixMetalRenderer.swift exactly.
struct Uniforms {
    float padding;      // left padding in drawable pixels
    float scale;        // drawable pixels per bitmap pixel
    float dotOriginY;   // drawable Y of the top of panel 0 (Y increases downward)
    float gapSize;      // drawable pixels per inter-panel housing gap
    float dotRadius;    // physical dot radius in drawable pixels
    float glowRadius;   // glow halo radius
    float hlRadius;     // unlit highlight radius
    int   clockMinX;    // bitmap column range of the clock module
    int   clockMaxX;
};

// Full-screen triangle strip — no vertex buffers needed.
vertex float4 dotMatrixVertex(uint vid [[vertex_id]]) {
    // NDC positions: y=+1 → viewport top, y=−1 → viewport bottom.
    float2 pos[4] = {
        float2(-1,  1),   // top-left
        float2( 1,  1),   // top-right
        float2(-1, -1),   // bottom-left
        float2( 1, -1),   // bottom-right
    };
    return float4(pos[vid], 0, 1);
}

fragment float4 dotMatrixFragment(
    float4               position [[position]],   // viewport px, y=0 at top
    constant Uniforms   &u        [[buffer(0)]],
    texture2d<float>     tex      [[texture(0)]]  // 256×boardHeight r8Unorm luminance
) {
    constexpr sampler s(filter::nearest, address::clamp_to_edge);

    float sx = position.x;
    float sy = position.y;  // 0 = top of drawable

    // ── X: map screen pixel → bitmap column ──────────────────────────────────
    float relX = sx - u.padding;
    if (relX < 0.0 || relX >= 256.0 * u.scale) return float4(0, 0, 0, 1);
    int bx = int(relX / u.scale);

    // ── Y: map screen pixel → panel + bitmap row ─────────────────────────────
    float relY = sy - u.dotOriginY;
    if (relY < 0.0) return float4(0, 0, 0, 1);

    int   by       = -1;
    float cellTopY = -1.0;

    for (int i = 0; i < 5; i++) {
        float panelTop = float(panelStarts[i]) * u.scale + float(i) * u.gapSize;
        float panelBot = (float(panelEnds[i]) + 1.0) * u.scale + float(i) * u.gapSize;
        if (relY >= panelTop && relY < panelBot) {
            int row = panelStarts[i] + int((relY - panelTop) / u.scale);
            if (row >= panelStarts[i] && row <= panelEnds[i]) {
                by       = row;
                cellTopY = u.dotOriginY + panelTop
                         + float(row - panelStarts[i]) * u.scale;
            }
            break;
        }
    }

    if (by < 0) return float4(0, 0, 0, 1);  // inter-panel housing gap

    // Clock module: only render within its horizontal extent.
    if (by >= clockStartRow && (u.clockMaxX < 0 || bx < u.clockMinX || bx > u.clockMaxX)) {
        return float4(0, 0, 0, 1);
    }

    // Distance from this fragment to the centre of its LED dot.
    float cx   = u.padding + (float(bx) + 0.5) * u.scale;
    float cy   = cellTopY  + 0.5 * u.scale;
    float dist = length(float2(sx - cx, sy - cy));

    // Sample luminance texture (v=0 at top matches bitmap row 0).
    float2 uv   = float2((float(bx) + 0.5) / 256.0, (float(by) + 0.5) / float(boardHeight));
    bool   isLit = tex.sample(s, uv).r > (20.0 / 255.0);

    if (isLit) {
        if (dist <= u.dotRadius)  return float4(1.00, 0.78, 0.00, 1.0);
        if (dist <= u.glowRadius) return float4(0.22, 0.132, 0.00, 1.0); // amber α=0.22 over black
    } else {
        if (dist <= u.hlRadius)   return float4(0.22, 0.10, 0.01, 1.0);
        if (dist <= u.dotRadius)  return float4(0.10, 0.04, 0.00, 1.0);
    }
    return float4(0, 0, 0, 1);
}
