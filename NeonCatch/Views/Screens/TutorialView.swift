import SwiftUI

// MARK: - Versus Tutorial (4 steps)
// Step 0 : Pinch         — both players must pinch (or skip)
// Step 1 : Your Zone     — interactive full-screen split; catch your colour note to advance
// Step 2 : Notes+Timing  — merged note sizes + beat timing; catch demo note to advance
// Step 3 : Special Notes — Freeze / Trap / Frenzy / Blackout → calibration

// Demo note positions (normalised 0–1)
private let zoneNoteP1Pos    = CGPoint(x: 0.25, y: 0.70)
private let zoneNoteP2Pos    = CGPoint(x: 0.75, y: 0.70)
private let zoneCatchRadius:  CGFloat = 0.18
private let noteCatchRadius:  CGFloat = 0.12

struct TutorialView: View {
    @ObservedObject var gameManager: GameManager
    @ObservedObject var tracker:     CameraHandTracker
    var isStandalone: Bool = false
    @Environment(\.uiScale) private var scale

    @State private var step:          Int  = 0
    @State private var p1Pinched           = false
    @State private var p2Pinched           = false
    @State private var p1ZoneTried         = false
    @State private var p2ZoneTried         = false
    @State private var noteDemoCaught      = false
    @State private var noteDemoPos         = CGPoint(x: 0.65, y: 0.38)
    @State private var stepForward         = true

    private let totalSteps = 4

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TutorialBackground()
                Color.black.opacity(0.35).ignoresSafeArea()
                CyberpunkGrid()
                CyberpunkScanlines().opacity(0.35)

                // Full-screen zone split — step 1 only (no horizontal padding)
                if step == 1 {
                    VTStep2_Zones(p1Tried: p1ZoneTried, p2Tried: p2ZoneTried)
                        .transition(.asymmetric(
                            insertion: .move(edge: stepForward ? .trailing : .leading).combined(with: .opacity),
                            removal:   .move(edge: stepForward ? .leading  : .trailing).combined(with: .opacity)
                        ))
                }

                VStack(spacing: 0) {
                    tutorialHeader

                    if step != 1 {
                        Spacer(minLength: 10 * scale)

                        Group {
                            switch step {
                            case 0:  VTStep0_Pinch(p1Pinched: p1Pinched, p2Pinched: p2Pinched)
                            case 2:  VTStep_NotesTiming(
                                     noteCaught: noteDemoCaught,
                                     screenSize: geo.size,
                                     onLargeNoteCenter: { raw in
                                         noteDemoPos = CGPoint(
                                             x: raw.x / geo.size.width,
                                             y: raw.y / geo.size.height
                                         )
                                     }
                                 )
                            default: VTStep4_SpecialNotes()
                            }
                        }
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: stepForward ? .trailing : .leading).combined(with: .opacity),
                            removal:   .move(edge: stepForward ? .leading  : .trailing).combined(with: .opacity)
                        ))
                    }

                    Spacer(minLength: 16 * scale)
                    stepNav(geo: geo)
                    Spacer(minLength: 14 * scale)
                }
                .padding(.horizontal, 24 * scale)

                // Zone trial demo notes — step 1 only
                if step == 1 {
                    DemoNoteTarget(caught: p1ZoneTried, color: .cyan,    label: "P1")
                        .position(x: geo.size.width  * zoneNoteP1Pos.x,
                                  y: geo.size.height * zoneNoteP1Pos.y)
                    DemoNoteTarget(caught: p2ZoneTried, color: .magenta, label: "P2")
                        .position(x: geo.size.width  * zoneNoteP2Pos.x,
                                  y: geo.size.height * zoneNoteP2Pos.y)

                    // Instruction text lifted to upper-centre so it doesn't crowd the notes
                    Text(p1ZoneTried && p2ZoneTried ? "" : "CATCH YOUR COLOUR NOTE TO CONTINUE")
                        .font(.custom("Audiowide-Regular", size: 12 * scale))
                        .foregroundColor(p1ZoneTried && p2ZoneTried ? .cyan : .white.opacity(0.55))
                        .tracking(3)
                        .animation(.easeInOut(duration: 0.25), value: p1ZoneTried && p2ZoneTried)
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.25)
                }

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
            .coordinateSpace(name: "tutorialRoot")
            .ignoresSafeArea()
            .onChange(of: tracker.handsP1) { _, hands in handleP1(hands) }
            .onChange(of: tracker.handsP2) { _, hands in handleP2(hands) }
        }
    }

    // MARK: - Sub-views

    private var tutorialHeader: some View {
        VStack(spacing: 6 * scale) {
            Text("VERSUS TUTORIAL")
                .font(.custom("Audiowide-Regular", size: 11 * scale))
                .foregroundColor(.cyan.opacity(0.65))
                .tracking(5)
                .padding(.top, 20 * scale)
            StepDots(current: step, total: totalSteps, activeColor: .cyan)
        }
    }

    @ViewBuilder
    private func stepNav(geo: GeometryProxy) -> some View {
        if step == 0 {
            step0Nav(geo: geo)
        } else if step == 1 {
            // Instruction text is positioned directly in the ZStack for step 1
            EmptyView()
        } else if step == 2 {
            // Notes+Timing — no NEXT; catch the floating demo note to advance
            Text(noteDemoCaught ? "CAUGHT! ADVANCING..." : "CATCH THE LARGE NOTE TO CONTINUE")
                .font(.custom("Audiowide-Regular", size: 12 * scale))
                .foregroundColor(noteDemoCaught ? .yellow : .white.opacity(0.85))
                .tracking(3)
                .animation(.easeInOut(duration: 0.25), value: noteDemoCaught)
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
                        action: { gameManager.beginCalibration() }
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
            .foregroundColor(p1Pinched && p2Pinched ? .cyan : .white.opacity(0.60))
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
        if target == 1 { p1ZoneTried = false; p2ZoneTried = false }
        if target == 2 { noteDemoCaught = false }
        stepForward = false
        withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
            step = target
        }
    }

    private func handleP1(_ hands: [HandState]) {
        if step == 0 {
            if hands.contains(where: { $0.isPinching && $0.isActive }) {
                p1Pinched = true
                checkBothPinchedForAutoAdvance()
            }
        } else if step == 1, !p1ZoneTried {
            catchZoneNote(hands: hands, notePos: zoneNoteP1Pos, isP1: true)
        } else if step == 2, !noteDemoCaught {
            catchDemoNoteCenter(hands: hands)
        }
    }

    private func handleP2(_ hands: [HandState]) {
        if step == 0 {
            if hands.contains(where: { $0.isPinching && $0.isActive }) {
                p2Pinched = true
                checkBothPinchedForAutoAdvance()
            }
        } else if step == 1, !p2ZoneTried {
            catchZoneNote(hands: hands, notePos: zoneNoteP2Pos, isP1: false)
        } else if step == 2, !noteDemoCaught {
            catchDemoNoteCenter(hands: hands)
        }
    }

    private func checkBothPinchedForAutoAdvance() {
        guard step == 0, p1Pinched, p2Pinched else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard self.step == 0 else { return }
            self.advance()
        }
    }

    private func catchDemoNoteCenter(hands: [HandState]) {
        let hit = hands.contains { h in
            guard h.isActive, h.isPinching else { return false }
            let dx = h.position.x - noteDemoPos.x
            let dy = h.position.y - noteDemoPos.y
            return dx*dx + dy*dy < noteCatchRadius * noteCatchRadius
        }
        guard hit else { return }
        noteDemoCaught = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard self.step == 2 else { return }
            self.advance()
        }
    }

    private func catchZoneNote(hands: [HandState], notePos: CGPoint, isP1: Bool) {
        let hit = hands.contains { h in
            guard h.isActive, h.isPinching else { return false }
            let dx = h.position.x - notePos.x
            let dy = h.position.y - notePos.y
            return dx*dx + dy*dy < zoneCatchRadius * zoneCatchRadius
        }
        guard hit else { return }
        if isP1 { p1ZoneTried = true } else { p2ZoneTried = true }
        if p1ZoneTried && p2ZoneTried {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard self.step == 1 else { return }
                self.advance()
            }
        }
    }
}

