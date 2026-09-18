import SwiftUI

/// Uses the same artwork as the Home Screen icon, including in dark mode.
/// iOS applies the Home Screen mask; in-app surfaces retain the original rounding.
struct InkflowMark: View {
    var size: CGFloat = 42
    var body: some View {
        Image("BrandMark")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}
