import SwiftUI
import AppKit

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearanceMode"
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .system: return "desktopcomputer"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    var appKitAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

extension Color {
    // Dynamic native colors also resolve correctly in sheets and macOS controls.
    private static func adaptive(_ name: String, light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name("MyRagAI.\(name)"), dynamicProvider: { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        }))
    }
    static let canvas = adaptive("canvas", light: (0.96, 0.975, 0.96), dark: (0.060, 0.080, 0.073))
    static let sidebar = adaptive("sidebar", light: (0.92, 0.945, 0.92), dark: (0.043, 0.060, 0.054))
    static let panel = adaptive("panel", light: (1, 1, 1), dark: (0.090, 0.120, 0.105))
    static let raised = adaptive("raised", light: (0.88, 0.915, 0.88), dark: (0.122, 0.157, 0.138))
    static let mint = adaptive("accent", light: (0.19, 0.40, 0.20), dark: (0.76, 0.94, 0.60))
    static let muted = adaptive("muted", light: (0.34, 0.40, 0.35), dark: (0.56, 0.63, 0.58))
    static let line = adaptive("line", light: (0.81, 0.85, 0.81), dark: (0.17, 0.20, 0.18))
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 11)
            .foregroundStyle(Color.canvas).background(Color.mint.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(configuration.isPressed ? Color.raised : Color.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.line))
    }
}
struct Tag: View {
    var text: String
    var icon: String? = nil
    var color: Color = .mint
    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }.font(.system(size: 10, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(color.opacity(0.08)).clipShape(Capsule())
    }
}
enum AppBrand {
    static let image: NSImage = {
        // Packaged builds have a direct resource; SwiftPM/Xcode runs use the resource bundle.
        let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png")
            ?? Bundle.module.url(forResource: "AppIcon", withExtension: "png")
        if let url, let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "doc.on.doc.fill", accessibilityDescription: "MyRagAI")!
    }()
}

struct BrandMark: View {
    var size: CGFloat = 36
    var body: some View {
        Image(nsImage: AppBrand.image)
            .resizable().interpolation(.high).scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
struct SectionTitle: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(eyebrow.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(Color.mint)
            Text(title).font(.system(size: 30, weight: .semibold, design: .rounded))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Color.muted)
        }
    }
}