// MARK: - Step 0 · The Pinch  (shared with CoopTutorialView)

struct VTStep0_Pinch: View {
    let p1Pinched: Bool
    let p2Pinched: Bool
    @Environment(\.uiScale) private var scale

    var body: some View {
        VStack(spacing: 28 * scale) {
            GlitchTitle(text: "THE PINCH", fontSize: 36 * scale)

            Text("PINCH THUMB + INDEX OVER A NOTE TO CATCH IT")
                .font(.custom("Audiowide-Regular", size: 13 * scale))
                .foregroundColor(.white.opacity(0.85))
                .tracking(2)
                .multilineTextAlignment(.center)

            // Large centred P1 / P2 status indicators
            HStack(spacing: 72 * scale) {
                BigPinchStatusDot(pinched: p1Pinched, label: "P1", color: .cyan)
                BigPinchStatusDot(pinched: p2Pinched, label: "P2", color: .magenta)
            }
            .padding(.top, 8 * scale)
        }
    }
}

// MARK: - Step 1 · Your Zone  (full-screen interactive split)

private struct VTStep2_Zones: View {
    let p1Tried: Bool
    let p2Tried: Bool
    @Environment(\.uiScale) private var scale

    var body: some View {
        // Full-width split — mirrors the actual game layout
        HStack(spacing: 0) {

            // ── P1 left zone ──────────────────────────────────────────────
            ZStack {
                Color.cyan.opacity(p1Tried ? 0.14 : 0.07)
                    .animation(.easeInOut(duration: 0.4), value: p1Tried)

                VStack(spacing: 20 * scale) {
                    Text("◀  PLAYER 1")
                        .font(.custom("Audiowide-Regular", size: 22 * scale))
                        .foregroundColor(.cyan)
                        .tracking(4)
                    Text("CYAN NOTES")
                        .font(.custom("Audiowide-Regular", size: 15 * scale))
                        .foregroundColor(.cyan.opacity(0.70))
                        .tracking(3)
                    Text("Stand on the LEFT\nside of the camera")
                        .font(.custom("Audiowide-Regular", size: 14 * scale))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                }
                .padding(20 * scale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(Rectangle().stroke(Color.cyan.opacity(0.35), lineWidth: 1.5))

            // ── Centre divider ─────────────────────────────────────────────
            Rectangle()
                .fill(LinearGradient(
                    colors: [.cyan.opacity(0.5), .white.opacity(0.20), .magenta.opacity(0.5)],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: 2)

            // ── P2 right zone ──────────────────────────────────────────────
            ZStack {
                Color.magenta.opacity(p2Tried ? 0.14 : 0.07)
                    .animation(.easeInOut(duration: 0.4), value: p2Tried)

                VStack(spacing: 20 * scale) {
                    Text("PLAYER 2  ▶")
                        .font(.custom("Audiowide-Regular", size: 22 * scale))
                        .foregroundColor(.magenta)
                        .tracking(4)
                    Text("PINK NOTES")
                        .font(.custom("Audiowide-Regular", size: 15 * scale))
                        .foregroundColor(.magenta.opacity(0.70))
                        .tracking(3)
                    Text("Stand on the RIGHT\nside of the camera")
                        .font(.custom("Audiowide-Regular", size: 14 * scale))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                }
                .padding(20 * scale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(Rectangle().stroke(Color.magenta.opacity(0.35), lineWidth: 1.5))
        }
        .animation(.easeInOut(duration: 0.35), value: p1Tried)
        .animation(.easeInOut(duration: 0.35), value: p2Tried)
    }
}

// MARK: - Custom alignment: aligns on the bottom edge of each note square

private extension VerticalAlignment {
    private enum NoteSquareBottomID: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[.bottom] }
    }
    static let noteSquareBottom = VerticalAlignment(NoteSquareBottomID.self)
}

// MARK: - Step 2 · Notes + Timing  (merged — interactive)

private struct VTStep_NotesTiming: View {
    let noteCaught: Bool
    let screenSize: CGSize
    let onLargeNoteCenter: (CGPoint) -> Void
    @Environment(\.uiScale) private var scale

    private let sizes: [(String, CGFloat, Int)] = [
        ("TINY",   17, 2000),
        ("SMALL",  26,  800),
        ("MEDIUM", 36,  400),
        ("LARGE",  48,  100),
    ]

    var body: some View {
        VStack(spacing: 18 * scale) {
            GlitchTitle(text: "SCORE BIG", fontSize: 34 * scale)

            Text("Smaller note + perfect timing = MAXIMUM score")
                .font(.custom("Audiowide-Regular", size: 15 * scale))
                .foregroundColor(.yellow.opacity(0.70))
                .tracking(2)
                .multilineTextAlignment(.center)

            // ── Note Sizes ──────────────────────────────────────────────────
            VStack(spacing: 14 * scale) {
                Text("")
                    .font(.custom("Audiowide-Regular", size: 14 * scale))
                    .foregroundColor(.cyan.opacity(0.80))
                    .tracking(4)

                HStack(alignment: .noteSquareBottom, spacing: 26 * scale) {
                    ForEach(sizes, id: \.0) { name, radius, _ in
                        let isLarge = name == "LARGE"
                        VStack(spacing: 7 * scale) {
                            ZStack {
                                // Pulsing catch-hint ring on LARGE note only
                                if isLarge && !noteCaught {
                                    TimelineView(.animation) { tl in
                                        let t = tl.date.timeIntervalSinceReferenceDate
                                        let p = CGFloat(0.5 + 0.5 * sin(t * 2.2))
                                        Circle()
                                            .stroke(Color.white.opacity(0.25 + p * 0.35),
                                                    lineWidth: 1.5)
                                            .frame(width: CGFloat(radius) * 2.8 * scale,
                                                   height: CGFloat(radius) * 2.8 * scale)
                                            .scaleEffect(1.0 + p * 0.12)
                                    }
                                }
                                TutorialSquareNote(baseRadius: radius,
                                                   color: isLarge ? (noteCaught ? .cyan : .white) : .cyan)
                            }
                            // anchor the alignment guide on the bottom of this ZStack
                            .alignmentGuide(.noteSquareBottom) { d in d[.bottom] }
                            .background(
                                isLarge ? AnyView(
                                    GeometryReader { noteGeo -> Color in
                                        let frame = noteGeo.frame(in: .named("tutorialRoot"))
                                        DispatchQueue.main.async {
                                            onLargeNoteCenter(CGPoint(x: frame.midX, y: frame.midY))
                                        }
                                        return Color.clear
                                    }
                                ) : AnyView(EmptyView())
                            )

                            Text(name)
                                .font(.custom("Audiowide-Regular", size: 12 * scale))
                                .foregroundColor(isLarge ? .white : .cyan.opacity(0.85))
                                .tracking(2)

                            if isLarge && !noteCaught {
                                // Arrow + "PINCH ME" label to make action obvious
                                VStack(spacing: 2 * scale) {
                                    Text("▲ PINCH TO CONTINUE")
                                        .font(.custom("Audiowide-Regular", size: 9 * scale))
                                        .foregroundColor(.white.opacity(0.80))
                                        .tracking(1)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.horizontal, 4 * scale)
                                .padding(.vertical, 4 * scale)
                                .background(Color.white.opacity(0.10))
                                .cornerRadius(4 * scale)
                            } else if !isLarge {
                                // scores removed
                            } else {
                                // Caught state
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16 * scale, weight: .bold))
                                    .foregroundColor(.cyan)
                                    .shadow(color: .cyan, radius: 6)
                            }
                        }
                    }
                }

                
            }

            // ── Horizontal rule ─────────────────────────────────────────────
            Rectangle()
                .fill(Color.black.opacity(0.10))
                .frame(maxWidth: 560 * scale)
                .frame(height: 1)

            // ── Beat Timing ─────────────────────────────────────────────────
            VStack(spacing: 12 * scale) {
                

                Text("Catch on the beat for a bonus multiplier")
                    .font(.custom("Audiowide-Regular", size: 15 * scale))
                    .foregroundColor(.yellow.opacity(0.85))
                    .tracking(1)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 700 * scale)
    }
}

// MARK: - Square Note Preview  (real game note shape)

private struct TutorialSquareNote: View {
    let baseRadius: CGFloat   // logical note radius (17 / 26 / 36 / 48)
    let color: Color
    @Environment(\.uiScale) private var scale

    var body: some View {
        let frameW = baseRadius * 2.0 * scale
        TimelineView(.animation) { tl in
            let t     = tl.date.timeIntervalSinceReferenceDate
            let pulse = CGFloat(0.5 + 0.5 * sin(t * 2.3 + Double(baseRadius) * 0.3))
            ZStack {
                // Glow halo
                Rectangle()
                    .fill(color.opacity(0.10))
                    .frame(width: frameW * 1.7, height: frameW * 1.7)
                    .blur(radius: baseRadius * 0.45 * scale)
                // Cyan ghost (chromatic aberration)
                Rectangle()
                    .stroke(Color.cyan.opacity(0.45), lineWidth: 1.2)
                    .frame(width: frameW, height: frameW)
                    .offset(x: -1.5, y: -0.8)
                // Magenta ghost
                Rectangle()
                    .stroke(Color(red: 1, green: 0, blue: 1).opacity(0.45), lineWidth: 1.2)
                    .frame(width: frameW, height: frameW)
                    .offset(x: 1.5, y: 0.8)
                // Main square frame — pulses
                Rectangle()
                    .stroke(color, lineWidth: 1.8 + pulse * 1.2)
                    .frame(width: frameW * (0.94 + 0.06 * pulse),
                           height: frameW * (0.94 + 0.06 * pulse))
                // Symbol
                Text("♪")
                    .font(.custom("Audiowide-Regular", size: baseRadius * 0.82 * scale))
                    .foregroundColor(.white)
                    .shadow(color: color, radius: 3 + pulse * 5)
            }
        }
        .frame(width: frameW * 1.7, height: frameW * 1.7)
    }
}

// MARK: - Step 4 · Special Notes

private struct VTStep4_SpecialNotes: View {
    @Environment(\.uiScale) private var scale

    // (symbol, name, mainColor, glowColor, shape, rotSpeed, effect, sub)
    private let notes: [(String, String, Color, Color, NoteShape, Double, String, String)] = [
        ("❄", "FREEZE",
         Color(red: 0.20, green: 0.60, blue: 1.00),
         Color(red: 0.40, green: 0.80, blue: 1.00),
         .circle, 12,
         "Catch to FREEZE\nopponent for 3 s",
         ""),

        ("⚡", "TRAP",
         Color(red: 1.00, green: 0.15, blue: 0.25),
         Color(red: 1.00, green: 0.35, blue: 0.10),
         .triangle, -22,
         "Catching it GLITCHES\nYOUR own screen 3 s",
         ""),

        ("★",  "FRENZY",
         Color.white,
         Color(red: 0.0, green: 0.95, blue: 1.0),
         .diamond, 32,
         "2× POINTS\nfor 5 seconds",
         ""),

        ("⊘",  "BLACKOUT",
         Color(red: 0.60, green: 0.00, blue: 1.00),
         Color(red: 0.85, green: 0.00, blue: 1.00),
         .octagon, -7,
         "−1 000 you\n−2 000 opponent",
         ""),
    ]

    var body: some View {
        VStack(spacing: 0) {
            GlitchTitle(text: "SPECIAL NOTES", fontSize: 38 * scale)
                .padding(.bottom, 20 * scale)

            HStack(alignment: .top, spacing: 14 * scale) {
                ForEach(notes, id: \.0) { sym, name, color, glow, shape, rot, effect, sub in
                    VStack(spacing: 10 * scale) {
                        TutorialSpecialNoteIcon(shape: shape, symbol: sym,
                                                color: color, glowColor: glow,
                                                rotSpeed: rot)
                        Text(name)
                            .font(.custom("Audiowide-Regular", size: 14 * scale))
                            .foregroundColor(color).tracking(3)
                        Text(effect)
                            .font(.custom("Audiowide-Regular", size: 12 * scale))
                            .foregroundColor(.white.opacity(0.90)).tracking(1)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(sub)
                            .font(.custom("Audiowide-Regular", size: 10 * scale))
                            .foregroundColor(.gray).tracking(1)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14 * scale)
                    .background(color.opacity(0.09))
                    .overlay(Rectangle().stroke(color.opacity(0.35), lineWidth: 1.2))
                }
            }
            .frame(maxWidth: 820 * scale)
        }
    }
}

// MARK: - Special Note Icon (real game shape via Canvas)

struct TutorialSpecialNoteIcon: View {
    let shape:     NoteShape
    let symbol:    String
    let color:     Color
    let glowColor: Color
    let rotSpeed:  Double
    @Environment(\.uiScale) private var scale

    private let idSeed: UInt64 = 0xABCD5678

    var body: some View {
        let r = 34.0 * scale
        TimelineView(.animation) { tl in
            let t       = tl.date.timeIntervalSinceReferenceDate
            let gPhase  = t.truncatingRemainder(dividingBy: 2.7)
            let gFrac   = CGFloat(gPhase < 0.10 ? gPhase / 0.10 : 0)
            let chrX    = 2.0 + CGFloat(sin(t * 0.9)) + gFrac * 8
            let chrY    = 0.8 + CGFloat(cos(t * 0.7)) * 0.6 + gFrac * 3
            let pulseF  = CGFloat(0.5 + 0.5 * sin(t * 2 * .pi / 1.5))
            let rotDeg  = t * rotSpeed

            ZStack {
                // Atmospheric glow
                Circle()
                    .fill(glowColor.opacity(0.12))
                    .frame(width: r * 2.6, height: r * 2.6)
                    .blur(radius: r * 0.5)

                Canvas { ctx, sz in
                    let cx = sz.width / 2, cy = sz.height / 2
                    let rr = r * (0.92 + 0.08 * pulseF)

                    ctx.translateBy(x: cx, y: cy)
                    ctx.rotate(by: .degrees(rotDeg))
                    ctx.translateBy(x: -cx, y: -cy)

                    let segsMain = buildNoteSegments(shape: shape, cx: cx,        cy: cy,        r: rr, gFrac: gFrac, idSeed: idSeed)
                    let segsL    = buildNoteSegments(shape: shape, cx: cx - chrX, cy: cy - chrY, r: rr, gFrac: gFrac, idSeed: idSeed)
                    let segsR    = buildNoteSegments(shape: shape, cx: cx + chrX, cy: cy + chrY, r: rr, gFrac: gFrac, idSeed: idSeed)

                    // Outer glow stroke
                    for seg in segsMain {
                        ctx.stroke(seg, with: .color(glowColor.opacity(0.30 + Double(gFrac) * 0.20)),
                                   lineWidth: 8.0)
                    }
                    // Chromatic ghost — cyan left
                    for seg in segsL {
                        ctx.stroke(seg, with: .color(Color(red: 0.0, green: 0.95, blue: 1.0).opacity(0.65)),
                                   lineWidth: 2.0)
                    }
                    // Chromatic ghost — magenta right
                    for seg in segsR {
                        ctx.stroke(seg, with: .color(Color(red: 1.0, green: 0.05, blue: 1.0).opacity(0.65)),
                                   lineWidth: 2.0)
                    }
                    // Main stroke
                    for seg in segsMain {
                        ctx.stroke(seg, with: .color(color), lineWidth: 3.0)
                    }
                }
                .frame(width: r * 2.8, height: r * 2.8)

                // Symbol with chromatic aberration
                let chrOff = CGFloat(2.0 + Double(gFrac) * 6)
                ZStack {
                    Text(symbol).foregroundColor(Color(red: 0.0, green: 0.95, blue: 1.0).opacity(0.50))
                        .offset(x: -chrOff, y: -chrOff * 0.35)
                    Text(symbol).foregroundColor(Color(red: 1.0, green: 0.05, blue: 1.0).opacity(0.50))
                        .offset(x:  chrOff, y:  chrOff * 0.35)
                    Text(symbol).foregroundColor(color)
                        .shadow(color: glowColor, radius: 8)
                }
                .font(.system(size: r * 0.65))
            }
        }
        .frame(width: 34 * 2.8 * scale, height: 34 * 2.8 * scale)
    }
}

// MARK: - Game-style floating demo note  (step 2 interactive overlay)

struct TutorialGameNoteDemo: View {
    let caught: Bool
    @Environment(\.uiScale) private var scale
    @State private var burstScale: CGFloat = 1.0
    @State private var showBurst           = false

    private let beat = 60.0 / 123.046875   // matches the game's BPM

    var body: some View {
        let frameW = 60.0 * scale
        ZStack {
            if showBurst {
                // Catch burst — expanding square rings
                Rectangle()
                    .stroke(Color.cyan.opacity(max(0, 0.7 - Double(burstScale - 1) * 0.5)), lineWidth: 2)
                    .frame(width: frameW, height: frameW)
                    .scaleEffect(burstScale)
                Rectangle()
                    .stroke(Color(red: 1, green: 0, blue: 1).opacity(max(0, 0.5 - Double(burstScale - 1) * 0.4)), lineWidth: 1.5)
                    .frame(width: frameW, height: frameW)
                    .scaleEffect(burstScale * 1.15)
                Image(systemName: "checkmark")
                    .font(.system(size: 22 * scale, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .cyan, radius: 8)
            } else {
                TimelineView(.animation) { tl in
                    let t      = tl.date.timeIntervalSinceReferenceDate
                    let phase  = t.truncatingRemainder(dividingBy: beat) / beat
                    let pulse  = CGFloat(phase < 0.15 ? phase / 0.15 : max(0, 1 - (phase - 0.15) / 0.85))

                    ZStack {
                        // Glow halo (pulses to beat)
                        Rectangle()
                            .fill(Color.cyan.opacity(0.10 + Double(pulse) * 0.12))
                            .frame(width: frameW * 1.8, height: frameW * 1.8)
                            .blur(radius: 12 + pulse * 8)

                        // Chromatic aberration offset layers
                        Rectangle()
                            .stroke(Color.cyan.opacity(0.50), lineWidth: 1.5)
                            .frame(width: frameW, height: frameW)
                            .offset(x: -2, y: -1)
                        Rectangle()
                            .stroke(Color(red: 1, green: 0, blue: 1).opacity(0.50), lineWidth: 1.5)
                            .frame(width: frameW, height: frameW)
                            .offset(x: 2, y: 1)

                        // Main square frame — grows on beat
                        Rectangle()
                            .stroke(Color.white, lineWidth: 2.5 + pulse * 1.5)
                            .frame(width: frameW * (0.94 + 0.08 * pulse),
                                   height: frameW * (0.94 + 0.08 * pulse))

                        // Symbol
                        Text("♪")
                            .font(.custom("Audiowide-Regular", size: 24 * scale))
                            .foregroundColor(.white)
                            .shadow(color: .cyan, radius: 6 + pulse * 8)
                    }
                }

                // "CATCH ME" label below
                Text("CATCH ME")
                    .font(.custom("Audiowide-Regular", size: 9 * scale))
                    .foregroundColor(.white.opacity(0.55))
                    .tracking(2)
                    .offset(y: frameW * 0.75)
            }
        }
        .frame(width: frameW * 2, height: frameW * 2)
        .onChange(of: caught) { _, isCaught in
            guard isCaught else { return }
            burstScale = 1.0
            showBurst  = true
            withAnimation(.easeOut(duration: 0.6)) { burstScale = 2.8 }
        }
    }
}

private struct BeatTier: View {
    let label:  String
    let window: String
    let mult:   String
    let color:  Color
    @Environment(\.uiScale) private var scale

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.custom("Audiowide-Regular", size: 11 * scale))
                .foregroundColor(color).tracking(2)
                .frame(width: 140 * scale, alignment: .leading)
            Text(window)
                .font(.custom("Audiowide-Regular", size: 9 * scale))
                .foregroundColor(.gray).tracking(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(mult)
                .font(.custom("Audiowide-Regular", size: 14 * scale))
                .foregroundColor(color)
                .frame(width: 40 * scale, alignment: .trailing)
        }
        .padding(.vertical, 7 * scale)
        .padding(.horizontal, 12 * scale)
        .background(color.opacity(0.07))
        .overlay(Rectangle().stroke(color.opacity(0.20), lineWidth: 1))
    }
}

private struct BeatPulseDemo: View {
    @Environment(\.uiScale) private var scale

