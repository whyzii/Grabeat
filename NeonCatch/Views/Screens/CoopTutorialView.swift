import SwiftUI

// MARK: - Co-op Tutorial (4 steps)
// Step 0 : Pinch — both players must pinch (or skip)
// Step 1 : Team Up + Groove Meter — cooperative screen + tier system
// Step 2 : Catch or Avoid? — special notes + duo note
// Step 3 : Beat the Clock — timer mechanics → calibration

struct CoopTutorialView: View {
    @ObservedObject var gameManager: GameManager
    @ObservedObject var tracker:     CameraHandTracker
    var isStandalone: Bool = false
    @Environment(\.uiScale) private var scale

    @State private var step: Int = 0
    @State private var p1Pinched    = false
    @State private var p2Pinched    = false
    @State private var stepForward  = true

    private let totalSteps = 3
    private let purple = Color(red: 0.6, green: 0.2, blue: 1.0)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TutorialBackground()
                Color.black.opacity(0.40).ignoresSafeArea()
                CyberpunkGrid()
                CyberpunkScanlines().opacity(0.35)

                VStack(spacing: 0) {
                    tutorialHeader

                    Spacer(minLength: 10 * scale)

                    Group {
                        switch step {
                        case 0:  VTStep0_Pinch(p1Pinched: p1Pinched, p2Pinched: p2Pinched)
                        case 1:  CTStep1_TeamUpGroove()
                        default: CTStep2_SpecialNotes()
                        }
                    }
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: stepForward ? .trailing : .leading).combined(with: .opacity),
                        removal:   .move(edge: stepForward ? .leading  : .trailing).combined(with: .opacity)
                    ))

                    Spacer(minLength: 16 * scale)
                    stepNav(geo: geo)
                    Spacer(minLength: 14 * scale)
                }
                .padding(.horizontal, 24 * scale)

                // Back arrow — top-left corner, tap (not pinch)
                VStack {
                    HStack {
                        Button(action: { retreat() }) {
                            Text("←")
                                .font(.custom("Audiowide-Regular", size: 18 * scale))
                                .foregroundColor(.white.opacity(0.75))
                                .frame(width: 40 * scale, height: 40 * scale)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.leading, 20 * scale)
                    .padding(.top, 16 * scale)
                    Spacer()
                }

                handCursors(geo: geo)
            }
            .ignoresSafeArea()
            .onChange(of: tracker.handsP1) { _, hands in handleP1(hands) }
            .onChange(of: tracker.handsP2) { _, hands in handleP2(hands) }
        }
    }

    // MARK: - Sub-views

    private var tutorialHeader: some View {
        VStack(spacing: 6 * scale) {
            Text("CO-OP TUTORIAL")
                .font(.custom("Audiowide-Regular", size: 11 * scale))
                .foregroundColor(purple.opacity(0.85))
                .tracking(5)
                .padding(.top, 20 * scale)
            StepDots(current: step, total: totalSteps, activeColor: purple)
        }
    }

    @ViewBuilder
    private func stepNav(geo: GeometryProxy) -> some View {
        if step == 0 {
            step0Nav(geo: geo)
        } else if step == totalSteps - 1 {
            VStack(spacing: 8 * scale) {
                if isStandalone {
                    MenuHandButton(
                        label: "MAIN MENU", color: .white,
                        tracker: tracker, screenSize: geo.size,
                        action: { gameManager.resetToStart() }
                    )
                } else {
                    MenuHandButton(
                        label: "BEGIN CALIBRATION", color: .white,
                        tracker: tracker, screenSize: geo.size,
                        action: { gameManager.beginCoopCalibration() }
                    )
                }
                holdHint
            }
        } else {
            VStack(spacing: 8 * scale) {
                MenuHandButton(
                    label: "NEXT", color: .white,
                    tracker: tracker, screenSize: geo.size,
                    action: { advance() }
                )
                holdHint
            }
        }
    }

    private var holdHint: some View {
        Text("HOLD TO CONTINUE")
            .font(.custom("Audiowide-Regular", size: 11 * scale))
            .foregroundColor(.white)
            .tracking(3)
    }

    private func step0Nav(geo: GeometryProxy) -> some View {
        Text(p1Pinched && p2Pinched ? "" : "BOTH PLAYERS PINCH TO CONTINUE")
            .font(.custom("Audiowide-Regular", size: 11 * scale))
            .foregroundColor(p1Pinched && p2Pinched ? purple : .white.opacity(0.60))
            .tracking(3)
            .animation(.easeInOut(duration: 0.3), value: p1Pinched && p2Pinched)
    }

    @ViewBuilder
    private func handCursors(geo: GeometryProxy) -> some View {
        if tracker.handsP1.count > 0 { HandCursor(hand: tracker.handsP1[0], color: .cyan,    size: geo.size) }
        if tracker.handsP1.count > 1 { HandCursor(hand: tracker.handsP1[1], color: .cyan,    size: geo.size) }
        if tracker.handsP2.count > 0 { HandCursor(hand: tracker.handsP2[0], color: .magenta, size: geo.size) }
        if tracker.handsP2.count > 1 { HandCursor(hand: tracker.handsP2[1], color: .magenta, size: geo.size) }
    }

    // MARK: - Logic

    private func advance() {
        stepForward = true
        withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
            step = min(step + 1, totalSteps - 1)
        }
    }

    private func retreat() {
        guard step > 0 else { gameManager.resetToStart(); return }
        let target = step - 1
        if target == 0 { p1Pinched = false; p2Pinched = false }
        stepForward = false
        withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
            step = target
        }
    }

    private func checkBothPinchedForAutoAdvance() {
        guard step == 0, p1Pinched, p2Pinched else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard self.step == 0 else { return }
            self.advance()
        }
    }
}

