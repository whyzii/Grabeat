import SwiftUI
import Combine

// MARK: - Menu Hand Button
// Activated by holding a pinch over the button for 1.5 seconds.
// While holding, a progress bar sweeps across the bottom border and the
// background fills in. Releasing before the threshold resets everything.
// A 30 fps Combine timer drives the fill so it's smooth even when the
// hand is perfectly still (Vision jitter alone isn't guaranteed at 60 fps).

private struct FramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private let holdThreshold: Double = 1.5

struct MenuHandButton: View {
    let label:      String
    let color:      Color
    let tracker:    CameraHandTracker
    let screenSize: CGSize
    let action:     () -> Void
    var minWidth:   CGFloat? = nil

    @State private var buttonFrame:  CGRect         = .zero
    @State private var isHovered:    Bool           = false
    @State private var holdProgress: Double         = 0
    @State private var holdStart:    Date?          = nil
    @State private var fired:        Bool           = false
    @State private var holdTimer:    AnyCancellable? = nil
    @Environment(\.uiScale) private var scale

    var body: some View {
        Text(label)
            .font(.custom("Audiowide-Regular", size: 15 * scale))
            .tracking(4)
            .foregroundColor(color)
            .padding(.horizontal, 40 * scale)
            .padding(.vertical, 14 * scale)
            .frame(minWidth: minWidth)
            .background(color.opacity(0.18 * holdProgress))
            .overlay(Rectangle().stroke(color, lineWidth: 1.5))
            // Progress bar sweeps left → right along the bottom edge
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(color)
                        .frame(width: geo.size.width * holdProgress, height: 2.5)
                        .shadow(color: color, radius: 4)
                }
                .frame(height: 2.5)
            }
            .shadow(color: isHovered ? color.opacity(0.35) : .clear, radius: 10)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: FramePreferenceKey.self,
                                           value: geo.frame(in: .global))
                }
            )
            .onPreferenceChange(FramePreferenceKey.self) { buttonFrame = $0 }
            .onChange(of: tracker.handsP1) { _, _ in checkHands() }
            .onChange(of: tracker.handsP2) { _, _ in checkHands() }
    }

    // MARK: - Hand detection

    private func checkHands() {
        guard screenSize.width > 0, buttonFrame != .zero else { return }

        let hit = buttonFrame.insetBy(dx: -buttonFrame.width  * 0.30,
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

        if pinching {
            startHoldIfNeeded()
        } else {
            cancelHold()
        }
    }

    // MARK: - Hold timer

    private func startHoldIfNeeded() {
        guard holdStart == nil else { return }
        holdStart    = Date()
        fired        = false
        holdProgress = 0

        holdTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in tick() }
    }

    private func tick() {
        guard let start = holdStart, !fired else { return }
        let elapsed  = Date().timeIntervalSince(start)
        holdProgress = min(elapsed / holdThreshold, 1.0)

        if elapsed >= holdThreshold {
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
        holdStart    = nil
        holdProgress = 0
        fired        = false
    }
}
