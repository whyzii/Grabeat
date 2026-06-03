import SwiftUI
import Combine

// MARK: - Start Screen

struct StartScreen: View {
    @ObservedObject var gameManager: GameManager
    @ObservedObject var tracker: CameraHandTracker
    @Environment(\.uiScale) private var scale
    @State private var showInfo = false

    // Photo-consent sheet
    @State private var showPhotoConsent = false
    @State private var pendingAction: (() -> Void)? = nil

    // Both mode buttons use the same fixed minimum width so they're identical in size
    private var modeButtonMinWidth: CGFloat { 260 * scale }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                GlitchCircleBackground()

                VStack(spacing: 0) {
                    Spacer()

                    GlitchTitle(text: "GRABEAT", fontSize: 60 * scale)

                    Text("Pinch, Play, Repeat.")
                        .font(.custom("Audiowide-Regular", size: 13 * scale))
                        .foregroundColor(Color(red: 1, green: 0, blue: 1).opacity(0.8))
                        .tracking(6)
                        .padding(.top, 8)
                        .padding(.bottom, 52)

                    // Versus row: mode button + circular tutorial button
                    HStack(alignment: .center, spacing: 64 * scale) {
                        MenuHandButton(
                            label: "VERSUS MODE", color: .cyan,
                            tracker: tracker, screenSize: geo.size,
                            action: {
                                pendingAction = { gameManager.beginTutorial() }
                                showPhotoConsent = true
                            },
                            minWidth: modeButtonMinWidth
                        )
                        TutorialCircleButton(
                            color: .cyan,
                            tracker: tracker, screenSize: geo.size,
                            action: { gameManager.forceTutorial() }
                        )
                    }

                    Text("")
                        .font(.custom("Audiowide-Regular", size: 10 * scale))
                        .foregroundColor(.cyan.opacity(0.45))
                        .tracking(2)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                        .padding(.bottom, 18)

                    // Co-op row: mode button + circular tutorial button
                    HStack(alignment: .center, spacing: 64 * scale) {
                        MenuHandButton(
                            label: "CO-OP MODE", color: Color(red: 234/255, green: 51/255, blue: 247/255),
                            tracker: tracker, screenSize: geo.size,
                            action: {
                                pendingAction = { gameManager.beginCoopTutorial() }
                                showPhotoConsent = true
                            },
                            minWidth: modeButtonMinWidth
                        )
                        TutorialCircleButton(
                            color: Color(red: 234/255, green: 51/255, blue: 247/255),
                            tracker: tracker, screenSize: geo.size,
                            action: { gameManager.forceCoopTutorial() }
                        )
                    }

                    Text("")
                        .font(.custom("Audiowide-Regular", size: 10 * scale))
                        .foregroundColor(Color(red: 1.0, green: 0.2, blue: 0.6).opacity(0.55))
                        .tracking(2)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)

                    Text("PINCH AND HOLD TO CHOOSE THE MODE")
                        .font(.custom("Audiowide-Regular", size: 11 * scale))
                        .foregroundColor(.white.opacity(0.75))
                        .tracking(3)
                        .padding(.top, 18)