    var body: some View {
        TimelineView(.animation) { tl in
            let t     = tl.date.timeIntervalSinceReferenceDate
            let beat  = 60.0 / 123.046875
            let phase = t.truncatingRemainder(dividingBy: beat) / beat
            let pulse = phase < 0.15 ? phase / 0.15 : max(0, 1 - (phase - 0.15) / 0.85)

            Canvas { ctx, size in
                let cx = size.width / 2, cy = size.height / 2
                let r  = (18 + 14 * pulse) * scale
                var gCtx = ctx
                gCtx.addFilter(.shadow(color: .cyan, radius: 4 + 12 * pulse))
                gCtx.stroke(
                    Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)),
                    with: .color(.cyan.opacity(0.5 + 0.5 * pulse)),
                    lineWidth: 2.5
                )
                ctx.draw(
                    Text("♩ ♩ ♩")
                        .font(.custom("Audiowide-Regular", size: 11 * scale))
                        .foregroundColor(.white.opacity(0.45 + 0.45 * pulse)),
                    at: CGPoint(x: cx, y: cy + 30 * scale), anchor: .center
                )
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Shared: Step Dots

struct StepDots: View {
    let current:     Int
    let total:       Int
    let activeColor: Color
    @Environment(\.uiScale) private var scale

    var body: some View {
        HStack(spacing: 8 * scale) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current ? activeColor : activeColor.opacity(0.25))
                    .frame(width: i == current ? 20 * scale : 8 * scale, height: 4 * scale)
                    .animation(.easeInOut(duration: 0.25), value: current)
            }
        }
    }
}

