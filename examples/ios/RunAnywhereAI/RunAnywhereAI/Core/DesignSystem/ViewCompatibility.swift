import SwiftUI

enum NavigationTitleMode {
    case automatic, inline, large
}

extension View {
    @ViewBuilder
    func navigationBarTitleDisplayModeCompat(_ mode: NavigationTitleMode) -> some View {
        #if os(iOS)
        switch mode {
        case .automatic: self.navigationBarTitleDisplayMode(.automatic)
        case .inline: self.navigationBarTitleDisplayMode(.inline)
        case .large: self.navigationBarTitleDisplayMode(.large)
        }
        #else
        self
        #endif
    }
}