                    Spacer()
                }

                if tracker.handsP1.count > 0 { HandCursor(hand: tracker.handsP1[0], color: .cyan,    size: geo.size) }
                if tracker.handsP1.count > 1 { HandCursor(hand: tracker.handsP1[1], color: .cyan,    size: geo.size) }
                if tracker.handsP2.count > 0 { HandCursor(hand: tracker.handsP2[0], color: .magenta, size: geo.size) }
                if tracker.handsP2.count > 1 { HandCursor(hand: tracker.handsP2[1], color: .magenta, size: geo.size) }

                // Info button — top-left corner
                VStack {
                    HStack {
                        Button(action: { withAnimation(.easeInOut(duration: 0.3)) { showInfo = true } }) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 20 * scale, weight: .light))
                                .foregroundColor(.white.opacity(0.65))
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

                // Info overlay — slides in over everything
                if showInfo {
                    InfoOverlay(onDismiss: { withAnimation(.easeInOut(duration: 0.3)) { showInfo = false } })
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                // Photo-consent overlay — shown whenever a mode button is activated
                if showPhotoConsent {
                    PhotoConsentOverlay(
                        tracker: tracker,
                        onAccept: {
                            withAnimation(.easeInOut(duration: 0.2)) { showPhotoConsent = false }
                            gameManager.photoConsentGiven = true
                            pendingAction?()
                            pendingAction = nil
                        },
                        onDecline: {
                            withAnimation(.easeInOut(duration: 0.2)) { showPhotoConsent = false }
                            gameManager.photoConsentGiven = false
                            pendingAction?()
                            pendingAction = nil
                        }
                    )
                    .transition(.opacity)
                }
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Photo Consent Overlay
// Full-screen overlay shown every time a mode is chosen.
// Both YES and NO are activated by pinch-hold (same mechanic as MenuHandButton).

private struct PhotoConsentOverlay: View {
    let tracker:   CameraHandTracker
    let onAccept:  () -> Void
    let onDecline: () -> Void
    @Environment(\.uiScale) private var scale

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.92).ignoresSafeArea()
                HyperspaceBackground().opacity(0.12)

                // ── Fixed centred panel — nothing here moves ──────────────
                VStack(spacing: 28 * scale) {

                    // Icon
                    Image(systemName: "camera.fill")
                        .font(.system(size: 44 * scale))
                        .foregroundColor(.cyan)
                        .shadow(color: .cyan, radius: 16)

                    // Title
                    Text("PHOTO BOOTH")
                        .font(.custom("Audiowide-Regular", size: 22 * scale))
                        .foregroundColor(.white)
                        .tracking(4)
                        .shadow(color: .cyan.opacity(0.6), radius: 12)

                    // Divider
                    Rectangle()
                        .fill(Color.cyan.opacity(0.25))
                        .frame(width: 320 * scale, height: 1)

                    // Body text
                    VStack(spacing: 12 * scale) {
                        Text("During the game, GraBeat will automatically take up to 4 photos of you using the camera.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white.opacity(0.85))

                        Text("YES — photos are captured with the cyberpunk filter and shown at the end. You can save them locally on your Mac. They are never sent anywhere.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white.opacity(0.55))

                        Text("NO — the camera is still used for hand tracking, but no photos will be taken or stored.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white.opacity(0.55))
                    }
                    .font(.custom("Audiowide-Regular", size: 11 * scale))
                    .tracking(1)
                    .lineSpacing(5)
                    .frame(maxWidth: 520 * scale)

                    Text("PINCH AND HOLD TO CHOOSE")
                        .font(.custom("Audiowide-Regular", size: 10 * scale))
                        .foregroundColor(.white.opacity(0.35))
                        .tracking(3)

                    // Pinch buttons
                    HStack(spacing: 32 * scale) {
                        ConsentHandButton(
                            label: "NO THANKS",
                            color: Color.white.opacity(0.70),
                            tracker: tracker,
                            screenSize: geo.size,
                            action: onDecline
                        )
                        ConsentHandButton(
                            label: "YES, TAKE PHOTOS",
                            color: .cyan,
                            tracker: tracker,
                            screenSize: geo.size,
                            action: onAccept
                        )
                    }
                }
                .padding(52 * scale)
                // Pin the panel to the centre — its size never changes
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                // ── Hand cursors — live OUTSIDE the VStack so they never shift the layout
                if tracker.handsP1.count > 0 { HandCursor(hand: tracker.handsP1[0], color: .cyan,    size: geo.size) }
                if tracker.handsP1.count > 1 { HandCursor(hand: tracker.handsP1[1], color: .cyan,    size: geo.size) }
                if tracker.handsP2.count > 0 { HandCursor(hand: tracker.handsP2[0], color: .magenta, size: geo.size) }
                if tracker.handsP2.count > 1 { HandCursor(hand: tracker.handsP2[1], color: .magenta, size: geo.size) }
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Consent Hand Button
// Identical pinch-hold mechanic to MenuHandButton.
// Progress bar sweeps along the bottom edge; fires after 1.5 s of continuous pinch.

private struct ConsentHandButtonFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct ConsentHandButton: View {
    let label:      String
    let color:      Color
    let tracker:    CameraHandTracker
    let screenSize: CGSize
    let action:     () -> Void

    @State private var buttonFrame:  CGRect          = .zero
    @State private var isHovered:    Bool            = false
    @State private var holdProgress: Double          = 0
    @State private var holdStart:    Date?           = nil
    @State private var fired:        Bool            = false
    @State private var holdTimer:    AnyCancellable? = nil
    @Environment(\.uiScale) private var scale

    private let threshold: Double = 1.5

    var body: some View {
        Text(label)
            .font(.custom("Audiowide-Regular", size: 14 * scale))
            .tracking(3)
            .foregroundColor(color)
            .padding(.horizontal, 36 * scale)
            .padding(.vertical, 14 * scale)
            .background(color.opacity(0.15 * holdProgress))
            .overlay(Rectangle().stroke(color, lineWidth: 1.5))
            // Progress bar along the bottom
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(color)
                        .frame(width: geo.size.width * holdProgress, height: 2.5)
                        .shadow(color: color, radius: 4)
                }
                .frame(height: 2.5)
            }
            .shadow(color: isHovered ? color.opacity(0.4) : .clear, radius: 10)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ConsentHandButtonFrameKey.self,
                                           value: geo.frame(in: .global))
                }
            )
            .onPreferenceChange(ConsentHandButtonFrameKey.self) { buttonFrame = $0 }
            .onChange(of: tracker.handsP1) { _, _ in checkHands() }
            .onChange(of: tracker.handsP2) { _, _ in checkHands() }
    }

    // MARK: Hand detection

    private func checkHands() {
        guard screenSize.width > 0, buttonFrame != .zero else { return }
        let hit = buttonFrame.insetBy(dx: -buttonFrame.width * 0.30,
                                      dy: -buttonFrame.height * 0.50)
        let all = tracker.handsP1 + tracker.handsP2

        isHovered = all.contains { h in
            guard h.isActive else { return false }
            return hit.contains(CGPoint(x: h.position.x * screenSize.width,
                                        y: h.position.y * screenSize.height))
        }

        let pinching = all.contains { h in
            guard h.isActive, h.isPinching else { return false }
            return hit.contains(CGPoint(x: h.position.x * screenSize.width,
                                        y: h.position.y * screenSize.height))
        }

        pinching ? startHoldIfNeeded() : cancelHold()
    }

    // MARK: Hold timer

    private func startHoldIfNeeded() {
        guard holdStart == nil else { return }
        holdStart = Date(); fired = false; holdProgress = 0
        holdTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in tick() }
    }

    private func tick() {
        guard let start = holdStart, !fired else { return }
        let elapsed  = Date().timeIntervalSince(start)
        holdProgress = min(elapsed / threshold, 1.0)
        if elapsed >= threshold {
            fired = true
            holdTimer?.cancel()
            holdTimer = nil
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { reset() }
        }
    }

    private func cancelHold() {
        holdTimer?.cancel()
        holdTimer = nil
        reset()
    }

    private func reset() {
        holdStart = nil; holdProgress = 0; fired = false
    }
}

