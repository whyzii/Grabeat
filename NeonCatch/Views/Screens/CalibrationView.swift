import SwiftUI

// MARK: - Calibration View

struct CalibrationView: View {
    @ObservedObject var gameManager: GameManager
    @ObservedObject var tracker: CameraHandTracker
    @Environment(\.uiScale) private var scale

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreview(tracker: tracker)
                    .ignoresSafeArea()
                    .opacity(0.88)

                CyberpunkCameraFilter()

                HStack(spacing: 0) {
                    Color.cyan.opacity(0.07)
                    Color.magenta.opacity(0.07)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                CyberpunkGrid()

                // Centre divider
                ZStack {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.cyan.opacity(0.18), .white.opacity(0.05), .magenta.opacity(0.18)],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: 24)
                    Rectangle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 1.5)
                }
                .frame(maxHeight: .infinity)
                .allowsHitTesting(false)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)

                // Step-3 target dots — rendered before cursors so cursors appear on top
                if tracker.calibStep == .point {
                    CalibTargets(
                        targets: tracker.p1TargetPoints,
                        capturedCount: tracker.p1TargetIndex,
                        color: .cyan, geo: geo
                    )
                    CalibTargets(
                        targets: tracker.p2TargetPoints,
                        capturedCount: tracker.p2TargetIndex,
                        color: .magenta, geo: geo
                    )
                }

                CalibPanel(player: 1, progress: tracker.p1CalibProgress,
                           step: tracker.calibStep, color: .cyan, size: geo.size)
                CalibPanel(player: 2, progress: tracker.p2CalibProgress,
                           step: tracker.calibStep, color: .magenta, size: geo.size)

                if tracker.handsP1.count > 0 { HandCursor(hand: tracker.handsP1[0], color: .cyan,    size: geo.size) }
                if tracker.handsP1.count > 1 { HandCursor(hand: tracker.handsP1[1], color: .cyan,    size: geo.size) }
                if tracker.handsP2.count > 0 { HandCursor(hand: tracker.handsP2[0], color: .magenta, size: geo.size) }
                if tracker.handsP2.count > 1 { HandCursor(hand: tracker.handsP2[1], color: .magenta, size: geo.size) }

                VStack {
                    VStack(spacing: 6) {
                        Text("CALIBRATION — STEP \(tracker.calibStep.rawValue) / 3")
                            .font(.custom("Audiowide-Regular", size: 16 * scale))
                            .foregroundColor(.white.opacity(0.5))
                            .tracking(4)
                        Text(tracker.calibStep.stepTitle.uppercased())
                            .font(.custom("Audiowide-Regular", size: 22 * scale))
                            .foregroundColor(.white.opacity(0.85))
                            .tracking(3)
                    }
                    .padding(.top, 20)
                    Spacer()
                    Button { gameManager.resetToStart() } label: {
                        Text("BACK TO MENU")
                            .font(.custom("Audiowide-Regular", size: 11 * scale))
                            .foregroundColor(.gray)
                            .tracking(3)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 18)
                }

                if tracker.calibrationReady { CalibReadyOverlay() }
            }
        }
        .ignoresSafeArea()
        .onAppear { tracker.beginCalibration() }
    }
}

// MARK: - CalibrationStep display helpers

private extension CalibrationStep {
    var stepTitle: String {
        switch self {
        case .presence: return "Show Your Hand"
        case .range:    return "Sweep your hand across your zone"
        case .point:    return "Pinch each glowing target"
        }
    }

    var playerInstruction: String {
        switch self {
        case .presence: return "HOLD STILL"
        case .range:    return "SWEEP YOUR HAND"
        case .point:    return "PINCH THE TARGET"
        }
    }
}

// MARK: - Calibration Targets (step 3)
// Renders all 4 corner targets for one player.
// Captured = filled checkmark.  Active = pulsing ring.  Pending = dim outline.

private struct CalibTargets: View {
    let targets:       [CGPoint]
    let capturedCount: Int
    let color:         Color
    let geo:           GeometryProxy

    var body: some View {
        ForEach(targets.indices, id: \.self) { idx in
            let t         = targets[idx]
            let captured  = idx < capturedCount
            let active    = idx == capturedCount   // the one the player should aim at next

            TargetDot(captured: captured, active: active, color: color)
                .position(x: t.x * geo.size.width, y: t.y * geo.size.height)
        }
    }
}

// MARK: - Target Dot

private struct TargetDot: View {
    let captured: Bool
    let active:   Bool
    let color:    Color

    @State private var pulse = false

