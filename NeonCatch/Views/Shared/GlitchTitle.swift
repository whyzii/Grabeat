import SwiftUI

// MARK: - Glitch Title
// Animated cyberpunk title with chromatic aberration, scan-line sweep,
// and periodic major/minor glitch bursts. Used on the Start screen.

struct GlitchTitle: View {
    let text: String
    let fontSize: CGFloat

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate

            // Slow continuous chromatic drift
            let drift  = CGFloat(sin(t * 0.60)) * 2.8 + CGFloat(cos(t * 0.38)) * 1.3

            // Major burst: every 3.5 s, lasts 150 ms
            let mPhase = t.truncatingRemainder(dividingBy: 3.5)
            let mFrac  = mPhase < 0.15 ? CGFloat(mPhase / 0.15) : 0
            let mBig   = CGFloat(sin(Double(mFrac) * .pi)) * 26
            let mY     = CGFloat(sin(Double(mFrac) * .pi * 3.5)) * 5 * mFrac

            // Minor burst: every 2.1 s, lasts 65 ms
            let nPhase = (t + 0.75).truncatingRemainder(dividingBy: 2.1)
            let nFrac  = nPhase < 0.065 ? CGFloat(nPhase / 0.065) : 0
            let nShift = CGFloat(sin(Double(nFrac) * .pi)) * 11

            let xOff  = drift + mBig + nShift
            let yOff  = mY
            let glowR = 18.0 + 20.0 * Double(mFrac) + 8.0 * Double(nFrac)

            ZStack {
                // Cyan ghost
                Text(text)
                    .font(.custom("Audiowide-Regular", size: fontSize))
                    .foregroundColor(Color(red: 0.0, green: 0.92, blue: 1.0))
                    .offset(x: xOff + 3.5, y: yOff - 1.5)
                    .opacity(0.36 + Double(mFrac + nFrac) * 0.28)

                // Magenta ghost
                Text(text)
                    .font(.custom("Audiowide-Regular", size: fontSize))
                    .foregroundColor(Color(red: 1.0, green: 0.0, blue: 1.0))
                    .offset(x: -(xOff + 2.5), y: -yOff * 0.55 + 1.5)
                    .opacity(0.36 + Double(mFrac + nFrac) * 0.28)

                // Main white text
                Text(text)
                    .font(.custom("Audiowide-Regular", size: fontSize))
                    .foregroundColor(.white)
                    .opacity(1.0 - Double(mFrac) * 0.24)
                    .shadow(color: .cyan,                            radius: glowR)
                    .shadow(color: Color(red: 1, green: 0, blue: 1), radius: 12 * Double(mFrac))

                // Scan line sweep during major burst
                Rectangle()
                    .fill(LinearGradient(
                        colors: [.clear,
                                 Color.cyan.opacity(0.9),
                                 Color.white.opacity(0.75),
                                 Color.cyan.opacity(0.9),
                                 .clear],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: fontSize * 7.5, height: 2.5)
                    .offset(y: (mFrac - 0.5) * fontSize * 0.88)
                    .opacity(Double(mFrac * (1 - mFrac)) * 3.8)
            }
        }
        .fixedSize()
    }
}