// MARK: - Tutorial Circle Button
// A circular "?" button with the same hold-to-activate mechanic as MenuHandButton.
// The progress arc sweeps clockwise as the user holds the pinch.

private struct CircleBtnFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private let circleBtnHoldThreshold: Double = 1.5

private struct TutorialCircleButton: View {
    let color:      Color
    let tracker:    CameraHandTracker
    let screenSize: CGSize
    let action:     () -> Void

    @State private var buttonFrame:  CGRect          = .zero
    @State private var isHovered:    Bool            = false
    @State private var holdProgress: Double          = 0
    @State private var holdStart:    Date?           = nil
    @State private var fired:        Bool            = false
    @State private var holdTimer:    AnyCancellable? = nil
    @Environment(\.uiScale) private var scale

    var body: some View {
        let d = 52.0 * scale
        ZStack {
            // Background fill grows as hold progresses
            Circle()
                .fill(color.opacity(0.18 * holdProgress))

            // Sweep arc showing hold progress (clockwise from top)
            Circle()
                .trim(from: 0, to: holdProgress)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color, radius: 4)

            // Base border (fades slightly while holding)
            Circle()
                .stroke(color.opacity(1.0 - holdProgress * 0.6), lineWidth: 1.5)

            // "?" label
            Text("?")
                .font(.custom("Audiowide-Regular", size: 20 * scale))
                .foregroundColor(color)
                .tracking(1)
        }
        .frame(width: d, height: d)
        .shadow(color: isHovered ? color.opacity(0.45) : .clear, radius: 12)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: CircleBtnFrameKey.self,
                                       value: geo.frame(in: .global))
            }
        )
        .onPreferenceChange(CircleBtnFrameKey.self) { buttonFrame = $0 }
        .onChange(of: tracker.handsP1) { _, _ in checkHands() }
        .onChange(of: tracker.handsP2) { _, _ in checkHands() }
    }

    // MARK: - Hand detection

    private func checkHands() {
        guard screenSize.width > 0, buttonFrame != .zero else { return }
        let hit = buttonFrame.insetBy(dx: -buttonFrame.width  * 0.10,
                                      dy: -buttonFrame.height * 0.10)
        let all = tracker.handsP1 + tracker.handsP2

        isHovered = all.contains { h in
            guard h.isActive else { return false }
            return hit.contains(CGPoint(x: h.position.x * screenSize.width,
                                        y: h.position.y * screenSize.height))
        }

        let pinching = all.contains { h in
            guard h.isActive, h.isPinching else { return false }
            return hit.contains(CGPoint(x: h.position.x * screenSize.width,
                                        y: h.position.y * screenSize.height))
        }

        pinching ? startHoldIfNeeded() : cancelHold()
    }

    // MARK: - Hold timer

    private func startHoldIfNeeded() {
        guard holdStart == nil else { return }
        holdStart = Date(); fired = false; holdProgress = 0
        holdTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in tick() }
    }

    private func tick() {
        guard let start = holdStart, !fired else { return }
        let elapsed  = Date().timeIntervalSince(start)
        holdProgress = min(elapsed / circleBtnHoldThreshold, 1.0)
        if elapsed >= circleBtnHoldThreshold {
            fired = true
            holdTimer?.cancel()
            holdTimer = nil
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { reset() }
        }
    }

    private func cancelHold() {
        holdTimer?.cancel()
        holdTimer = nil
        reset()
    }

    private func reset() {
        holdStart = nil; holdProgress = 0; fired = false
    }
}

