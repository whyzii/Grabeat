import SwiftUI

// MARK: - UI Scale Environment Key
// Propagates a responsive scale factor through the view hierarchy so all
// components can size themselves relative to the current window width.

private struct UIScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var uiScale: CGFloat {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }
}
