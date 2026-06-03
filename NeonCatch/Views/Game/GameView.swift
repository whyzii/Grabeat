import SwiftUI

// MARK: - Game View
// Composes all gameplay layers in the correct draw order.
// Each layer lives in its own file — this file only handles layout and wiring.

struct GameView: View {
    @ObservedObject var gameManager: GameManager
    @ObservedObject var tracker: CameraHandTracker
    @State private var gridRipples: [GridRipple] = []

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height

            ZStack {
                // 1. Camera feed
                CameraPreview(tracker: tracker)
                    .ignoresSafeArea()
                    .opacity(0.88)

                // 2. Cyberpunk colour filter
                CyberpunkCameraFilter()

                // 4. Animated interactive grid
                AnimatedGrid(
                    handPositions: (tracker.handsP1 + tracker.handsP2)
                        .filter(\.isActive).map(\.position),
                    ripples: gridRipples
                )

                // 4. Player zone tints — anchored to real screen coords to prevent
                // ZStack-width inflation from shifting the cyan/magenta split off-centre.
                HStack(spacing: 0) {
                    Color.cyan.opacity(0.06)
                    Color.magenta.opacity(0.06)
                }
                .frame(width: W, height: H)
                .position(x: W / 2, y: H / 2)
                .allowsHitTesting(false)

                // 5. Centre divider
                centerDivider(W: W, H: H)

                // 6. Pixel particles — frame to exact screen size so sz inside the
                // closure matches W×H rather than the ZStack's inflated dimensions.
                Canvas { ctx, sz in
                    for p in gameManager.particles {
                        let alpha = max(0.0, p.life)
                        guard alpha > 0 else { continue }
                        let cx   = p.position.x * sz.width
                        let cy   = p.position.y * sz.height
                        let half = p.size * 0.5
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
                .frame(width: W, height: H)
                .position(x: W / 2, y: H / 2)
                .allowsHitTesting(false)

                // 7. Notes
                ForEach(gameManager.notes) { note in
                    let glitching = note.player == 1 ? gameManager.trapGlitchP1.active
                                                     : gameManager.trapGlitchP2.active
                    let phase     = note.player == 1 ? gameManager.trapGlitchP1.glitchPhase
                                                     : gameManager.trapGlitchP2.glitchPhase
                    NoteView(note: note, size: geo.size)
                        // Near-invisible during glitch: max opacity 0.08, pulses between 0.02-0.08.
                        // Combined with the heavy overlay above, the note is essentially undetectable.
                        .opacity(glitching ? 0.02 + 0.06 * abs(sin(phase * .pi * 17)) : 1.0)
                        .blur(radius: glitching ? 6 : 0)
                }

                // 8. Score floats
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

                // 9. Hand cursors (up to 2 per player)
                if tracker.handsP1.count > 0 { HandCursor(hand: tracker.handsP1[0], color: .cyan,    size: geo.size, frozen: gameManager.freezeP1.active) }
                if tracker.handsP1.count > 1 { HandCursor(hand: tracker.handsP1[1], color: .cyan,    size: geo.size, frozen: gameManager.freezeP1.active) }
                if tracker.handsP2.count > 0 { HandCursor(hand: tracker.handsP2[0], color: .magenta, size: geo.size, frozen: gameManager.freezeP2.active) }
                if tracker.handsP2.count > 1 { HandCursor(hand: tracker.handsP2[1], color: .magenta, size: geo.size, frozen: gameManager.freezeP2.active) }

                // 10. Power-up overlays
                if gameManager.freezeP1.active {
                    FreezeOverlay(freeze: gameManager.freezeP1, side: .left, size: geo.size)
                }
                if gameManager.freezeP2.active {
                    FreezeOverlay(freeze: gameManager.freezeP2, side: .right, size: geo.size)
                }
                if gameManager.trapGlitchP1.active {
                    TrapGlitchOverlay(glitch: gameManager.trapGlitchP1, side: .left,  player: 1, size: geo.size)
                }
                if gameManager.trapGlitchP2.active {
                    TrapGlitchOverlay(glitch: gameManager.trapGlitchP2, side: .right, player: 2, size: geo.size)
                }
                if gameManager.blackout.active {
                    BlackoutOverlay(state: gameManager.blackout, size: geo.size)
                }

                // 11. HUD — use .position() to anchor to the real screen centre.
                VStack(spacing: 0) {
                    HUDBar(gameManager: gameManager, availableWidth: W,
                           onPause: { gameManager.pauseGame() })
                    Spacer()
                    BeatIndicator(quality: gameManager.lastBeatQuality)
                        .padding(.bottom, 8)
                    ZoneLabels()
                        .frame(width: W)
                }
                .frame(width: W, height: H, alignment: .top)
                .position(x: W / 2, y: H / 2)

                // 12. Pause overlay
                if gameManager.isPaused {
                    PauseOverlay(
                        onResume: { withAnimation { gameManager.resumeGame() } },
                        onHome:   { gameManager.resetToStart() }
                    )
                    .position(x: W / 2, y: H / 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .zIndex(10)
                }
            }
            // Forward hand state to GameManager for catch detection.
            // handsP1/P2 are NOT @Published — forwarding them doesn't trigger re-renders.
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

    // MARK: - Centre Divider

    @ViewBuilder
    private func centerDivider(W: CGFloat, H: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(
                    colors: [.cyan.opacity(0.18), .white.opacity(0.05), .magenta.opacity(0.18)],
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(width: 24)
            Rectangle()
                .fill(Color.white.opacity(0.55))
                .frame(width: 1.5)
        }
        .frame(maxHeight: .infinity)
        .allowsHitTesting(false)
        .position(x: W / 2, y: H / 2)
    }
}
