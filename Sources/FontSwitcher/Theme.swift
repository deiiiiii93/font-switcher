import AppKit
import FontSwitcherCore
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    @MainActor static func restore() {
        let saved = UserDefaults.standard.string(forKey: "appearance")
        NSApplication.shared.appearance = saved.flatMap(AppAppearance.init(rawValue:))?.appearance
    }
}

struct AppearancePicker: View {
    @AppStorage("appearance") private var appearance = AppAppearance.system

    var body: some View {
        Picker("Appearance", selection: $appearance) {
            ForEach(AppAppearance.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: appearance) { _, newValue in
            NSApp.appearance = newValue.appearance
        }
    }
}

// Shared look: system materials, system colors and the user's accent color. Liquid Glass on
// macOS 26+, with material/bordered fallbacks on macOS 15. Call sites use these wrappers only.

extension View {
    /// Quiet content surface. Glass belongs to controls floating above this layer.
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(ContentSurface(cornerRadius: cornerRadius))
    }

    /// A capsule surface for pills and floating banners, optionally tinted.
    func glassCapsule(tint: Color? = nil) -> some View {
        modifier(GlassSurface(shape: Capsule(style: .continuous), tint: tint))
    }

    /// `.glass` / `.glassProminent` on macOS 26+, `.bordered` / `.borderedProminent` on 15.
    func glassButton(prominent: Bool = false) -> some View {
        modifier(GlassButton(prominent: prominent))
    }
}

private struct ContentSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor).opacity(reduceTransparency ? 1 : 0.72),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1))
    }
}

struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .controlBackgroundColor), in: shape)
                .overlay(shape.stroke(.separator, lineWidth: 0.5))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(tint), in: shape)
        } else {
            content
                .background(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.ultraThinMaterial), in: shape)
                .overlay(shape.stroke(.separator, lineWidth: 0.5))
        }
    }
}

struct GlassButton: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent).tint(.accentColor)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            if prominent {
                content.buttonStyle(.borderedProminent)
            } else {
                content.buttonStyle(.bordered)
            }
        }
    }
}

/// A bottom bar over scrolling content: `safeAreaBar` (with the scroll-edge blur) on macOS 26+,
/// a plain safe-area inset on 15.
struct BottomBar<Bar: View>: ViewModifier {
    @ViewBuilder var bar: Bar

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.safeAreaBar(edge: .bottom, spacing: 0) { bar }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) { bar }
        }
    }
}

/// Groups neighbouring glass shapes so they blend and morph together (no-op before macOS 26).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// SF Symbols such as `textformat` have localized variants (“格式” on a Chinese system). The UI is
/// English, so pin symbols to English glyphs ("Aa") to match the text around them.
extension View {
    func englishSymbols() -> some View { environment(\.locale, Locale(identifier: "en_US")) }
}

/// Tiny status dot: green when on, grey when off.
struct StatusDot: View {
    var on: Bool
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(on ? Color.green : Color.secondary.opacity(0.5))
            .frame(width: size, height: size)
    }
}

/// Small grey capsule tag ("Monospaced", "User-installed").
struct Tag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }
}

/// The code preview is an always-dark editor card (like the mockup), so its palette is fixed.
enum CodePalette {
    static let background = Color(red: 0.12, green: 0.12, blue: 0.14)
    static let keyword = Color(red: 1.00, green: 0.48, blue: 0.70)
    static let function = Color(red: 0.42, green: 0.71, blue: 1.00)
    static let type = Color(red: 0.85, green: 0.73, blue: 1.00)
    static let string = Color(red: 1.00, green: 0.80, blue: 0.40)
    static let plain = Color(red: 0.91, green: 0.91, blue: 0.93)
}

enum Format {
    /// 14 → "14", 13.5 → "13.5".
    static func size(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%g", value)
    }

    static func choice(_ c: FontChoice) -> String {
        switch (c.family, c.size) {
        case let (f?, s?): "\(f) \(size(s)) pt"
        case let (f?, nil): f
        case let (nil, s?): "\(size(s)) pt"
        case (nil, nil): "—"
        }
    }

    /// Replaces the home prefix with "~".
    static func abbreviate(_ path: String, home: String) -> String {
        let h = home.hasSuffix("/") ? String(home.dropLast()) : home
        return path.hasPrefix(h + "/") ? "~" + path.dropFirst(h.count) : path
    }
}


/// Shared page rhythm for the library and settings destinations.
struct PageHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 27, weight: .bold, design: .rounded))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SymbolTile: View {
    let symbol: String
    var color: Color = .accentColor

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 42, height: 42)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .englishSymbols()
            .accessibilityHidden(true)
    }
}