// MARK: - Shared: Pinch Status Dot

struct PinchStatusDot: View {
    let pinched: Bool
    let label:   String
    let color:   Color
    let scale:   CGFloat

    var body: some View {
        VStack(spacing: 5 * scale) {
            ZStack {
                Circle()
                    .fill(pinched ? color : Color.white.opacity(0.08))
                    .frame(width: 40 * scale, height: 40 * scale)
                    .shadow(color: pinched ? color : .clear, radius: 10)
                Circle()
                    .stroke(color.opacity(pinched ? 1 : 0.35), lineWidth: 1.5)
                    .frame(width: 40 * scale, height: 40 * scale)
                if pinched {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16 * scale, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("✋")
                        .font(.system(size: 16 * scale))
                        .opacity(0.5)
                }
            }
            Text(label)
                .font(.custom("Audiowide-Regular", size: 9 * scale))
                .foregroundColor(color.opacity(0.80)).tracking(2)
        }
    }
}

// MARK: - Shared: Big Pinch Status Dot (Step 0 centre display)

struct BigPinchStatusDot: View {
    let pinched: Bool
    let label:   String
    let color:   Color
    @Environment(\.uiScale) private var scale

    var body: some View {
        VStack(spacing: 16 * scale) {
            ZStack {
                // Glow ring when active
                Circle()
                    .fill(pinched ? color.opacity(0.20) : Color.white.opacity(0.04))
                    .frame(width: 120 * scale, height: 120 * scale)
                    .shadow(color: pinched ? color : .clear, radius: 24)
                Circle()
                    .stroke(color.opacity(pinched ? 1.0 : 0.30), lineWidth: 2.5)
                    .frame(width: 120 * scale, height: 120 * scale)

                if pinched {
                    Image(systemName: "checkmark")
                        .font(.system(size: 48 * scale, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: color, radius: 8)
                } else {
                    Text("✋")
                        .font(.system(size: 48 * scale))
                        .opacity(0.55)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: pinched)

            Text(label)
                .font(.custom("Audiowide-Regular", size: 20 * scale))
                .foregroundColor(color)
                .tracking(6)
        }
    }
}

// MARK: - Shared: Catch Status Dot

struct CatchStatusDot: View {
    let caught: Bool
    let label:  String
    let color:  Color
    let scale:  CGFloat

    var body: some View {
        VStack(spacing: 5 * scale) {
            ZStack {
                Circle()
                    .fill(caught ? color : Color.white.opacity(0.08))
                    .frame(width: 40 * scale, height: 40 * scale)
                    .shadow(color: caught ? color : .clear, radius: 10)
                Circle()
                    .stroke(color.opacity(caught ? 1 : 0.35), lineWidth: 1.5)
                    .frame(width: 40 * scale, height: 40 * scale)
                if caught {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16 * scale, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("♪")
                        .font(.system(size: 15 * scale))
                        .foregroundColor(color.opacity(0.5))
                }
            }
            Text(label)
                .font(.custom("Audiowide-Regular", size: 9 * scale))
                .foregroundColor(color.opacity(0.80)).tracking(2)
        }
    }
}

// MARK: - Shared: Demo Note Target (interactive floating note)

struct DemoNoteTarget: View {
    let caught: Bool
    let color:  Color
    let label:  String
    @Environment(\.uiScale) private var scale
    @State private var animScale: CGFloat = 1.0
    @State private var showBurst           = false

    var body: some View {
        ZStack {
            if showBurst {
                // Caught burst ring
                Circle()
                    .stroke(color.opacity(0.55), lineWidth: 2.5)
                    .frame(width: 72 * scale)
                    .scaleEffect(animScale)
                    .opacity(max(0, 2.3 - animScale))

                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 48 * scale)
                    .shadow(color: color, radius: 16)

                Image(systemName: "checkmark")
                    .font(.system(size: 18 * scale, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: color, radius: 6)
            } else {
                // Pulsing halo
                Circle()
                    .stroke(color.opacity(0.22), lineWidth: 1.5)
                    .frame(width: 64 * scale)
                    .scaleEffect(animScale)
                    .opacity(max(0, 2.0 - animScale))

                // Note body
                Circle()
                    .fill(color.opacity(0.28))
                    .frame(width: 48 * scale)
                    .shadow(color: color, radius: 10)
                Circle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: 48 * scale)
                Text("♪")
                    .font(.custom("Audiowide-Regular", size: 22 * scale))
                    .foregroundColor(.white)

                // Player label below
                Text(label)
                    .font(.custom("Audiowide-Regular", size: 8 * scale))
                    .foregroundColor(color.opacity(0.75))
                    .tracking(2)
                    .offset(y: 32 * scale)
            }
        }
        .frame(width: 88 * scale, height: 88 * scale)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                animScale = 1.6
            }
        }
        .onChange(of: caught) { _, isCaught in
            guard isCaught else { return }
            animScale  = 1.0
            showBurst  = true
            withAnimation(.easeOut(duration: 0.65)) { animScale = 2.5 }
        }
    }
}

