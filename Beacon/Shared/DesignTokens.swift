import SwiftUI
#if os(macOS)
import AppKit
#endif

enum BeaconAppearanceTheme: String, CaseIterable, Identifiable {
    static let defaultsKey = "Beacon.appearanceTheme"

    case system
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return BeaconL10n.string("System")
        case .dark: return BeaconL10n.string("Dark")
        case .light: return BeaconL10n.string("Light")
        }
    }

    var colorSchemeOverride: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }

    static func resolved(rawValue: String) -> BeaconAppearanceTheme {
        BeaconAppearanceTheme(rawValue: rawValue) ?? .system
    }

    func palette(resolvedSystemScheme colorScheme: ColorScheme) -> BeaconThemePalette {
        switch self {
        case .system:
            return colorScheme == .dark ? .dark : .light
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }
}

struct BeaconThemePalette {
    let panel: Color
    let raised: Color
    let hover: Color
    let active: Color
    let textPrimary: Color
    let textSecondary: Color
    let textMuted: Color
    let textTertiary: Color
    let textDisabled: Color
    let accent: Color
    let accentSoft: Color
    let statusOK: Color
    let statusLow: Color
    let statusCritical: Color
    let statusOffline: Color
    let hairlineSubtle: Color
    let hairlineDefault: Color
    let shadow: Color

    #if os(macOS)
    /// System label, fill, and status colors resolved for one appearance, so an
    /// explicit Light/Dark theme still matches what macOS draws.
    static let dark = BeaconThemePalette.system(appearance: .darkAqua)
    static let light = BeaconThemePalette.system(appearance: .aqua)

    private static func system(appearance name: NSAppearance.Name) -> BeaconThemePalette {
        let appearance = NSAppearance(named: name) ?? NSAppearance.currentDrawing()
        func resolved(_ color: NSColor, alpha: CGFloat = 1) -> Color {
            var output = color
            appearance.performAsCurrentDrawingAppearance {
                output = color.usingColorSpace(.sRGB) ?? color
            }
            return Color(nsColor: output.withAlphaComponent(output.alphaComponent * alpha))
        }
        return BeaconThemePalette(
            panel: resolved(.windowBackgroundColor),
            raised: resolved(.controlBackgroundColor),
            hover: resolved(.quaternarySystemFill),
            active: resolved(.tertiarySystemFill),
            textPrimary: resolved(.labelColor),
            textSecondary: resolved(.secondaryLabelColor),
            textMuted: resolved(.secondaryLabelColor),
            textTertiary: resolved(.secondaryLabelColor),
            textDisabled: resolved(.tertiaryLabelColor),
            accent: .accentColor,
            accentSoft: Color.accentColor.opacity(0.18),
            statusOK: resolved(.systemGreen),
            statusLow: resolved(.systemOrange),
            statusCritical: resolved(.systemRed),
            statusOffline: resolved(.secondaryLabelColor),
            hairlineSubtle: resolved(.separatorColor),
            hairlineDefault: resolved(.separatorColor),
            shadow: Color.black.opacity(name == .darkAqua ? 0.5 : 0.18)
        )
    }
    #endif
}