extension CoopTutorialView {
    fileprivate func handleP1(_ hands: [HandState]) {
        if step == 0, hands.contains(where: { $0.isPinching && $0.isActive }) {
            p1Pinched = true
            checkBothPinchedForAutoAdvance()
        }
    }

    fileprivate func handleP2(_ hands: [HandState]) {
        if step == 0, hands.contains(where: { $0.isPinching && $0.isActive }) {
            p2Pinched = true
            checkBothPinchedForAutoAdvance()
        }
    }
}

// MARK: - Step 1 · Team Up + Groove Meter (merged)

private struct CTStep1_TeamUpGroove: View {
    @Environment(\.uiScale) private var scale
    @State private var animLevel: Double = 0
    private let purple = Color(red: 0.6, green: 0.2, blue: 1.0)

    private let tiers: [(String, Color, String)] = [
        ("COLD",    Color(red: 0.30, green: 0.50, blue: 1.00), "0–15 · dark, sparse notes"),
        ("WARM",    .cyan,                                       "15–40 · cyan glow, more notes"),
        ("HOT",     Color(red: 1.00, green: 0.55, blue: 0.00),  "40–68 · orange edges, wild grid"),
        ("ULTRA ★", .yellow,                                     "68–100 · hue cycling, max chaos"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            GlitchTitle(text: "TEAM UP", fontSize: 36 * scale)
                .padding(.bottom, 28 * scale)

            VStack(spacing: 18 * scale) {
                BulletRow(icon: "✓", color: .cyan,
                          text: "No zones — any player can catch any note",
                          fontSize: 15 * scale)
                BulletRow(icon: "✓", color: .cyan,
                          text: "Notes fly in from all 4 edges of the screen",
                          fontSize: 15 * scale)
                BulletRow(icon: "✓", color: purple,
                          text: "Work together to keep the Groove Meter alive",
                          fontSize: 15 * scale)
            }
            .frame(maxWidth: 520 * scale)
            .padding(.bottom, 28 * scale)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(maxWidth: 420 * scale, maxHeight: 1)
                .padding(.bottom, 20 * scale)

            // Groove meter title
            GlitchTitle(text: "GROOVE METER", fontSize: 36 * scale)
                .padding(.bottom, 16 * scale)

            // Groove meter bar
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 380 * scale, height: 14 * scale)
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.30, green: 0.50, blue: 1.00),
                                 .cyan,
                                 Color(red: 1.00, green: 0.55, blue: 0.00),
                                 .yellow],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: 380 * scale * animLevel, height: 14 * scale)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: animLevel)

                ForEach([0.15, 0.40, 0.68], id: \.self) { frac in
                    Rectangle()
                        .fill(Color.white.opacity(0.50))
                        .frame(width: 1.5, height: 20 * scale)
                        .offset(x: 380 * scale * frac - 0.75)
                }
            }
            .frame(width: 380 * scale, height: 20 * scale)
            .padding(.bottom, 4 * scale)

            HStack(spacing: 0) {
                ForEach(tiers, id: \.0) { label, color, _ in
                    Text(label)
                        .font(.custom("Audiowide-Regular", size: 7 * scale))
                        .foregroundColor(color).tracking(1)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 380 * scale)
        }
        .onAppear { animLevel = 0.85 }
    }
}

// MARK: - Step 2 · Good vs Bad

// MARK: - Step 2 · Special Notes + Duo Note