// MARK: - Shared: Pinch Demo Animation

struct PinchDemo: View {
    @Environment(\.uiScale) private var scale

    var body: some View {
        TimelineView(.animation) { tl in
            let t     = tl.date.timeIntervalSinceReferenceDate
            let cycle = 2.4
            let phase = t.truncatingRemainder(dividingBy: cycle) / cycle

            let pinchAmount: Double = {
                if phase < 0.40      { return phase / 0.40 }
                else if phase < 0.55 { return 1.0 }
                else if phase < 0.75 { return 1.0 - (phase - 0.55) / 0.20 }
                else                 { return 0.0 }
            }()

            let burst: Double = {
                let lo = 0.45, hi = 0.70
                guard phase >= lo, phase <= hi else { return 0 }
                return (phase - lo) / (hi - lo)
            }()

            Canvas { ctx, size in
                let cx = size.width / 2, cy = size.height / 2
                drawReticle(ctx: ctx, cx: cx, cy: cy, pinch: pinchAmount)
                drawFingertips(ctx: ctx, cx: cx, cy: cy, pinch: pinchAmount)
                drawNote(ctx: ctx, cx: cx, cy: cy, pinch: pinchAmount, burst: burst, time: t)
                if burst > 0 {
                    drawBurst(ctx: ctx, cx: cx, cy: cy, burst: burst)
                    drawCatchLabel(ctx: ctx, cx: cx, cy: cy, burst: burst)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func drawReticle(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, pinch: Double) {
        var hLine = Path(); hLine.move(to: CGPoint(x: cx - 38*scale, y: cy)); hLine.addLine(to: CGPoint(x: cx + 38*scale, y: cy))
        var vLine = Path(); vLine.move(to: CGPoint(x: cx, y: cy - 38*scale)); vLine.addLine(to: CGPoint(x: cx, y: cy + 38*scale))
        ctx.stroke(hLine, with: .color(.cyan.opacity(0.45)), lineWidth: 1)
        ctx.stroke(vLine, with: .color(.cyan.opacity(0.45)), lineWidth: 1)
        let r = (62 - 14 * pinch) * scale
        var ring = ctx; ring.addFilter(.shadow(color: .cyan, radius: 4 + 10 * pinch))
        ring.stroke(Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)), with: .color(.cyan), lineWidth: 2.5)
        if pinch > 0.01 { ctx.fill(Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)), with: .color(.cyan.opacity(0.30 * pinch))) }
        let s: CGFloat = 8 * scale
        var diamond = Path()
        diamond.move(to: CGPoint(x: cx, y: cy-s)); diamond.addLine(to: CGPoint(x: cx+s, y: cy))
        diamond.addLine(to: CGPoint(x: cx, y: cy+s)); diamond.addLine(to: CGPoint(x: cx-s, y: cy))
        diamond.closeSubpath()
        if pinch > 0.5 { ctx.fill(diamond, with: .color(.cyan.opacity(0.95))) }
        else            { ctx.stroke(diamond, with: .color(.cyan.opacity(0.85)), lineWidth: 1.5) }
    }

