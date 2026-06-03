import SwiftUI

// MARK: - Cyberpunk Grid
// Static background grid used on end/calibration screens.

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
// Colour tint + scanlines + vignette layered over the camera feed.

struct CyberpunkCameraFilter: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 1.0,  green: 0.05, blue: 0.75).opacity(0.14),
                    Color(red: 0.55, green: 0.0,  blue: 1.0 ).opacity(0.10),
                    Color(red: 0.0,  green: 0.85, blue: 1.0 ).opacity(0.14),
                ],
                startPoint: .topTrailing,
                endPoint:   .bottomLeading
            )
            CyberpunkScanlines()
            CyberpunkVignette()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Cyberpunk Scanlines

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

// MARK: - Cyberpunk Vignette

struct CyberpunkVignette: View {
    var body: some View {
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height)
            ZStack {
                RadialGradient(
                    colors: [.clear, .black.opacity(0.48)],
                    center: .center,
                    startRadius: r * 0.45,
                    endRadius:   r * 1.10
                )
                LinearGradient(
                    colors: [Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.22), .clear],
                    startPoint: .leading,
                    endPoint:   UnitPoint(x: 0.35, y: 0.5)
                )
                LinearGradient(
                    colors: [.clear, Color(red: 1.0, green: 0.0, blue: 0.65).opacity(0.22)],
                    startPoint: UnitPoint(x: 0.65, y: 0.5),
                    endPoint:   .trailing
                )
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