private struct CTStep2_SpecialNotes: View {
    @Environment(\.uiScale) private var scale
    @State private var pulseScale: CGFloat = 1.0

    private struct NoteData: Identifiable {
        let id = UUID()
        let sym: String; let name: String
        let color: Color; let glowColor: Color
        let shape: NoteShape; let rotSpeed: Double
        let effect: String; let sub: String
    }

    private let notes: [NoteData] = [
        NoteData(sym: "❄", name: "FREEZE",
                 color: Color(red: 0.20, green: 0.60, blue: 1.00),
                 glowColor: Color(red: 0.40, green: 0.80, blue: 1.00),
                 shape: .circle, rotSpeed: 12,
                 effect: "Speed surge\nfor both players",
                 sub: ""),
        NoteData(sym: "⚡", name: "TRAP",
                 color: Color(red: 1.00, green: 0.15, blue: 0.25),
                 glowColor: Color(red: 1.00, green: 0.35, blue: 0.10),
                 shape: .triangle, rotSpeed: -22,
                 effect: "Screen GLITCH\nfor both players",
                 sub: ""),
        NoteData(sym: "★", name: "FRENZY",
                 color: Color(red: 1.0, green: 0.75, blue: 0.0),
                 glowColor: Color(red: 1.00, green: 1.00, blue: 0.85),
                 shape: .diamond, rotSpeed: 32,
                 effect: "+6 s  +9 groove\nfor the team",
                 sub: ""),
        NoteData(sym: "⊘", name: "BLACKOUT",
                 color: Color(red: 0.60, green: 0.00, blue: 1.00),
                 glowColor: Color(red: 0.85, green: 0.00, blue: 1.00),
                 shape: .octagon, rotSpeed: -7,
                 effect: "Full blackout\nfor both players",
                 sub: ""),
    ]

    var body: some View {
        VStack(spacing: 0) {
            GlitchTitle(text: "SPECIAL NOTES", fontSize: 40 * scale)
                .padding(.bottom, 16 * scale)

            // ── 4 special note cards ──────────────────────────────────────
            HStack(alignment: .top, spacing: 12 * scale) {
                ForEach(notes) { note in
                    VStack(spacing: 10 * scale) {
                        // Same animated Canvas icon used in the Versus tutorial
                        TutorialSpecialNoteIcon(
                            shape: note.shape,
                            symbol: note.sym,
                            color: note.color,
                            glowColor: note.glowColor,
                            rotSpeed: note.rotSpeed
                        )
                        Text(note.name)
                            .font(.custom("Audiowide-Regular", size: 13 * scale))
                            .foregroundColor(note.color).tracking(2)
                        Text(note.effect)
                            .font(.custom("Audiowide-Regular", size: 11 * scale))
                            .foregroundColor(.white.opacity(0.85)).tracking(1)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(note.sub)
                            .font(.custom("Audiowide-Regular", size: 9.5 * scale))
                            .foregroundColor(.gray).tracking(1)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12 * scale)
                    .background(note.color.opacity(0.08))
                    .overlay(Rectangle().stroke(note.color.opacity(0.30), lineWidth: 1))
                }
            }
            .frame(maxWidth: 700 * scale)
            .padding(.bottom, 14 * scale)

            // ── Duo Note banner ───────────────────────────────────────────
            HStack(spacing: 16 * scale) {
                // Animated hexagon icon
                ZStack {
                    Circle()
                        .stroke(Color.yellow.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 56 * scale, height: 56 * scale)
                        .scaleEffect(pulseScale)
                        .opacity(2.0 - pulseScale)
                        .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulseScale)
                    DuoHexagon()
                        .fill(Color.yellow.opacity(0.20))
                        .frame(width: 40 * scale, height: 40 * scale)
                        .shadow(color: .yellow, radius: 10)
                    DuoHexagon()
                        .stroke(Color.yellow, lineWidth: 2)
                        .frame(width: 40 * scale, height: 40 * scale)
                    Text("⬡")
                        .font(.system(size: 20 * scale))
                        .foregroundColor(.yellow)
                        .shadow(color: .yellow, radius: 8)
                }
                .frame(width: 60 * scale, height: 60 * scale)

                VStack(alignment: .leading, spacing: 6 * scale) {
                    Text("DUO NOTE")
                        .font(.custom("Audiowide-Regular", size: 14 * scale))
                        .foregroundColor(.yellow).tracking(3)
                    Text("BOTH players must pinch it simultaneously.")
                        .font(.custom("Audiowide-Regular", size: 11 * scale))
                        .foregroundColor(.white.opacity(0.75)).tracking(1)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 14 * scale) {
                        Text("")
                            .foregroundColor(.cyan)
                        Text("")
                            .foregroundColor(Color(red: 1, green: 0.3, blue: 0.3))
                    }
                    .font(.custom("Audiowide-Regular", size: 10 * scale))
                    .tracking(1)
                }
                Spacer(minLength: 0)
            }
            .padding(14 * scale)
            .frame(maxWidth: 700 * scale)
            .background(Color.yellow.opacity(0.06))
            .overlay(Rectangle().stroke(Color.yellow.opacity(0.30), lineWidth: 1))
        }
        .onAppear { pulseScale = 2.0 }
    }
}

