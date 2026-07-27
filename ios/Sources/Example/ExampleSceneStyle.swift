import SwiftUI

enum ExampleColors {
    static let background = Color(hex: ExampleTheme.backgroundHex)
    static let primary = Color(hex: ExampleTheme.primaryHex)
    static let surface = Color(hex: ExampleTheme.surfaceHex)
    static let brandText = Color(hex: ExampleTheme.brandTextHex)
    static let textPrimary = Color(hex: ExampleTheme.textPrimaryHex)
    static let textSecondary = Color(hex: ExampleTheme.textSecondaryHex)
    static let inputSurface = Color(hex: ExampleTheme.inputSurfaceHex)
    static let inputBorder = Color(hex: ExampleTheme.inputBorderHex)
    static let videoBackground = Color(hex: ExampleTheme.videoBackgroundHex)
    static let failure = Color(hex: ExampleTheme.failureHex)
    static let redAccent = Color(red: 1.0, green: 0.541, blue: 0.502)
    static let configureGradient = LinearGradient(
        colors: [
            Color(hex: ExampleTheme.backgroundHex),
            Color(hex: ExampleTheme.backgroundMidHex),
            Color(hex: ExampleTheme.backgroundHex),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: value)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xff) / 255.0,
            green: Double((rgb >> 8) & 0xff) / 255.0,
            blue: Double(rgb & 0xff) / 255.0
        )
    }
}
