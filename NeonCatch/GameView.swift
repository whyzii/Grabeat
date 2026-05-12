import SwiftUI
import AVFoundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct GameView: View {
    @ObservedObject var gameManager: GameManager
    @ObservedObject var tracker: CameraHandTracker
    @State private var gridRipples: [GridRipple] = []

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height

            ZStack {
                // ── 1. Camera feed ───────────────────────────────────────
                CameraPreview(tracker: tracker)
                    .ignoresSafeArea()
                    .opacity(0.88)

                // ── 2. Cyberpunk filter ──────────────────────────────────
                CyberpunkCameraFilter()

                // ── 3. Animated interactive grid ─────────────────────────
                AnimatedGrid(
                    handPositions: (tracker.handsP1 + tracker.handsP2)
                        .filter(\.isActive).map(\.position),
                    ripples: gridRipples
                )

                // ── 4. Zone tints ────────────────────────────────────────
                HStack(spacing: 0) {
                    Color.cyan.opacity(0.06)
                    Color.magenta.opacity(0.06)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // ── 5. Center divider ────────────────────────────────────
                ZStack {
                    // Soft glow behind the hard line
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.cyan.opacity(0.18), .white.opacity(0.05), .magenta.opacity(0.18)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 24)
                    // Hard line
                    Rectangle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 1.5)
                }
                .frame(maxHeight: .infinity)
                .allowsHitTesting(false)
                .position(x: W / 2, y: H / 2)

                // ── 6. Pixel particles ───────────────────────────────────
                // Single Canvas replaces per-particle SwiftUI views + shadows,
                // which caused severe FPS drops at high particle counts.
                Canvas { ctx, sz in
                    for p in gameManager.particles {
                        let alpha = max(0.0, p.life)
                        guard alpha > 0 else { continue }
                        let cx   = p.position.x * sz.width
                        let cy   = p.position.y * sz.height
                        let half = p.size * 0.5
                        // Soft glow ring then crisp core pixel
                        let glowHalf = half + p.size
                        ctx.fill(
                            Path(CGRect(x: cx - glowHalf, y: cy - glowHalf,
                                        width: glowHalf * 2, height: glowHalf * 2)),
                            with: .color(p.color.opacity(alpha * 0.22))
                        )
                        ctx.fill(
                            Path(CGRect(x: cx - half, y: cy - half,
                                        width: p.size, height: p.size)),
                            with: .color(p.color.opacity(alpha))
                        )
                    }
                }
                .allowsHitTesting(false)

                // ── 7. Notes ─────────────────────────────────────────────
                ForEach(gameManager.notes) { note in
                    let glitching = note.player == 1 ? gameManager.trapGlitchP1.active
                                                     : gameManager.trapGlitchP2.active
                    let phase     = note.player == 1 ? gameManager.trapGlitchP1.glitchPhase
                                                     : gameManager.trapGlitchP2.glitchPhase
                    let ghosted   = note.player == 1 ? gameManager.ghostP1.active
                                                     : gameManager.ghostP2.active
                    NoteView(note: note, size: geo.size)
                        .opacity(glitching ? abs(sin(phase * .pi * 9)) * 0.35 + 0.10
                                           : ghosted   ? 0.07
                                           : 1.0)
                }

                // ── 8. Score floats ──────────────────────────────────────
                ForEach(gameManager.scoreFloats) { sf in
                    VStack(spacing: 2) {
                        if !sf.beatLabel.isEmpty {
                            Text(sf.beatLabel)
                                .font(.custom("Audiowide-Regular", size: 13))
                                .foregroundColor(sf.beatLabelColor)
                                .shadow(color: sf.beatLabelColor, radius: 8)
                        }
                        if sf.points > 0 {
                            Text("+\(sf.points)")
                                .font(.custom("Audiowide-Regular", size: 26))
                                .foregroundColor(sf.color)
                                .shadow(color: sf.color, radius: 10)
                                .shadow(color: sf.color, radius: 4)
                        }
                    }
                    .opacity(max(0, sf.life))
                    .scaleEffect(sf.scale)
                    .position(x: sf.position.x * W, y: sf.position.y * H)
                    .allowsHitTesting(false)
                }

                // ── 9. Hand cursors (up to 2 per player) ─────────────────
                if tracker.handsP1.count > 0 { HandCursor(hand: tracker.handsP1[0], color: .cyan,    size: geo.size, frozen: gameManager.freezeP1.active) }
                if tracker.handsP1.count > 1 { HandCursor(hand: tracker.handsP1[1], color: .cyan,    size: geo.size, frozen: gameManager.freezeP1.active) }
                if tracker.handsP2.count > 0 { HandCursor(hand: tracker.handsP2[0], color: .magenta, size: geo.size, frozen: gameManager.freezeP2.active) }
                if tracker.handsP2.count > 1 { HandCursor(hand: tracker.handsP2[1], color: .magenta, size: geo.size, frozen: gameManager.freezeP2.active) }

                // ── 10. Freeze overlays (per player half) ────────────────
                if gameManager.freezeP1.active {
                    FreezeOverlay(freeze: gameManager.freezeP1, side: .left, size: geo.size)
                }
                if gameManager.freezeP2.active {
                    FreezeOverlay(freeze: gameManager.freezeP2, side: .right, size: geo.size)
                }

                // ── 10b. Trap glitch overlays ─────────────────────────────
                if gameManager.trapGlitchP1.active {
                    TrapGlitchOverlay(glitch: gameManager.trapGlitchP1, side: .left,  player: 1, size: geo.size)
                }
                if gameManager.trapGlitchP2.active {
                    TrapGlitchOverlay(glitch: gameManager.trapGlitchP2, side: .right, player: 2, size: geo.size)
                }

                // ── 11. HUD ──────────────────────────────────────────────
                VStack {
                    HUDBar(gameManager: gameManager)
                    Spacer()
                    BeatIndicator(quality: gameManager.lastBeatQuality)
                        .padding(.bottom, 8)
                    ZoneLabels()
                }
            }
            // Forward hand state to GameManager for catch detection.
            // handsP1/handsP2 are NOT @Published — forwarding them doesn't trigger re-renders.
            .onChange(of: tracker.handsP1) { _, h in gameManager.handsP1 = h }
            .onChange(of: tracker.handsP2) { _, h in gameManager.handsP2 = h }
            .onChange(of: gameManager.lastCatch) { _, event in
                guard let e = event else { return }
                gridRipples.append(GridRipple(origin: e.position, color: e.color))
                gridRipples = Array(gridRipples.suffix(6)).filter(\.isAlive)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Camera Preview

#if os(iOS)
struct CameraPreview: UIViewRepresentable {
    let tracker: CameraHandTracker

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.clipsToBounds = true
        if let layer = tracker.previewLayer {
            layer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(layer)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let layer = tracker.previewLayer else { return }
        // Re-attach if the layer isn't in this view (e.g. first render or tracker swap).
        if layer.superlayer == nil || layer.superlayer !== uiView.layer {
            layer.removeFromSuperlayer()
            layer.videoGravity = .resizeAspectFill
            uiView.layer.addSublayer(layer)
        }
        // Update frame without animation.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = uiView.bounds
        CATransaction.commit()
    }
}
#elseif os(macOS)
struct CameraPreview: NSViewRepresentable {
    let tracker: CameraHandTracker

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer = CALayer()
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.layer?.masksToBounds = true
        if let layer = tracker.previewLayer {
            layer.videoGravity = .resizeAspectFill
            view.layer?.addSublayer(layer)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let hostLayer = nsView.layer,
              let layer = tracker.previewLayer else { return }
        if layer.superlayer == nil || layer.superlayer !== hostLayer {
            layer.removeFromSuperlayer()
            layer.videoGravity = .resizeAspectFill
            hostLayer.addSublayer(layer)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = nsView.bounds
        CATransaction.commit()
    }
}
#endif

// MARK: - Cyberpunk Grid

struct CyberpunkGrid: View {
    @Environment(\.uiScale) private var scale

    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 44 * scale
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            ctx.stroke(path, with: .color(.cyan.opacity(0.07)), lineWidth: 0.5)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Cyberpunk Camera Filter

struct CyberpunkCameraFilter: View {
    var body: some View {
        ZStack {
            // Diagonal colour tint — hot pink → purple → cyan.
            // No blend mode: sits as a semi-transparent coloured lens over the feed.
            LinearGradient(
                colors: [
                    Color(red: 1.0,  green: 0.05, blue: 0.75).opacity(0.14),
                    Color(red: 0.55, green: 0.0,  blue: 1.0 ).opacity(0.10),
                    Color(red: 0.0,  green: 0.85, blue: 1.0 ).opacity(0.14),
                ],
                startPoint: .topTrailing,
                endPoint:   .bottomLeading
            )

            // Scanlines
            CyberpunkScanlines()

            // Coloured-edge vignette
            CyberpunkVignette()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct CyberpunkScanlines: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.black.opacity(0.10))
                )
                y += 4
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct CyberpunkVignette: View {
    var body: some View {
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height)
            ZStack {
                // Soft dark vignette around the edges.
                RadialGradient(
                    colors: [.clear, .black.opacity(0.48)],
                    center: .center,
                    startRadius: r * 0.45,
                    endRadius:   r * 1.10
                )
                // Cyan glow — left edge (P1).
                LinearGradient(
                    colors: [Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.22), .clear],
                    startPoint: .leading,
                    endPoint:   UnitPoint(x: 0.35, y: 0.5)
                )
                // Hot-pink glow — right edge (P2).
                LinearGradient(
                    colors: [.clear, Color(red: 1.0, green: 0.0, blue: 0.65).opacity(0.22)],
                    startPoint: UnitPoint(x: 0.65, y: 0.5),
                    endPoint:   .trailing
                )
                // Purple bars top and bottom.
                LinearGradient(
                    colors: [
                        Color(red: 0.5, green: 0.0, blue: 1.0).opacity(0.18),
                        .clear,
                        Color(red: 0.5, green: 0.0, blue: 1.0).opacity(0.18)
                    ],
                    startPoint: .top,
                    endPoint:   .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Animated interactive grid

struct GridRipple {
    let origin:    CGPoint   // normalised 0-1
    let color:     Color
    let startDate: Date = Date()
    static let duration: Double = 1.6

    func progress(at date: Date) -> Double {
        min(date.timeIntervalSince(startDate) / Self.duration, 1.0)
    }
    var isAlive: Bool { Date().timeIntervalSince(startDate) < Self.duration }
}

/// A Canvas-based grid that:
///  • Flows with a continuous sine-wave warp
///  • Brightens near each hand cursor (proximity glow)
///  • Fires an expanding shockwave ring on every note catch
struct AnimatedGrid: View {
    let handPositions: [CGPoint]  // normalised 0-1 screen positions
    let ripples:       [GridRipple]
    @Environment(\.uiScale) private var scale

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                draw(ctx: ctx, size: size, date: tl.date)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func draw(ctx: GraphicsContext, size: CGSize, date: Date) {
        let step: CGFloat = 42 * scale
        let t    = date.timeIntervalSinceReferenceDate
        let cols = Int(size.width  / step) + 2
        let rows = Int(size.height / step) + 2

        // Convert to pixel coords once.
        let hpx = handPositions.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }

        typealias Rip = (ox: CGFloat, oy: CGFloat, prog: Double, col: Color)
        let rips: [Rip] = ripples.compactMap {
            let p = $0.progress(at: date)
            guard p < 1 else { return nil }
            return ($0.origin.x * size.width, $0.origin.y * size.height, p, $0.color)
        }

        // Flat arrays: index = r*cols + c
        let n = rows * cols
        var vx = [CGFloat](repeating: 0, count: n)
        var vy = [CGFloat](repeating: 0, count: n)
        var vb = [Double](repeating: 0, count: n)

        for r in 0..<rows {
            for c in 0..<cols {
                let bx = CGFloat(c) * step - step
                let by = CGFloat(r) * step - step

                // Flowing wave warp (different speeds on each axis = organic feel)
                var px = bx + sin(CGFloat(r) * 0.28 + t * 1.10) * 6
                var py = by + cos(CGFloat(c) * 0.28 + t * 0.85) * 6
                var b  = 0.055

                // Hand proximity glow
                for h in hpx {
                    let dx = px - h.x, dy = py - h.y
                    let d  = sqrt(dx*dx + dy*dy)
                    if d < 130 { let f = 1 - d/130; b += Double(f * f) * 0.30 }
                }

                // Ripple shockwave: displace vertices on the ring + brighten
                for rip in rips {
                    let maxR = max(size.width, size.height)
                    let ring = CGFloat(rip.prog) * maxR
                    let dx   = px - rip.ox, dy = py - rip.oy
                    let d    = sqrt(dx*dx + dy*dy)
                    let gap  = abs(d - ring), w: CGFloat = 38
                    if gap < w {
                        let f    = 1 - gap / w
                        let push = f * sin(.pi * f) * 15 * CGFloat(1 - rip.prog)
                        if d > 0 { px += dx/d * push; py += dy/d * push }
                        b += Double(f * (1 - rip.prog)) * 0.52
                    }
                }

                let i = r * cols + c
                vx[i] = px; vy[i] = py; vb[i] = min(b, 0.90)
            }
        }

        // Draw line segments between adjacent vertices.
        // Colour is determined by which zone the midpoint falls in (cyan=P1, magenta=P2).
        for r in 0..<rows {
            for c in 0..<cols {
                let i  = r * cols + c
                let px = vx[i], py = vy[i], b = vb[i]

                if c + 1 < cols {
                    let j  = r * cols + (c + 1)
                    let qx = vx[j], qy = vy[j]
                    let avg = (b + vb[j]) / 2
                    let col = (px + qx) / 2 < size.width / 2 ? Color.cyan : Color.magenta
                    var p = Path()
                    p.move(to: .init(x: px, y: py))
                    p.addLine(to: .init(x: qx, y: qy))
                    ctx.stroke(p, with: .color(col.opacity(avg)), lineWidth: 0.8)
                }

                if r + 1 < rows {
                    let j  = (r + 1) * cols + c
                    let qx = vx[j], qy = vy[j]
                    let avg = (b + vb[j]) / 2
                    let col = (px + qx) / 2 < size.width / 2 ? Color.cyan : Color.magenta
                    var p = Path()
                    p.move(to: .init(x: px, y: py))
                    p.addLine(to: .init(x: qx, y: qy))
                    ctx.stroke(p, with: .color(col.opacity(avg)), lineWidth: 0.8)
                }
            }
        }
    }
}

// MARK: - Note View

struct NoteView: View {
    let note: NoteItem
    let size: CGSize
    @State private var pulse:    Bool    = false
    @State private var scanLine: CGFloat = -1   // sweeps -1 → +1
    @Environment(\.uiScale) private var scale

    var body: some View {
        let baseR  = note.noteSize.baseRadius * scale
        let frameW = baseR * 2.2

        ZStack {
            if note.caught {
                catchGlitch(baseR: baseR, frameW: frameW)
                    .opacity(max(0, 1 - note.catchProgress * 1.6))
            } else if note.noteKind == .obstacle {
                obstacleNote(baseR: baseR, frameW: frameW)
                    .scaleEffect(pulse ? 1.10 : 0.92)
                    .opacity(note.life)
            } else if note.noteKind == .trap {
                trapNote(baseR: baseR, frameW: frameW)
                    .scaleEffect(pulse ? 1.12 : 0.90)
                    .opacity(note.life)
            } else if note.noteKind == .frenzy {
                frenzyNote(baseR: baseR, frameW: frameW)
                    .scaleEffect(pulse ? 1.12 : 0.90)
                    .opacity(note.life)
            } else if note.noteKind == .ghost {
                ghostNote(baseR: baseR, frameW: frameW)
                    .scaleEffect(pulse ? 1.10 : 0.88)
                    .opacity(note.life)
            } else {
                liveNote(baseR: baseR, frameW: frameW)
                    .scaleEffect(pulse ? 1.07 : 0.94)
                    .opacity(note.life)
            }
        }
        .position(x: note.position.x * size.width,
                  y: note.position.y * size.height)
        .onAppear {
            withAnimation(.easeInOut(duration: note.noteKind == .obstacle ? 0.35 : note.noteSize.pulseDuration)
                .repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.linear(duration: 1.6)
                .repeatForever(autoreverses: false)) { scanLine = 1 }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Obstacle note (❄ freeze weapon)

    @ViewBuilder
    private func obstacleNote(baseR: CGFloat, frameW: CGFloat) -> some View {
        let iceBlue  = Color(red: 0.4,  green: 0.85, blue: 1.0)
        let iceWhite = Color(red: 0.85, green: 0.97, blue: 1.0)
        let scanY = scanLine * frameW * 0.44

        ZStack {
            // Outer diffuse halo
            HexagonShape()
                .fill(iceBlue.opacity(0.12))
                .frame(width: frameW * 2.6, height: frameW * 2.6)
                .blur(radius: baseR * 0.9)

            // Secondary ring
            HexagonShape()
                .stroke(iceWhite.opacity(0.22), lineWidth: 1)
                .frame(width: frameW + 14, height: frameW + 14)

            // Main hex frame with triple ice glow
            HexagonShape()
                .stroke(iceWhite, lineWidth: 2.5)
                .frame(width: frameW, height: frameW)
                .shadow(color: iceBlue.opacity(0.95), radius: 4)
                .shadow(color: iceBlue.opacity(0.60), radius: 12)
                .shadow(color: iceBlue.opacity(0.30), radius: 26)

            // Inner fill
            HexagonShape()
                .fill(iceBlue.opacity(0.10))
                .frame(width: frameW - 4, height: frameW - 4)

            // Inner rotated hexagon
            HexagonShape()
                .stroke(iceBlue.opacity(0.35), lineWidth: 1)
                .frame(width: frameW * 0.58, height: frameW * 0.58)
                .rotationEffect(.degrees(30))

            // Scan line
            LinearGradient(colors: [.clear, iceWhite.opacity(0.55), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: frameW * 0.80, height: 1.5)
                .offset(y: scanY)
                .frame(width: frameW, height: frameW)
                .clipped()

            // Snowflake symbol
            Text("❄")
                .font(.custom("Audiowide-Regular", size: baseR * 0.88))
                .foregroundColor(iceWhite)
                .shadow(color: iceBlue, radius: 8)

            // "FREEZE" label below
            Text("FREEZE")
                .font(.custom("Audiowide-Regular", size: max(8, baseR * 0.30)))
                .foregroundColor(iceBlue.opacity(0.9))
                .offset(y: frameW * 0.60)
                .tracking(1)
        }
    }

    // MARK: - Trap note (⚡ glitch hazard)

    @ViewBuilder
    private func trapNote(baseR: CGFloat, frameW: CGFloat) -> some View {
        let tc    = note.color      // electric orange (P1) or toxic lime (P2)
        let tgc   = note.glowColor  // slightly brighter shade
        let scanY = scanLine * frameW * 0.44

        ZStack {
            // Wide diffuse halo
            HexagonShape()
                .fill(tgc.opacity(0.15))
                .frame(width: frameW * 2.6, height: frameW * 2.6)
                .blur(radius: baseR * 0.9)

            // Outer secondary ring
            HexagonShape()
                .stroke(tc.opacity(0.25), lineWidth: 1)
                .frame(width: frameW + 14, height: frameW + 14)

            // Main hex — triple electric glow
            HexagonShape()
                .stroke(tc, lineWidth: 2.5)
                .frame(width: frameW, height: frameW)
                .shadow(color: tgc.opacity(0.95), radius: 4)
                .shadow(color: tgc.opacity(0.60), radius: 12)
                .shadow(color: tgc.opacity(0.30), radius: 26)

            // Inner fill
            HexagonShape()
                .fill(tgc.opacity(0.10))
                .frame(width: frameW - 4, height: frameW - 4)

            // Inner rotated hexagon
            HexagonShape()
                .stroke(tgc.opacity(0.40), lineWidth: 1)
                .frame(width: frameW * 0.58, height: frameW * 0.58)
                .rotationEffect(.degrees(30))

            // Scan line
            LinearGradient(colors: [.clear, tc.opacity(0.55), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: frameW * 0.80, height: 1.5)
                .offset(y: scanY)
                .frame(width: frameW, height: frameW)
                .clipped()

            // Lightning symbol
            Text("⚡")
                .font(.custom("Audiowide-Regular", size: baseR * 0.88))
                .foregroundColor(tc)
                .shadow(color: tgc, radius: 8)

            // Warning label
            Text("GLITCH")
                .font(.custom("Audiowide-Regular", size: max(8, baseR * 0.30)))
                .foregroundColor(tgc.opacity(0.9))
                .offset(y: frameW * 0.60)
                .tracking(1)
        }
    }

    // MARK: - Frenzy note (★ gold power-up)

    @ViewBuilder
    private func frenzyNote(baseR: CGFloat, frameW: CGFloat) -> some View {
        let gold  = Color(red: 1.0, green: 0.92, blue: 0.0)
        let glow  = Color(red: 1.0, green: 1.0,  blue: 0.40)
        let scanY = scanLine * frameW * 0.44
        ZStack {
            HexagonShape().fill(gold.opacity(0.14))
                .frame(width: frameW * 2.6, height: frameW * 2.6).blur(radius: baseR * 0.9)
            HexagonShape().stroke(gold.opacity(0.25), lineWidth: 1)
                .frame(width: frameW + 14, height: frameW + 14)
            HexagonShape().stroke(gold, lineWidth: 2.5)
                .frame(width: frameW, height: frameW)
                .shadow(color: glow.opacity(0.95), radius: 4)
                .shadow(color: glow.opacity(0.60), radius: 12)
                .shadow(color: glow.opacity(0.30), radius: 26)
            HexagonShape().fill(gold.opacity(0.10))
                .frame(width: frameW - 4, height: frameW - 4)
            HexagonShape().stroke(gold.opacity(0.40), lineWidth: 1)
                .frame(width: frameW * 0.58, height: frameW * 0.58).rotationEffect(.degrees(30))
            LinearGradient(colors: [.clear, gold.opacity(0.60), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: frameW * 0.80, height: 1.5).offset(y: scanY)
                .frame(width: frameW, height: frameW).clipped()
            Text("★")
                .font(.custom("Audiowide-Regular", size: baseR * 0.88))
                .foregroundColor(gold).shadow(color: glow, radius: 8)
            Text("FRENZY")
                .font(.custom("Audiowide-Regular", size: max(8, baseR * 0.28)))
                .foregroundColor(gold.opacity(0.9)).offset(y: frameW * 0.60).tracking(1)
        }
    }

    // MARK: - Ghost note (👻 purple weapon)

    @ViewBuilder
    private func ghostNote(baseR: CGFloat, frameW: CGFloat) -> some View {
        let purple = Color(red: 0.70, green: 0.40, blue: 1.0)
        let glow   = Color(red: 0.85, green: 0.60, blue: 1.0)
        let scanY  = scanLine * frameW * 0.44
        ZStack {
            HexagonShape().fill(purple.opacity(0.14))
                .frame(width: frameW * 2.6, height: frameW * 2.6).blur(radius: baseR * 0.9)
            HexagonShape().stroke(purple.opacity(0.22), lineWidth: 1)
                .frame(width: frameW + 14, height: frameW + 14)
            HexagonShape().stroke(purple, lineWidth: 2.5)
                .frame(width: frameW, height: frameW)
                .shadow(color: glow.opacity(0.95), radius: 4)
                .shadow(color: glow.opacity(0.60), radius: 12)
                .shadow(color: glow.opacity(0.30), radius: 26)
            HexagonShape().fill(purple.opacity(0.10))
                .frame(width: frameW - 4, height: frameW - 4)
            HexagonShape().stroke(glow.opacity(0.35), lineWidth: 1)
                .frame(width: frameW * 0.58, height: frameW * 0.58).rotationEffect(.degrees(30))
            LinearGradient(colors: [.clear, purple.opacity(0.55), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: frameW * 0.80, height: 1.5).offset(y: scanY)
                .frame(width: frameW, height: frameW).clipped()
            Text("👻")
                .font(.system(size: baseR * 0.80))
                .shadow(color: glow, radius: 8)
            Text("GHOST")
                .font(.custom("Audiowide-Regular", size: max(8, baseR * 0.28)))
                .foregroundColor(glow.opacity(0.9)).offset(y: frameW * 0.60).tracking(1)
        }
    }

    // MARK: - Live note

    @ViewBuilder
    private func liveNote(baseR: CGFloat, frameW: CGFloat) -> some View {
        let hex   = note.noteShape == .hexagon
        let scanY = scanLine * frameW * 0.44
        let gc    = note.glowColor
        let nc    = note.color

        ZStack {
            // ── 1. Wide diffuse glow halo ────────────────────────────────
            NoteFrame(hex: hex, w: frameW * 2.4, fill: gc.opacity(0.10))
                .blur(radius: baseR * 0.7)

            // ── 2. Secondary outer outline (depth / halo ring) ───────────
            NoteFrame(hex: hex, w: frameW + 10, stroke: gc.opacity(0.18), lw: 1)

            // ── 3. Main frame — intense neon triple-shadow glow ──────────
            NoteFrame(hex: hex, w: frameW, stroke: nc, lw: 2.5)
                .shadow(color: gc.opacity(0.95), radius: 3)
                .shadow(color: gc.opacity(0.55), radius: 10)
                .shadow(color: gc.opacity(0.25), radius: 22)

            // ── 4. Dim inner fill ────────────────────────────────────────
            NoteFrame(hex: hex, w: frameW - 4, fill: gc.opacity(0.07))

            // ── 5. Inner secondary shape (adds structural depth) ─────────
            if hex {
                // Inner hexagon rotated 30° — looks like a gear / lock-on ring
                HexagonShape()
                    .stroke(gc.opacity(0.32), lineWidth: 1)
                    .frame(width: frameW * 0.58, height: frameW * 0.58)
                    .rotationEffect(.degrees(30))
            } else {
                // Inner diamond (45° square) — classic HUD data-terminal look
                Rectangle()
                    .stroke(gc.opacity(0.32), lineWidth: 1)
                    .frame(width: frameW * 0.52, height: frameW * 0.52)
                    .rotationEffect(.degrees(45))
            }

            // ── 6. All ornamental geometry drawn in Canvas ────────────────
            noteDecoration(hex: hex, baseR: baseR, frameW: frameW, gc: gc, nc: nc)

            // ── 7. Scan line — clipped to frame bounds ───────────────────
            LinearGradient(colors: [.clear, nc.opacity(0.60), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: frameW * 0.80, height: 1.5)
                .offset(y: scanY)
                .frame(width: frameW, height: frameW)
                .clipped()

            // ── 8. Musical symbol ────────────────────────────────────────
            Text(note.symbol)
                .font(.custom("Audiowide-Regular", size: baseR * 0.88))
                .foregroundColor(nc)
                .shadow(color: gc, radius: 7)

            // ── 9. Point label ────────────────────────────────────────────
            Text("+\(note.points)")
                .font(.custom("Audiowide-Regular", size: max(8, baseR * 0.38)))
                .foregroundColor(nc.opacity(0.85))
                .offset(y: frameW * 0.56)
        }
    }

    // MARK: - Catch glitch animation

    @ViewBuilder
    private func catchGlitch(baseR: CGFloat, frameW: CGFloat) -> some View {
        let hex       = note.noteShape == .hexagon
        let prog      = CGFloat(note.catchProgress)
        let expand    = 1 + prog * 2.4
        let chrOffset = prog * 20
        let chrAlpha  = Double(max(0, 0.55 - prog))

        ZStack {
            // Red channel drifts right
            NoteFrame(hex: hex, w: frameW,
                      stroke: Color(red: 1, green: 0.1, blue: 0.3), lw: 2)
                .scaleEffect(expand)
                .offset(x:  chrOffset, y: -chrOffset * 0.25)
                .opacity(chrAlpha)

            // Glow channel drifts left
            NoteFrame(hex: hex, w: frameW, stroke: note.glowColor, lw: 2)
                .scaleEffect(expand)
                .offset(x: -chrOffset, y:  chrOffset * 0.25)
                .opacity(chrAlpha)

            // Glitch slices — deterministic horizontal bars that shear sideways
            Canvas { ctx, sz in
                let slices: [(CGFloat, CGFloat, CGFloat)] = [
                    (0.28, 0.70, -16), (0.52, 0.45, 20), (0.74, 0.60, -10)
                ]
                for (yF, wF, xS) in slices {
                    let y = sz.height * yF, w = sz.width * wF, xOff = xS * prog
                    var p = Path()
                    p.move(to: CGPoint(x: xOff, y: y))
                    p.addLine(to: CGPoint(x: w + xOff, y: y))
                    let a = max(0.0, 0.65 - Double(prog) * 1.3)
                    ctx.stroke(p, with: .color(note.color.opacity(a)), lineWidth: 2.5)
                }
            }
            .frame(width: frameW, height: frameW)
            .scaleEffect(expand)

            // Symbol drifts with the expansion
            Text(note.symbol)
                .font(.custom("Audiowide-Regular", size: baseR * 0.85))
                .foregroundColor(note.color)
                .shadow(color: note.glowColor, radius: 6)
                .scaleEffect(expand * 0.65 + 0.35)
        }
    }

    // MARK: - Ornamental geometry  (drawn in a Canvas slightly larger than the
    //          frame so corner brackets can extend outside the border)

    @ViewBuilder
    private func noteDecoration(hex: Bool, baseR: CGFloat, frameW: CGFloat,
                                gc: Color, nc: Color) -> some View {
        // Canvas is 30 % wider/taller than the frame; frame sits centred inside.
        let pad: CGFloat = frameW * 0.15
        let canvasW = frameW + pad * 2

        Canvas { ctx, sz in
            let cx = sz.width / 2, cy = sz.height / 2
            // Frame edges in canvas space
            let fx = pad, fy = pad, fw = frameW

            if hex {
                // ── Hexagon decorations ──────────────────────────────────
                let R = fw / 2   // radius of the main hex (frame circle)

                // Vertex squares (bright, clearly visible)
                for i in 0..<6 {
                    let a = CGFloat(i) / 6 * .pi * 2
                    let vx = cx + R * cos(a), vy = cy + R * sin(a)
                    ctx.fill(Path(CGRect(x: vx-4, y: vy-4, width: 8, height: 8)),
                             with: .color(gc))
                }

                // Mid-edge perpendicular tick marks
                for i in 0..<6 {
                    let a1 = CGFloat(i) / 6 * .pi * 2
                    let a2 = CGFloat(i+1) / 6 * .pi * 2
                    let mA = (a1 + a2) / 2
                    let mx = cx + R * cos(mA), my = cy + R * sin(mA)
                    let tx = -sin(mA) * 5, ty = cos(mA) * 5
                    var t = Path()
                    t.move(to:    CGPoint(x: mx-tx, y: my-ty))
                    t.addLine(to: CGPoint(x: mx+tx, y: my+ty))
                    ctx.stroke(t, with: .color(gc.opacity(0.70)), lineWidth: 1.8)
                }

                // Targeting lines from centre — gap in middle, dash from 48%→70% of R
                for i in 0..<6 {
                    let a = CGFloat(i) / 6 * .pi * 2
                    var line = Path()
                    line.move(to:    CGPoint(x: cx + R*0.48*cos(a), y: cy + R*0.48*sin(a)))
                    line.addLine(to: CGPoint(x: cx + R*0.70*cos(a), y: cy + R*0.70*sin(a)))
                    ctx.stroke(line, with: .color(gc.opacity(0.38)), lineWidth: 0.9)
                }

                // Central crosshair dot
                ctx.fill(Path(CGRect(x: cx-2, y: cy-2, width: 4, height: 4)),
                         with: .color(gc.opacity(0.75)))

            } else {
                // ── Square decorations ───────────────────────────────────
                let L = fw * 0.28   // bracket arm length
                let T: CGFloat = 2.5

                // Extended corner L-brackets — arms start at frame corner and
                // extend both along the frame edge AND outward past it
                for (ox, oy, sx, sy): (CGFloat, CGFloat, CGFloat, CGFloat) in [
                    (fx,    fy,    1,  1),    // top-left
                    (fx+fw, fy,   -1,  1),    // top-right
                    (fx,    fy+fw, 1, -1),    // bottom-left
                    (fx+fw, fy+fw,-1, -1)     // bottom-right
                ] {
                    // Horizontal arm (extends outward from corner)
                    ctx.fill(Path(CGRect(x: ox + sx * (-pad * 0.5),
                                         y: oy + sy * (-T * 0.5),
                                         width:  sx * (L + pad * 0.5),
                                         height: sy * T)),
                             with: .color(nc))
                    // Vertical arm
                    ctx.fill(Path(CGRect(x: ox + sx * (-T * 0.5),
                                         y: oy + sy * (-pad * 0.5),
                                         width:  sx * T,
                                         height: sy * (L + pad * 0.5))),
                             with: .color(nc))
                    // Bright terminal square at the tip of the horizontal arm
                    let tipX = ox + sx * L
                    ctx.fill(Path(CGRect(x: tipX - 3.5, y: oy - 3.5, width: 7, height: 7)),
                             with: .color(gc))
                }

                // Mid-edge notches (small bright rectangles centred on each side)
                let nL: CGFloat = 11, nT: CGFloat = 3
                let notches: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                    (cx - nL/2, fy - nT/2, nL, nT),          // top
                    (cx - nL/2, fy+fw - nT/2, nL, nT),        // bottom
                    (fx - nT/2, cy - nL/2, nT, nL),           // left
                    (fx+fw - nT/2, cy - nL/2, nT, nL)         // right
                ]
                for (nx, ny, nw, nh) in notches {
                    ctx.fill(Path(CGRect(x:nx,y:ny,width:nw,height:nh)),
                             with: .color(gc.opacity(0.85)))
                }

                // Thin data lines at 27% and 73% height (header / footer zone)
                for yFrac: CGFloat in [0.27, 0.73] {
                    let y = fy + fw * yFrac
                    let xPad = fw * 0.22
                    var line = Path()
                    line.move(to:    CGPoint(x: fx + xPad, y: y))
                    line.addLine(to: CGPoint(x: fx + fw - xPad, y: y))
                    ctx.stroke(line, with: .color(gc.opacity(0.22)), lineWidth: 0.8)
                }

                // Central crosshair dot
                ctx.fill(Path(CGRect(x: cx-2, y: cy-2, width: 4, height: 4)),
                         with: .color(gc.opacity(0.70)))
            }
        }
        .frame(width: canvasW, height: canvasW)
    }
}

// MARK: - NoteFrame helper
// Renders either a HexagonShape or a Rectangle as fill or stroke,
// keeping the NoteView body clean.

private struct NoteFrame: View {
    let hex: Bool
    let w:   CGFloat
    var fill:   Color? = nil
    var stroke: Color? = nil
    var lw:     CGFloat = 1

    var body: some View {
        if hex {
            if let f = fill   { HexagonShape().fill(f).frame(width:w,height:w) }
            if let s = stroke { HexagonShape().stroke(s, lineWidth:lw).frame(width:w,height:w) }
        } else {
            if let f = fill   { Rectangle().fill(f).frame(width:w,height:w) }
            if let s = stroke { Rectangle().stroke(s, lineWidth:lw).frame(width:w,height:w) }
        }
    }
}

// MARK: - Hexagon Shape

struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX, cy = rect.midY
        let r  = min(rect.width, rect.height) / 2
        for i in 0..<6 {
            let a  = CGFloat(i) / 6 * .pi * 2
            let pt = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Hand Cursor

struct HandCursor: View {
    let hand: HandState
    let color: Color
    let size: CGSize
    var frozen: Bool = false
    @Environment(\.uiScale) private var scale

    var body: some View {
        if hand.isActive {
            let r: CGFloat = (hand.isPinching ? 46 : 62) * scale
            let displayColor: Color = frozen ? Color(red: 0.4, green: 0.85, blue: 1.0) : color

            ZStack {
                Group {
                    Rectangle().frame(width: 48 * scale, height: 1)
                    Rectangle().frame(width: 1, height: 48 * scale)
                }
                .foregroundColor(displayColor.opacity(0.55))

                Circle()
                    .stroke(displayColor, lineWidth: 2.5)
                    .frame(width: r, height: r)
                    .shadow(color: displayColor, radius: (hand.isPinching ? 16 : 8) * scale)

                if hand.isPinching {
                    Circle()
                        .fill(displayColor.opacity(0.3))
                        .frame(width: r, height: r)
                }

                Text(frozen ? "🧊" : hand.isPinching ? "✊" : "✋")
                    .font(.custom("Audiowide-Regular", size: 18))
                    .opacity(0.7)
            }
            .position(x: hand.position.x * size.width, y: hand.position.y * size.height)
            .animation(.spring(response: 0.08, dampingFraction: 0.7), value: hand.isPinching)
            .animation(.interactiveSpring(response: 0.06, dampingFraction: 0.90), value: hand.position)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - HUD

struct HUDBar: View {
    @ObservedObject var gameManager: GameManager
    @Environment(\.uiScale) private var scale

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(gameManager.scoreP1)")
                        .font(.custom("Audiowide-Regular", size: 38 * scale))
                        .foregroundColor(gameManager.freezeP1.active ? Color(red: 0.4, green: 0.85, blue: 1.0) : .cyan)
                        .shadow(color: gameManager.freezeP1.active ? Color(red: 0.4, green: 0.85, blue: 1.0) : .cyan, radius: 12)
                    if gameManager.freezeP1.active {
                        Text("❄ \(Int(ceil(gameManager.freezeP1.timeLeft)))s")
                            .font(.custom("Audiowide-Regular", size: 13 * scale))
                            .foregroundColor(Color(red: 0.4, green: 0.85, blue: 1.0))
                            .shadow(color: Color(red: 0.4, green: 0.85, blue: 1.0), radius: 8)
                    }
                    if gameManager.frenzyP1.active {
                        Text("★ \(Int(ceil(gameManager.frenzyP1.timeLeft)))s")
                            .font(.custom("Audiowide-Regular", size: 13 * scale))
                            .foregroundColor(.yellow)
                            .shadow(color: .yellow, radius: 8)
                    }
                }
                Text("PLAYER 1")
                    .font(.custom("Audiowide-Regular", size: 10 * scale))
                    .foregroundColor(.cyan.opacity(0.7))
                    .tracking(4)
            }
            .padding(.leading, 24 * scale)

            Spacer()

            VStack(spacing: 2) {
                Text("\(gameManager.timeLeft)")
                    .font(.custom("Audiowide-Regular", size: 40 * scale))
                    .foregroundColor(gameManager.timeLeft <= 10 ? .red : .white)
                    .shadow(color: gameManager.timeLeft <= 10 ? .red : .white.opacity(0.4), radius: 14)
                Text("TIME")
                    .font(.custom("Audiowide-Regular", size: 10 * scale))
                    .foregroundColor(.gray)
                    .tracking(4)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if gameManager.freezeP2.active {
                        Text("❄ \(Int(ceil(gameManager.freezeP2.timeLeft)))s")
                            .font(.custom("Audiowide-Regular", size: 13 * scale))
                            .foregroundColor(Color(red: 0.4, green: 0.85, blue: 1.0))
                            .shadow(color: Color(red: 0.4, green: 0.85, blue: 1.0), radius: 8)
                    }
                    if gameManager.frenzyP2.active {
                        Text("★ \(Int(ceil(gameManager.frenzyP2.timeLeft)))s")
                            .font(.custom("Audiowide-Regular", size: 13 * scale))
                            .foregroundColor(.yellow)
                            .shadow(color: .yellow, radius: 8)
                    }
                    Text("\(gameManager.scoreP2)")
                        .font(.custom("Audiowide-Regular", size: 38 * scale))
                        .foregroundColor(gameManager.freezeP2.active ? Color(red: 0.4, green: 0.85, blue: 1.0) : .magenta)
                        .shadow(color: gameManager.freezeP2.active ? Color(red: 0.4, green: 0.85, blue: 1.0) : .magenta, radius: 12)
                }
                Text("PLAYER 2")
                    .font(.custom("Audiowide-Regular", size: 10 * scale))
                    .foregroundColor(.magenta.opacity(0.7))
                    .tracking(4)
            }
            .padding(.trailing, 24 * scale)
        }
        .padding(.vertical, 14 * scale)
        .background(.ultraThinMaterial.opacity(0.85))
    }
}

// MARK: - Beat Indicator

struct BeatIndicator: View {
    let quality: BeatQuality
    @State private var show = false
    @Environment(\.uiScale) private var scale

    var body: some View {
        Group {
            switch quality {
            case .perfect:
                Text("★ PERFECT BEAT ★")
                    .font(.custom("Audiowide-Regular", size: 14 * scale))
                    .foregroundColor(.yellow)
                    .shadow(color: .yellow, radius: 16)
                    .tracking(3)
            case .good:
                Text("♪ ON BEAT")
                    .font(.custom("Audiowide-Regular", size: 12 * scale))
                    .foregroundColor(.white.opacity(0.75))
                    .tracking(3)
            case .offBeat:
                EmptyView()
            }
        }
        .id(quality.label)   // forces re-render / re-trigger on each new catch
        .transition(.scale(scale: 0.5).combined(with: .opacity))
        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: quality.label)
    }
}

// MARK: - Freeze Overlay

enum PlayerSide { case left, right }

struct FreezeOverlay: View {
    let freeze: FreezeState
    let side: PlayerSide
    let size: CGSize
    @Environment(\.uiScale) private var scale

    var body: some View {
        let iceBlue = Color(red: 0.4, green: 0.85, blue: 1.0)
        let w = size.width / 2
        let h = size.height
        let x = side == .left ? w / 2 : size.width * 0.75

        ZStack {
            // Semi-transparent ice tint
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            iceBlue.opacity(0.22 + 0.06 * sin(freeze.glitchPhase * .pi * 2)),
                            Color(red: 0.7, green: 0.95, blue: 1.0).opacity(0.12)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: w, height: h)

            // Glitch scanlines
            Canvas { ctx, sz in
                let lineCount = 18
                for i in 0..<lineCount {
                    let yFrac = Double(i) / Double(lineCount)
                    let yPos  = yFrac * sz.height
                    // Each line shifts by a different glitch amount
                    let shift = CGFloat(sin((freeze.glitchPhase + yFrac) * .pi * 4)) * 8
                    var p = Path()
                    p.move(to:    CGPoint(x: shift, y: yPos))
                    p.addLine(to: CGPoint(x: sz.width + shift, y: yPos))
                    let alpha = 0.06 + 0.04 * abs(sin((freeze.glitchPhase + yFrac) * .pi * 3))
                    ctx.stroke(p, with: .color(iceBlue.opacity(alpha)), lineWidth: 1.5)
                }
            }
            .frame(width: w, height: h)

            // Frost border
            Rectangle()
                .stroke(iceBlue.opacity(0.55), lineWidth: 2)
                .frame(width: w - 2, height: h - 2)

            // "FROZEN" text + countdown
            VStack(spacing: 4) {
                Text("❄ FROZEN ❄")
                    .font(.custom("Audiowide-Regular", size: 22 * scale))
                    .foregroundColor(iceBlue)
                    .shadow(color: iceBlue, radius: 16)
                    .tracking(3)
                    .scaleEffect(1.0 + 0.04 * sin(freeze.glitchPhase * .pi * 6))
                Text("\(Int(ceil(freeze.timeLeft)))s")
                    .font(.custom("Audiowide-Regular", size: 36 * scale))
                    .foregroundColor(.white)
                    .shadow(color: iceBlue, radius: 12)
            }
        }
        .position(x: x, y: h / 2)
        .allowsHitTesting(false)
    }
}

// MARK: - Trap Glitch Overlay

struct TrapGlitchOverlay: View {
    let glitch: TrapGlitchState
    let side: PlayerSide
    let player: Int
    let size: CGSize
    @Environment(\.uiScale) private var scale

    var body: some View {
        let c = player == 1
            ? Color(red: 1.0, green: 0.40, blue: 0.0)
            : Color(red: 0.40, green: 1.0, blue: 0.0)
        let w = size.width / 2
        let h = size.height
        let x = side == .left ? w / 2 : size.width * 0.75

        ZStack {
            // Colour tint — pulses with glitchPhase
            Rectangle()
                .fill(LinearGradient(
                    colors: [
                        c.opacity(0.20 + 0.08 * sin(glitch.glitchPhase * .pi * 5)),
                        c.opacity(0.08)
                    ],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: w, height: h)

            // Scanlines with random horizontal jitter + glitch block artifacts
            Canvas { ctx, sz in
                for i in 0..<22 {
                    let yF = Double(i) / 22.0
                    let sh = CGFloat(sin((glitch.glitchPhase + yF * 2.1) * .pi * 7)) * 16
                    var p = Path()
                    p.move(to:    CGPoint(x: sh,            y: yF * sz.height))
                    p.addLine(to: CGPoint(x: sz.width + sh, y: yF * sz.height))
                    let a = 0.07 + 0.05 * abs(sin((glitch.glitchPhase + yF) * .pi * 4))
                    ctx.stroke(p, with: .color(c.opacity(a)), lineWidth: 1.8)
                }
                let seed = Int(glitch.glitchPhase * 7) % 7
                for i in 0..<4 {
                    let yF   = CGFloat((seed + i * 2) % 9) / 9.0
                    let bh   = CGFloat((seed + i) % 5 + 1)
                    let xOff = CGFloat(sin(Double(seed + i) * 1.3)) * 0.25 * sz.width
                    ctx.fill(Path(CGRect(x: xOff, y: yF * sz.height,
                                        width: sz.width, height: bh)),
                             with: .color(c.opacity(0.25)))
                }
            }
            .frame(width: w, height: h)

            // Border
            Rectangle()
                .stroke(c.opacity(0.65), lineWidth: 2)
                .frame(width: w - 2, height: h - 2)

            // Status text
            VStack(spacing: 4) {
                Text("⚡ GLITCHING ⚡")
                    .font(.custom("Audiowide-Regular", size: 19 * scale))
                    .foregroundColor(c)
                    .shadow(color: c, radius: 14)
                    .tracking(2)
                    .scaleEffect(1.0 + 0.05 * sin(glitch.glitchPhase * .pi * 9))
                Text("\(Int(ceil(glitch.timeLeft)))s")
                    .font(.custom("Audiowide-Regular", size: 36 * scale))
                    .foregroundColor(.white)
                    .shadow(color: c, radius: 10)
            }
        }
        .position(x: x, y: h / 2)
        .allowsHitTesting(false)
    }
}

struct ZoneLabels: View {
    @Environment(\.uiScale) private var scale

    var body: some View {
        HStack {
            Text("// P1 ZONE")
                .font(.custom("Audiowide-Regular", size: 11 * scale))
                .foregroundColor(.cyan.opacity(0.4))
                .tracking(2)
                .padding(.leading, 16)
            Spacer()
            Text("P2 ZONE //")
                .font(.custom("Audiowide-Regular", size: 11 * scale))
                .foregroundColor(.magenta.opacity(0.4))
                .tracking(2)
                .padding(.trailing, 16)
        }
        .padding(.bottom, 14)
    }
}
