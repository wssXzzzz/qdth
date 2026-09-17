import SwiftUI

enum Palette {
    static let accent = Color(light: 0x3D6B57, dark: 0xA0CBB3)
    static let canvas = Color(light: 0xF5F5F0, dark: 0x181D1A)
    static let card = Color(light: 0xFFFFFF, dark: 0x222A25)
    static let ink = Color(light: 0x253D31, dark: 0xE5EDE7)
    static let muted = Color(light: 0x778279, dark: 0x9BA99E)
    static let line = Color(light: 0xE4E8E1, dark: 0x354238)
    static let softGreen = Color(light: 0xE8EEE5, dark: 0x293D30)
    static let gold = Color(light: 0xB08337, dark: 0xE2B969)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        })
    }
}

struct InkflowMark: View {
    var size: CGFloat = 42
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3).fill(Palette.accent)
            Image(systemName: "quote.opening").font(.system(size: size * 0.55, weight: .bold)).foregroundStyle(Palette.canvas)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct EmptyLibrary: View {
    var title: String
    var subtitle: String
    var symbol: String = "tray"
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(Palette.accent)
                .frame(width: 84, height: 84).background(Palette.softGreen, in: RoundedRectangle(cornerRadius: 28))
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
            Text(subtitle).font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center).lineSpacing(5)
        }.frame(maxWidth: .infinity).padding(.vertical, 70).padding(.horizontal, 30)
    }
}