public enum DesignTokens {
    public enum Radius {
        public static let chip: CGFloat = 4
        public static let statusPill: CGFloat = 9
        public static let row: CGFloat = 12
        public static let card: CGFloat = 14
        public static let panel: CGFloat = 28
    }

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 22
    }

    public enum Motion {
        public static let quick: Double = 0.12
    }

    public enum Typography {
        public static let windowTitle: Font = .title2.weight(.semibold)
        public static let popoverTitle: Font = .title3.weight(.semibold)
        public static let sidebarTitle: Font = .headline.weight(.semibold)
        public static let sectionTitle: Font = .headline.weight(.semibold)
        public static let rowTitle: Font = .body.weight(.medium)
        public static let rowTitleEmphasis: Font = .body.weight(.semibold)
        public static let rowSubtitle: Font = .caption
        public static let controlLabel: Font = .callout
        public static let controlLabelEmphasis: Font = .callout.weight(.semibold)
        public static let caption: Font = .caption
        public static let captionEmphasis: Font = .caption.weight(.semibold)
        public static let caption2: Font = .caption2
        public static let caption2Emphasis: Font = .caption2.weight(.semibold)
        public static let percent: Font = .body.weight(.medium)
        public static let percentEmphasis: Font = .body.weight(.semibold)
        public static let percentSmall: Font = .callout.weight(.semibold)
        public static let percentLarge: Font = .title2.weight(.semibold)

        public static let nativePopoverTitle: Font = .title3.weight(.semibold)
        public static let nativePopoverRowTitle: Font = .body.weight(.regular)
        public static let nativePopoverRowSubtitle: Font = .caption.weight(.regular)
        public static let nativePopoverFooter: Font = .body.weight(.regular)
        public static let nativePopoverPercent: Font = .body.weight(.semibold)
        public static let nativePopoverPill: Font = .caption.weight(.medium)
    }

    public enum Palette {
        public static let charging = Color.green
        public static let healthy = Color.green
        public static let warning = Color.orange
        public static let stale = Color.secondary
        public static let critical = Color.red
        public static let sync = Color.accentColor
        public static let accent = Color.accentColor

        #if os(macOS)
        public static let panel = Color(nsColor: .windowBackgroundColor)
        public static let panelTint = Color(nsColor: .underPageBackgroundColor)
        public static let card = Color(nsColor: .controlBackgroundColor)
        public static let row = Color(nsColor: .controlBackgroundColor)
        public static let separator = Color(nsColor: .separatorColor)
        public static let glassStroke = Color(nsColor: .separatorColor)
        public static let controlPill = Color(nsColor: .quaternarySystemFill)
        #elseif os(iOS)
        public static let panel = Color(.systemBackground)
        public static let panelTint = Color(.secondarySystemBackground)
        public static let card = Color(.secondarySystemBackground)
        public static let row = Color(.secondarySystemBackground)
        public static let separator = Color(.separator)
        public static let glassStroke = Color.white.opacity(0.20)
        public static let controlPill = Color(.tertiarySystemBackground)
        #else
        public static let panel = Color.black
        public static let panelTint = Color.black.opacity(0.6)
        public static let card = Color.white.opacity(0.12)
        public static let row = Color.white.opacity(0.12)
        public static let separator = Color.white.opacity(0.16)
        public static let glassStroke = Color.white.opacity(0.16)
        public static let controlPill = Color.white.opacity(0.10)
        #endif

        public static let text = Color.primary
        public static let secondaryText = Color.secondary
        public static let tertiaryText = Color.secondary

        #if os(macOS)
        public static let hover = Color(nsColor: .quaternarySystemFill)
        #else
        public static let hover = Color.accentColor.opacity(0.10)
        #endif
    }
}

public enum NativeMacStyle {
    public static let popoverCornerRadius: CGFloat = 16
    public static let widgetCornerRadius: CGFloat = 22
    public static let panelCornerRadius: CGFloat = 12
    public static let rowCornerRadius: CGFloat = 8
    public static let dashboardRowCornerRadius: CGFloat = 12

    public static var subtleStroke: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor).opacity(0.26)
        #elseif os(iOS)
        Color(.separator).opacity(0.26)
        #else
        Color.white.opacity(0.18)
        #endif
    }

    public static var rowSelection: Color {
        #if os(macOS)
        Color(nsColor: .selectedContentBackgroundColor).opacity(0.14)
        #else
        Color.accentColor.opacity(0.14)
        #endif
    }
}

extension View {
    /// The menu bar panel's surface: the same behind-window material NSPopover uses.
    func beaconPopoverSurface(
        cornerRadius: CGFloat = NativeMacStyle.popoverCornerRadius,
        colorScheme: ColorScheme
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background {
                #if os(macOS)
                PopoverMaterialBackground(colorScheme: colorScheme, cornerRadius: cornerRadius)
                #else
                Rectangle().fill(.regularMaterial)
                #endif
            }
            .overlay {
                // Liquid Glass draws its own rim; the hairline is for the older material.
                if !PopoverMaterialBackground.usesGlass {
                    shape.strokeBorder(NativeMacStyle.subtleStroke, lineWidth: 0.5)
                }
            }
            .clipShape(shape)
    }

    @ViewBuilder
    func nativeSystemSurface(cornerRadius: CGFloat, strokeOpacity: Double = 0.24) -> some View {
        if #available(macOS 26.0, *) {
            self
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.regularMaterial)
                }
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(strokeOpacity), lineWidth: 0.7)
                }
        } else {
            self
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(NativeMacStyle.subtleStroke, lineWidth: 0.7)
                        }
                }
        }
    }

    @ViewBuilder
    func nativeSettingsBackground() -> some View {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            self
                .containerBackground(.regularMaterial, for: .window)
        } else {
            self
                .background(.regularMaterial)
        }
        #else
        self
            .background(.regularMaterial)
        #endif
    }
}

#if os(macOS)
/// A backdrop only: NSGlassEffectView's content holder otherwise takes every
/// click over it, so the SwiftUI controls drawn on top never receive one.
@available(macOS 26.0, *)
final class PassthroughGlassEffectView: NSGlassEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// macOS 26 menus and Control Center modules sit on Liquid Glass; earlier
/// systems keep the behind-window popover material.
struct PopoverMaterialBackground: NSViewRepresentable {
    /// Beacon's resolved theme, which can differ from the window's appearance.
    let colorScheme: ColorScheme
    var cornerRadius: CGFloat = NativeMacStyle.popoverCornerRadius

    static var usesGlass: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = PassthroughGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            return glass
        }
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        if #available(macOS 26.0, *), let glass = nsView as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
        }
    }
}
#endif