    private func drawFingertips(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, pinch: Double) {
        let spread = (78 + (6 - 78) * CGFloat(pinch)) * scale
        let y = cy + 78 * scale
        var line = Path(); line.move(to: CGPoint(x: cx-spread, y: y)); line.addLine(to: CGPoint(x: cx+spread, y: y))
        ctx.stroke(line, with: .color(.cyan.opacity(0.25 + 0.55 * pinch)), lineWidth: 1.5)
        for (idx, x) in [cx - spread, cx + spread].enumerated() {
            let dot = CGRect(x: x - 9*scale, y: y - 9*scale, width: 18*scale, height: 18*scale)
            var d = ctx; d.addFilter(.shadow(color: .cyan, radius: 8))
            d.fill(Path(ellipseIn: dot), with: .color(.white))
            ctx.stroke(Path(ellipseIn: dot), with: .color(.cyan), lineWidth: 1.5)
            ctx.draw(
                Text(idx == 0 ? "THUMB" : "INDEX")
                    .font(.custom("Audiowide-Regular", size: 9 * scale))
                    .foregroundColor(.cyan.opacity(0.85)),
                at: CGPoint(x: x, y: y + 22*scale), anchor: .center)
        }
    }

    private func drawNote(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                          pinch: Double, burst: Double, time: TimeInterval) {
        let r = 28 * scale * CGFloat(1.0 - burst); guard r > 1 else { return }
        let rect = CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)
        var n = ctx; n.addFilter(.shadow(color: .cyan, radius: 12))
        n.fill(Path(ellipseIn: rect), with: .color(.cyan.opacity(0.45)))
        n.stroke(Path(ellipseIn: rect), with: .color(.cyan), lineWidth: 2)
        if (1.0 - burst) > 0.4 {
            ctx.draw(Text("♪").font(.custom("Audiowide-Regular", size: 22*scale)).foregroundColor(.white),
                     at: CGPoint(x: cx, y: cy), anchor: .center)
        }
        if pinch < 0.5 {
            let haloR = 28*scale + 14*scale + CGFloat(sin(time * 6)) * 3
            ctx.stroke(Path(ellipseIn: CGRect(x: cx-haloR, y: cy-haloR, width: haloR*2, height: haloR*2)),
                       with: .color(.cyan.opacity(0.25 * (1 - pinch))), lineWidth: 1)
        }
    }

    private func drawBurst(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, burst: Double) {
        let len = (10 + 36 * burst) * scale; let fade = 1.0 - burst
        for k in 0..<8 {
            let a = Double(k) * .pi * 2 / 8
            var p = Path(); p.move(to: CGPoint(x: cx + CGFloat(cos(a))*6*scale, y: cy + CGFloat(sin(a))*6*scale))
            p.addLine(to: CGPoint(x: cx + CGFloat(cos(a))*len, y: cy + CGFloat(sin(a))*len))
            ctx.stroke(p, with: .color(.cyan.opacity(fade)), lineWidth: 2)
        }
        let rr = (10 + 50 * burst) * scale
        ctx.stroke(Path(ellipseIn: CGRect(x: cx-rr, y: cy-rr, width: rr*2, height: rr*2)),
                   with: .color(.white.opacity(fade * 0.8)), lineWidth: 1.5)
    }

    private func drawCatchLabel(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, burst: Double) {
        let opacity = burst < 0.15 ? burst / 0.15 : 1.0 - (burst - 0.15) / 0.85
        ctx.draw(Text("CATCH ✓").font(.custom("Audiowide-Regular", size: 14*scale)).foregroundColor(.white.opacity(opacity)),
                 at: CGPoint(x: cx, y: cy - 56*scale - CGFloat(burst)*14*scale), anchor: .center)
    }
}