    var body: some View {
        ZStack {
            if captured {
                Circle()
                    .fill(color.opacity(0.55))
                    .frame(width: 56, height: 56)
                    .shadow(color: color, radius: 10)
                Circle()
                    .stroke(color, lineWidth: 2.5)
                    .frame(width: 56, height: 56)
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: color, radius: 4)

            } else if active {
                // Expanding ring — draws attention
                Circle()
                    .stroke(color.opacity(0.30), lineWidth: 2.5)
                    .frame(width: 90, height: 90)
                    .scaleEffect(pulse ? 1.30 : 1.0)
                    .opacity(pulse ? 0.0 : 0.80)
                    .animation(.easeOut(duration: 0.9).repeatForever(autoreverses: false), value: pulse)

                // Solid background disk — large and unmissable
                Circle()
                    .fill(color.opacity(0.20))
                    .frame(width: 72, height: 72)

                // Border ring
                Circle()
                    .stroke(color, lineWidth: 3)
                    .frame(width: 72, height: 72)
                    .shadow(color: color, radius: 8)

                // Crosshair
                Group {
                    Rectangle()
                        .fill(color.opacity(0.80))
                        .frame(width: 32, height: 2.5)
                    Rectangle()
                        .fill(color.opacity(0.80))
                        .frame(width: 2.5, height: 32)
                }

                // Centre dot
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .shadow(color: color, radius: 6)

            } else {
                // Pending — visible but clearly inactive
                Circle()
                    .stroke(color.opacity(0.30), lineWidth: 2)
                    .frame(width: 52, height: 52)
                Circle()
                    .fill(color.opacity(0.07))
                    .frame(width: 52, height: 52)
                Circle()
                    .fill(color.opacity(0.40))
                    .frame(width: 8, height: 8)
            }
        }
        .onAppear { if active { pulse = true } }
        .onChange(of: active) { _, isActive in pulse = isActive }
        .allowsHitTesting(false)
    }
}

// MARK: - Calibration Panel

private struct CalibPanel: View {
    let player:   Int
    let progress: Double
    let step:     CalibrationStep
    let color:    Color
    let size:     CGSize
    @Environment(\.uiScale) private var scale

    var body: some View {
        let confirmed = progress >= 1.0
        let cx: CGFloat = player == 1 ? size.width * 0.25 : size.width * 0.75

        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.20), lineWidth: 5)
                    .frame(width: 96 * scale, height: 96 * scale)
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 96 * scale, height: 96 * scale)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.08), value: progress)
                    .shadow(color: color.opacity(0.6), radius: confirmed ? 12 : 4)

                if confirmed {
                    Image(systemName: "checkmark")
                        .font(.custom("Audiowide-Regular", size: 32 * scale))
                        .foregroundColor(color)
                        .shadow(color: color, radius: 8)
                } else {
                    Canvas { ctx, sz in
                        let cx = sz.width / 2, cy = sz.height / 2
                        let r  = sz.width * 0.42
                        ctx.stroke(
                            Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)),
                            with: .color(color.opacity(0.50)), lineWidth: 1.5
                        )
                        for k in 0..<4 {
                            let a = Double(k) * .pi / 2
                            var p = Path()
                            p.move(to:    CGPoint(x: cx + CGFloat(cos(a)) * r * 0.50, y: cy + CGFloat(sin(a)) * r * 0.50))
                            p.addLine(to: CGPoint(x: cx + CGFloat(cos(a)) * r,        y: cy + CGFloat(sin(a)) * r))
                            ctx.stroke(p, with: .color(color.opacity(0.90)), lineWidth: 2)
                        }
                        let c: CGFloat = 7
                        var h = Path(); h.move(to: CGPoint(x: cx-c, y: cy)); h.addLine(to: CGPoint(x: cx+c, y: cy))
                        var v = Path(); v.move(to: CGPoint(x: cx, y: cy-c)); v.addLine(to: CGPoint(x: cx, y: cy+c))
                        ctx.stroke(h, with: .color(color.opacity(0.65)), lineWidth: 1.2)
                        ctx.stroke(v, with: .color(color.opacity(0.65)), lineWidth: 1.2)
                    }
                    .frame(width: 48 * scale, height: 48 * scale)
                    .opacity(progress > 0 ? 1 : 0.35)
                }
            }

            VStack(spacing: 4) {
                Text("PLAYER \(player)")
                    .font(.custom("Audiowide-Regular", size: 12 * scale))
                    .foregroundColor(color).tracking(4)
                Text(confirmed ? "STEP DONE ✓" : step.playerInstruction)
                    .font(.custom("Audiowide-Regular", size: 10 * scale))
                    .foregroundColor(color.opacity(0.70)).tracking(2)
            }
        }
        .position(x: cx, y: size.height * 0.78)
    }
}

// MARK: - Calibration Ready Overlay

private struct CalibReadyOverlay: View {
    @State private var appeared = false
    @Environment(\.uiScale) private var scale

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 10) {
                Text("READY!")
                    .font(.custom("Audiowide-Regular", size: 72 * scale))
                    .foregroundColor(.white)
                    .shadow(color: .cyan, radius: 24)
                Text("STARTING GAME...")
                    .font(.custom("Audiowide-Regular", size: 13 * scale))
                    .foregroundColor(.white.opacity(0.65))
                    .tracking(5)
            }
            .scaleEffect(appeared ? 1 : 0.5)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: appeared)
            .onAppear { appeared = true }
        }
    }
}
