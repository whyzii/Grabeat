import SwiftUI

extension Color {
    /// Hot magenta — not available natively in SwiftUI (UIKit only).
    static let magenta = Color(red: 1, green: 0, blue: 1)
}

// MARK: - UI scale environment

private struct UIScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var uiScale: CGFloat {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }
}
