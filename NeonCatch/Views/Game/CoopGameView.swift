import SwiftUI

// MARK: - Co-op Game View

struct CoopGameView: View {
    @ObservedObject var coopManager:  CoopGameManager
    @ObservedObject var gameManager:  GameManager
    @ObservedObject var tracker:      CameraHandTracker

    @State private var gridRipples: [GridRipple] = []
    @State private var shakeOffset  = CGSize.zero
    @State private var isShaking    = false
    @State private var flashAlpha: Double = 0
    @State private var flashColor:  Color  = .red

    var body: some View {
        GeometryReader { geo in
            let W      = geo.size.width
            let H      = geo.size.height
            let tier   = coopManager.groove.tier
            let groove = coopManager.groove.level

            let darkAlpha = max(0.0, (40.0 - groove) / 40.0) * 0.68
            let beatPulse = tier.rawValue >= 2
                ? max(0.0, 0.09 - coopManager.beatPhase * 0.11)
                : 0.0

            ZStack {
                // 1. Camera feed
                CameraPreview(tracker: tracker)
                    .ignoresSafeArea()
                    .opacity(tier.cameraOpacity)

                // 2. Dead-party darkness — lifts as groove rises
                Color.black
                    .opacity(darkAlpha)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // 4. Cyberpunk filter (fades in with groove)
                CyberpunkCameraFilter()
                    .opacity(0.3 + 0.7 * (groove / 100.0))

                // 5. Animated grid
                AnimatedGrid(
                    handPositions: (tracker.handsP1 + tracker.handsP2)
                        .filter(\.isActive).map(\.position),
                    ripples: gridRipples
                )
                .opacity(0.10 + 0.90 * tier.particleScale / 3.0)

                // 5. Beat pulse (hot/ultra only)
                tier.color
                    .opacity(beatPulse)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // 6. Hue cycling light show (ultra only) — no blur, single Color view
                if tier == .ultra {
                    Color(hue: coopManager.beatPhase, saturation: 1.0, brightness: 1.0)
                        .opacity(0.07)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // 7. Screen edge glow (hot/ultra)
                if tier.rawValue >= 2 {
                    let g = tier == .ultra ? 0.55 : 0.30
                    ZStack {
                        LinearGradient(colors: [tier.color.opacity(g), .clear],
                                       startPoint: .top,    endPoint: UnitPoint(x: 0.5, y: 0.14))
                            .frame(maxWidth: .infinity).frame(height: H * 0.14)
                            .frame(maxHeight: .infinity, alignment: .top)
                        LinearGradient(colors: [tier.color.opacity(g), .clear],
                                       startPoint: .bottom, endPoint: UnitPoint(x: 0.5, y: 0.86))
                            .frame(maxWidth: .infinity).frame(height: H * 0.14)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                        LinearGradient(colors: [tier.color.opacity(g * 0.7), .clear],
                                       startPoint: .leading, endPoint: UnitPoint(x: 0.09, y: 0.5))
                            .frame(width: W * 0.09).frame(maxHeight: .infinity)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        LinearGradient(colors: [tier.color.opacity(g * 0.7), .clear],
                                       startPoint: .trailing, endPoint: UnitPoint(x: 0.91, y: 0.5))
                            .frame(width: W * 0.09).frame(maxHeight: .infinity)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .allowsHitTesting(false)
                }

                // 8. Cross-hatch lane guides — fixed to real screen size
                Canvas { ctx, sz in
                    let alpha = 0.04 + 0.05 * tier.particleScale / 3.2
                    let style = StrokeStyle(lineWidth: 1, dash: [8, 14])
                    for pos in [0.20, 0.33, 0.46, 0.59, 0.72, 0.85] as [CGFloat] {
                        var h = Path()
                        h.move(to: CGPoint(x: 0,          y: pos * sz.height))
                        h.addLine(to: CGPoint(x: sz.width, y: pos * sz.height))
                        ctx.stroke(h, with: .color(.white.opacity(alpha)), style: style)
                        var v = Path()
                        v.move(to: CGPoint(x: pos * sz.width, y: 0))
                        v.addLine(to: CGPoint(x: pos * sz.width, y: sz.height))
                        ctx.stroke(v, with: .color(.white.opacity(alpha * 0.6)), style: style)
                    }
                }
                .frame(width: W, height: H)
                .position(x: W / 2, y: H / 2)
                .allowsHitTesting(false)

                // 9. Particles — fixed to real screen size
                Canvas { ctx, sz in
                    for p in coopManager.particles {
                        let alpha = max(0.0, p.life); guard alpha > 0 else { continue }
                        let scale    = CGFloat(tier.particleScale)
                        let cx       = p.position.x * sz.width
                        let cy       = p.position.y * sz.height
                        let half     = p.size * scale * 0.5
                        let glowHalf = half + p.size * scale
                        ctx.fill(Path(CGRect(x: cx-glowHalf, y: cy-glowHalf,
                                             width: glowHalf*2, height: glowHalf*2)),
                                 with: .color(p.color.opacity(alpha * 0.22)))
                        ctx.fill(Path(CGRect(x: cx-half, y: cy-half,
                                             width: p.size*scale, height: p.size*scale)),
                                 with: .color(p.color.opacity(alpha)))
                    }
                }
                .frame(width: W, height: H)
                .position(x: W / 2, y: H / 2)
                .allowsHitTesting(false)

                // 10. Confetti (spawned at DROP — single Canvas, no blurs)
                if !coopManager.confetti.isEmpty {
                    Canvas { ctx, sz in
                        for p in coopManager.confetti where p.life > 0 {
                            var rect = Path(CGRect(x: -p.size/2, y: -p.size/4,
                                                   width: p.size, height: p.size/2))
                            rect = rect.applying(
                                CGAffineTransform(translationX: p.x * sz.width,
                                                  y: p.y * sz.height)
                                    .rotated(by: p.rotation)
                            )
                            ctx.fill(rect, with: .color(p.color.opacity(p.life)))
                        }
                    }
                    .frame(width: W, height: H)
                    .position(x: W / 2, y: H / 2)
                    .allowsHitTesting(false)
                }

                // 11. Notes
                ForEach(coopManager.notes) { note in
                    CoopNoteView(note: note, size: geo.size, beatPhase: coopManager.beatPhase)
                }

                // 12. Score floats
                ForEach(coopManager.scoreFloats) { sf in
                    VStack(spacing: 2) {
                        if !sf.beatLabel.isEmpty {
                            Text(sf.beatLabel)
                                .font(.custom("Audiowide-Regular", size: 13))
                                .foregroundColor(sf.beatLabelColor)
                                .shadow(color: sf.beatLabelColor, radius: 8)
                        }
                        if sf.points > 0 {
                            Text("+\(sf.points)")
                                .font(.custom("Audiowide-Regular", size: 24))
                                .foregroundColor(sf.color)
                                .shadow(color: sf.color, radius: 10)
                        }
                    }
                    .opacity(max(0, sf.life))
                    .scaleEffect(sf.scale)
                    .position(x: sf.position.x * W, y: sf.position.y * H)
                    .allowsHitTesting(false)
                }

                // 13. Hand cursors
                if tracker.handsP1.count > 0 { HandCursor(hand: tracker.handsP1[0], color: .cyan,    size: geo.size) }
                if tracker.handsP1.count > 1 { HandCursor(hand: tracker.handsP1[1], color: .cyan,    size: geo.size) }
                if tracker.handsP2.count > 0 { HandCursor(hand: tracker.handsP2[0], color: .magenta, size: geo.size) }
                if tracker.handsP2.count > 1 { HandCursor(hand: tracker.handsP2[1], color: .magenta, size: geo.size) }

                // 14. Power-up overlays
                if coopManager.glitchActive {
                    let gs = TrapGlitchState(active: true, timeLeft: 3,
                                             glitchPhase: coopManager.beatPhase)
                    TrapGlitchOverlay(glitch: gs, side: .full, player: 0, size: geo.size)
                }
                if coopManager.blackoutActive {
                    BlackoutOverlay(
                        state: BlackoutState(active: true,
                                             timeLeft: BlackoutState.totalDuration,
                                             phase: coopManager.blackoutPhase),
                        size: geo.size)
                }
                if coopManager.speedBoostActive { speedBoostBanner }

                // 15. DROP visual — radiating lines + strobe + title
                if coopManager.dropActive {
                    let dp = coopManager.dropProgress
                    Canvas { ctx, sz in
                        let cx = sz.width/2, cy = sz.height/2
                        let maxLen = max(sz.width, sz.height) * 0.95
                        for i in 0..<16 {
                            let angle = Double(i) / 16.0 * .pi * 2
                            let len   = maxLen * CGFloat(dp)
                            var p = Path()
                            p.move(to: CGPoint(x: cx, y: cy))
                            p.addLine(to: CGPoint(x: cx + CGFloat(cos(angle))*len,
                                                  y: cy + CGFloat(sin(angle))*len))
                            ctx.stroke(p, with: .color(Color.yellow.opacity(0.45*(1-dp))),
                                       lineWidth: 2.5)
                        }
                    }
                    .allowsHitTesting(false)
                    Color.white
                        .opacity(sin(dp * .pi * 14) > 0.3 ? 0.18 : 0)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    let ta = dp < 0.25 ? dp/0.25 : dp > 0.75 ? (1-dp)/0.25 : 1.0
                    Text("★  D R O P  ★")
                        .font(.custom("Audiowide-Regular", size: 52))
                        .foregroundColor(.yellow)
                        .shadow(color: .yellow, radius: 10)
                        .tracking(6)
                        .opacity(ta)
                        .allowsHitTesting(false)
                }

                // 16. Impact flash
                flashColor
                    .opacity(flashAlpha)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // 17. Tier announcement — slams in, holds, fades out
                if let annTier = coopManager.announcementTier {
                    let p     = coopManager.announcementProgress
                    let scl   = p < 0.18 ? (2.0 - p / 0.18) : 1.0
                    let alpha = p < 0.18 ? p / 0.18
                                         : p > 0.72 ? max(0, (1.0 - p) / 0.28) : 1.0
                    let txt   = annTier == .ultra ? "★  ULTRA  ★" : "🔥  HOT  🔥"
                    Text(txt)
                        .font(.custom("Audiowide-Regular", size: 60))
                        .foregroundColor(annTier.color)
                        .shadow(color: annTier.color, radius: 12)
                        .tracking(8)
                        .scaleEffect(scl)
                        .opacity(alpha)
                        .allowsHitTesting(false)
                }

                // 18. HUD + countdown bar — use .position() to anchor to the real screen centre.
                VStack(spacing: 0) {
                    CoopHUD(coopManager: coopManager, availableWidth: W,
                            onPause: { coopManager.pauseGame() })
                    Spacer()
                    CoopBeatIndicator(quality: coopManager.lastQuality)
                        .padding(.bottom, 8)
                }
                .frame(width: W, height: H, alignment: .top)
                .position(x: W / 2, y: H / 2)

                // 19. Pause overlay
                if coopManager.isPaused {
                    PauseOverlay(
                        onResume: { withAnimation { coopManager.resumeGame() } },
                        onHome: {
                            coopManager.endGame()
                            gameManager.resetToStart()
                        }
                    )
                    .position(x: W / 2, y: H / 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .zIndex(10)
                }

                // 19. DROP countdown bar (bottom strip, visible 85–100 groove)
                let cdp = coopManager.dropCountdownProgress
                if cdp > 0 {
                    VStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Text("D R O P   I N . . .")
                                .font(.custom("Audiowide-Regular", size: 12))
                                .foregroundColor(.yellow.opacity(0.75 + 0.25 * cdp))
                                .shadow(color: .yellow, radius: 4)
                                .tracking(5)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.yellow.opacity(0.15))
                                    Rectangle()
                                        .fill(LinearGradient(
                                            colors: [Color(red: 1.0, green: 0.6, blue: 0.0),
                                                     .yellow, .white],
                                            startPoint: .leading, endPoint: .trailing))
                                        .frame(width: g.size.width * CGFloat(cdp))
                                }
                                .cornerRadius(2)
                            }
                            .frame(height: 5)
                        }
                        .padding(.horizontal, 50)
                        .padding(.bottom, 52)
                    }
                    .allowsHitTesting(false)
                }
            }
            .offset(shakeOffset)
            .onChange(of: tracker.handsP1) { _, h in coopManager.handsP1 = h }
            .onChange(of: tracker.handsP2) { _, h in coopManager.handsP2 = h }
            .onChange(of: coopManager.lastCatch) { _, event in
                guard let e = event else { return }
                gridRipples.append(GridRipple(origin: e.position, color: e.color))
                // More ripples at higher groove — screen reacts harder
                switch coopManager.groove.tier {
                case .hot:
                    gridRipples.append(GridRipple(origin: e.position, color: e.color))
                case .ultra:
                    gridRipples.append(GridRipple(origin: e.position, color: e.color))
                    gridRipples.append(GridRipple(origin: CGPoint(x: 0.5, y: 0.5), color: e.color))
                    gridRipples.append(GridRipple(
                        origin: CGPoint(x: 1 - e.position.x, y: 1 - e.position.y),
                        color: e.color))
                default: break
                }
                gridRipples = Array(gridRipples.suffix(12)).filter(\.isAlive)
            }
            .onChange(of: coopManager.impactSignal) { _, _ in
                triggerImpact(color: coopManager.impactFlashColor)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Impact Effects

    private func triggerImpact(color: Color) { triggerFlash(color: color); triggerShake() }

    private func triggerFlash(color: Color) {
        flashColor = color
        withAnimation(.easeIn(duration: 0.03)) { flashAlpha = 0.22 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.25)) { flashAlpha = 0 }
        }
    }

    private func triggerShake() {
        guard !isShaking else { return }
        isShaking = true
        let steps: [(CGFloat, CGFloat, Double)] = [
            (10,-4,0.00), (-8,3,0.06), (6,-2,0.11), (-4,1,0.16), (2,-1,0.20), (0,0,0.25)
        ]
        for (dx, dy, delay) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.05)) {
                    shakeOffset = CGSize(width: dx, height: dy)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { isShaking = false }
    }

    // MARK: - Speed Boost Banner

    private var speedBoostBanner: some View {
        VStack {
            Spacer()
            Text("❄  SPEED UP! NOTES FASTER  ❄")
                .font(.custom("Audiowide-Regular", size: 13))
                .foregroundColor(Color(red: 0.4, green: 0.85, blue: 1.0))
                .shadow(color: Color(red: 0.4, green: 0.85, blue: 1.0), radius: 10)
                .tracking(3)
                .padding(.vertical, 6).padding(.horizontal, 18)
                .background(Color.black.opacity(0.5))
                .cornerRadius(8)
                .padding(.bottom, 48)
        }
        .allowsHitTesting(false)
    }
}
