import AppKit
import SwiftUI

extension TerminalEntry {
    func applyTheme(_ theme: TerminalTheme, systemColorScheme: ColorScheme) {
        let palette = TerminalThemePalette(theme: theme, systemColorScheme: systemColorScheme)
        terminalView.nativeForegroundColor = palette.foreground
        terminalView.nativeBackgroundColor = palette.background
        terminalView.caretColor = palette.caret
        terminalView.selectedTextBackgroundColor = palette.selection
        terminalView.needsDisplay = true
    }
}

private struct TerminalThemePalette {
    let foreground: NSColor
    let background: NSColor
    let caret: NSColor
    let selection: NSColor

    init(theme: TerminalTheme, systemColorScheme: ColorScheme) {
        switch theme {
        case .system:
            foreground = Self.systemColor(.textColor, for: systemColorScheme)
            background = Self.systemColor(.textBackgroundColor, for: systemColorScheme)
            caret = Self.systemColor(.controlAccentColor, for: systemColorScheme)
            selection = Self.systemColor(.selectedTextBackgroundColor, for: systemColorScheme)
        case .light:
            foreground = Self.color(red: 31, green: 35, blue: 40)
            background = Self.color(red: 255, green: 255, blue: 255)
            caret = Self.color(red: 9, green: 105, blue: 218)
            selection = Self.color(red: 182, green: 215, blue: 240)
        case .dark:
            foreground = Self.color(red: 230, green: 237, blue: 243)
            background = Self.color(red: 13, green: 17, blue: 23)
            caret = Self.color(red: 88, green: 166, blue: 255)
            selection = Self.color(red: 38, green: 79, blue: 120)
        }
    }

    private static func color(red: Int, green: Int, blue: Int) -> NSColor {
        NSColor(
            calibratedRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }

    private static func systemColor(_ color: NSColor, for colorScheme: ColorScheme) -> NSColor {
        let appearanceName: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
        guard let appearance = NSAppearance(named: appearanceName) else { return color }
        var resolvedColor = color
        appearance.performAsCurrentDrawingAppearance {
            resolvedColor = color.usingColorSpace(.deviceRGB) ?? color
        }
        return resolvedColor
    }
}