// MARK: - Info Overlay

private struct InfoOverlay: View {
    let onDismiss: () -> Void
    @Environment(\.uiScale) private var scale

    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.96).ignoresSafeArea()
            HyperspaceBackground().opacity(0.15)

            // Scrollable content
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Header ─────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 6 * scale) {
                        Text("GRABEAT")
                            .font(.custom("Audiowide-Regular", size: 38 * scale))
                            .foregroundColor(.white)
                            .shadow(color: Color(red: 1, green: 0, blue: 1).opacity(0.8), radius: 18)

                        Text("Version 1.0  ·  © 2026 Cow Workers Studio, Napoli (Forza Napoli Sempre)")
                            .font(.custom("Audiowide-Regular", size: 11 * scale))
                            .foregroundColor(.white.opacity(0.45))
                            .tracking(2)

                        Text("Pinch. Play. Repeat.")
                            .font(.custom("Audiowide-Regular", size: 13 * scale))
                            .foregroundColor(Color(red: 1, green: 0, blue: 1).opacity(0.75))
                            .tracking(4)
                            .padding(.top, 4 * scale)
                    }
                    .padding(.bottom, 36 * scale)

                    // ── About ──────────────────────────────────────────────
                    InfoSection(title: "ABOUT", color: .cyan) {
                        Text("GraBeat is a camera-based rhythm game for two players. No controllers, no touch screen — just your hands. Catch notes, follow the beat, and play the air.")
                    }

                    // ── Team ───────────────────────────────────────────────
                    InfoSection(title: "TEAM", color: Color(red: 0.6, green: 0.4, blue: 1.0)) {
                        InfoRoleRow(role: "Development", names: "Abbas Yousefzadeh, Raffaella Ruggiero, Nima Khodarahmi")
                        InfoRoleRow(role: "Design", names: "Sana Ravan, Nima Khodarahmi")
                        InfoRoleRow(role: "Project Management", names: "Martina Maria Bruno, Shantia Azizian")
                    }

                    // ── Privacy ────────────────────────────────────────────
                    InfoSection(title: "PRIVACY", color: .cyan) {
                        Text("GraBeat and its developers are committed to protecting your privacy. The application does not integrate any third-party analytics or advertising frameworks, and does not collect, transmit, distribute, or sell any personal data.")
                            .padding(.bottom, 10 * scale)
                        Text("Camera access is used exclusively for real-time hand movement tracking during gameplay and photo capture for the final Photo Booth feature. All image data is stored locally on your device and is never transmitted externally.")
                            .padding(.bottom, 10 * scale)
                        Text("Beyond the information Apple provides to developers by default, no additional data is gathered or retained.")
                    }

                    // ── Built with ─────────────────────────────────────────
                    InfoSection(title: "BUILT WITH", color: Color(red: 0.6, green: 0.4, blue: 1.0)) {
                        Text("Swift · SwiftUI · Vision · AVFoundation · Core ML")
                            .padding(.bottom, 6 * scale)
                        Text("Font: Audiowide — designed by Astigmatic\n(Google Fonts, SIL Open Font License)")
                            .foregroundColor(.white.opacity(0.45))
                    }

                    Spacer(minLength: 60 * scale)
                }
                .padding(.horizontal, 52 * scale)
                .padding(.top, 80 * scale)
                .frame(maxWidth: 720 * scale)
                .frame(maxWidth: .infinity)
            }

            // Back button — top-left, tap only
            VStack {
                HStack {
                    Button(action: onDismiss) {
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
        }
    }
}