// MARK: - Step 3 · Timer & Survival

private struct CTStep3_Timer: View {
    @Environment(\.uiScale) private var scale

    var body: some View {
        VStack(spacing: 0) {
            GlitchTitle(text: "BEAT THE CLOCK", fontSize: 32 * scale)
                .padding(.bottom, 8 * scale)

            Text("You start with 20 seconds. Catching notes adds time — missing loses it.")
                .font(.custom("Audiowide-Regular", size: 11 * scale))
                .foregroundColor(.gray).tracking(1)
                .multilineTextAlignment(.center)
                .padding(.bottom, 18 * scale)
                .frame(maxWidth: 550 * scale)

            VStack(spacing: 0) {
                TimerRow(symbol: "★",   label: "FRENZY catch",   delta: "+6.0 s", color: Color(red: 1, green: 0.85, blue: 0), isHeader: true)
                TimerRow(symbol: "♪",   label: "PERFECT catch",  delta: "+4.0 s", color: .yellow,  isHeader: false)
                TimerRow(symbol: "♪",   label: "GOOD catch",     delta: "+2.0 s", color: .white,   isHeader: false)
                TimerRow(symbol: "♪",   label: "Off-beat catch", delta: "+0.8 s", color: Color.white.opacity(0.50), isHeader: false)
                Divider().background(Color.white.opacity(0.12)).padding(.vertical, 4 * scale)
                TimerRow(symbol: "⊘⚡❄", label: "BAD note caught",  delta: "−2.5 s", color: Color(red: 1, green: 0.3, blue: 0.3), isHeader: false)
                TimerRow(symbol: "•",    label: "Good note missed",  delta: "−0.5 s", color: .gray,   isHeader: false)
                TimerRow(symbol: "⬡",    label: "DUO note missed",   delta: "−3.0 s", color: .orange, isHeader: false)
            }
            .frame(maxWidth: 500 * scale)
            .overlay(Rectangle().stroke(Color.white.opacity(0.12), lineWidth: 1))

            Text("Max timer cap: 60 s · Drain rate increases the longer you survive.")
                .font(.custom("Audiowide-Regular", size: 9 * scale))
                .foregroundColor(.white.opacity(0.32)).tracking(1)
                .padding(.top, 12 * scale)
        }
    }
}

private struct TimerRow: View {
    let symbol:   String
    let label:    String
    let delta:    String
    let color:    Color
    let isHeader: Bool
    @Environment(\.uiScale) private var scale

    var body: some View {
        HStack(spacing: 0) {
            Text(symbol)
                .font(.system(size: isHeader ? 14 * scale : 12 * scale))
                .frame(width: 44 * scale)
                .foregroundColor(color)
            Text(label)
                .font(.custom("Audiowide-Regular", size: 9 * scale))
                .foregroundColor(color.opacity(0.85)).tracking(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(delta)
                .font(.custom("Audiowide-Regular", size: 12 * scale))
                .foregroundColor(color)
                .frame(width: 68 * scale, alignment: .trailing)
        }
        .padding(.vertical, 7 * scale)
        .padding(.horizontal, 10 * scale)
        .background(isHeader ? color.opacity(0.10) : Color.clear)
    }
}

private struct DuoHexagon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX, cy = rect.midY
        let r  = min(rect.width, rect.height) / 2
        for i in 0..<6 {
            let a = CGFloat(i) * .pi / 3 - .pi / 6
            let pt = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Shared utility views

private struct BulletRow: View {
    let icon:     String
    let color:    Color
    let text:     String
    var fontSize: CGFloat? = nil
    @Environment(\.uiScale) private var scale

    var body: some View {
        let size = fontSize ?? (10 * scale)
        HStack(alignment: .top, spacing: 10 * scale) {
            Text(icon)
                .font(.custom("Audiowide-Regular", size: size + 2))
                .foregroundColor(color)
                .frame(width: size + 6)
            Text(text)
                .font(.custom("Audiowide-Regular", size: size))
                .foregroundColor(.white.opacity(0.85)).tracking(1)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