// MARK: - Info Section

private struct InfoSection<Content: View>: View {
    let title: String
    let color: Color
    @ViewBuilder let content: () -> Content
    @Environment(\.uiScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * scale) {
            // Section header with accent line
            HStack(spacing: 10 * scale) {
                Rectangle()
                    .fill(color)
                    .frame(width: 3, height: 16 * scale)
                Text(title)
                    .font(.custom("Audiowide-Regular", size: 13 * scale))
                    .foregroundColor(color)
                    .tracking(4)
            }

            // Divider
            Rectangle()
                .fill(color.opacity(0.20))
                .frame(height: 1)
                .padding(.bottom, 4 * scale)

            content()
                .font(.custom("Audiowide-Regular", size: 11 * scale))
                .foregroundColor(.white.opacity(0.72))
                .tracking(1)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 32 * scale)
    }
}

// MARK: - Info Role Row

private struct InfoRoleRow: View {
    let role:  String
    let names: String
    @Environment(\.uiScale) private var scale

    var body: some View {
        HStack(alignment: .top, spacing: 12 * scale) {
            Text(role)
                .font(.custom("Audiowide-Regular", size: 10 * scale))
                .foregroundColor(.white.opacity(0.40))
                .tracking(2)
                .frame(width: 160 * scale, alignment: .leading)
            Text(names)
                .font(.custom("Audiowide-Regular", size: 11 * scale))
                .foregroundColor(.white.opacity(0.80))
                .tracking(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3 * scale)
    }
}

// MARK: - Player Instruction Card

struct PlayerInstructionCard: View {
    let player:      Int
    let color:       Color
    let side:        String
    let description: String
    @Environment(\.uiScale) private var scale

    var body: some View {
        VStack(spacing: 10) {
            Text(player == 1 ? "◀ PLAYER \(player) — \(side)" : "PLAYER \(player) — \(side) ▶")
                .font(.custom("Audiowide-Regular", size: 12 * scale))
                .foregroundColor(color)
                .tracking(3)
            Text(description)
                .font(.custom("Audiowide-Regular", size: 12 * scale))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(width: 250 * scale)
    }
}
