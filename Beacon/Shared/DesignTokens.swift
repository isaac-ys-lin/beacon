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
        case .system: return "System"
        case .dark: return "Dark"
        case .light: return "Light"
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

    static let dark = BeaconThemePalette(
        panel: DesignTokens.Beacon.navy700,
        raised: DesignTokens.Beacon.navy600,
        hover: DesignTokens.Beacon.navy500,
        active: DesignTokens.Beacon.navy400,
        textPrimary: DesignTokens.Beacon.offWhite50,
        textSecondary: DesignTokens.Beacon.offWhite200,
        textMuted: DesignTokens.Beacon.offWhite300,
        textTertiary: DesignTokens.Beacon.offWhite400,
        textDisabled: DesignTokens.Beacon.offWhite500,
        accent: DesignTokens.Beacon.ice400,
        accentSoft: DesignTokens.Beacon.ice400.opacity(0.18),
        statusOK: DesignTokens.Beacon.ice300,
        statusLow: DesignTokens.Beacon.amber400,
        statusCritical: DesignTokens.Beacon.red400,
        statusOffline: DesignTokens.Beacon.offWhite500,
        hairlineSubtle: DesignTokens.Beacon.offWhite200.opacity(0.09),
        hairlineDefault: DesignTokens.Beacon.offWhite200.opacity(0.14),
        shadow: DesignTokens.Beacon.navy950.opacity(0.62)
    )

    static let light = BeaconThemePalette(
        panel: Color(red: 0.957, green: 0.976, blue: 0.992),
        raised: Color(red: 0.918, green: 0.949, blue: 0.976),
        hover: Color(red: 0.871, green: 0.922, blue: 0.965),
        active: Color(red: 0.820, green: 0.890, blue: 0.949),
        textPrimary: DesignTokens.Beacon.navy900,
        textSecondary: DesignTokens.Beacon.navy500,
        textMuted: DesignTokens.Beacon.navy400,
        textTertiary: DesignTokens.Beacon.offWhite500,
        textDisabled: DesignTokens.Beacon.offWhite500.opacity(0.70),
        accent: DesignTokens.Beacon.ice500,
        accentSoft: DesignTokens.Beacon.ice400.opacity(0.16),
        statusOK: DesignTokens.Beacon.ice500,
        statusLow: DesignTokens.Beacon.amber400,
        statusCritical: DesignTokens.Beacon.red400,
        statusOffline: DesignTokens.Beacon.offWhite500,
        hairlineSubtle: DesignTokens.Beacon.navy400.opacity(0.12),
        hairlineDefault: DesignTokens.Beacon.navy400.opacity(0.18),
        shadow: DesignTokens.Beacon.navy950.opacity(0.18)
    )
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

    public enum Beacon {
        public static let navy950 = Color(red: 0.031, green: 0.059, blue: 0.110)
        public static let navy900 = Color(red: 0.039, green: 0.071, blue: 0.133)
        public static let navy850 = Color(red: 0.047, green: 0.082, blue: 0.153)
        public static let navy800 = Color(red: 0.063, green: 0.102, blue: 0.188)
        public static let navy700 = Color(red: 0.086, green: 0.137, blue: 0.247)
        public static let navy600 = Color(red: 0.110, green: 0.173, blue: 0.290)
        public static let navy500 = Color(red: 0.141, green: 0.212, blue: 0.341)
        public static let navy400 = Color(red: 0.180, green: 0.263, blue: 0.408)

        public static let offWhite50 = Color(red: 0.984, green: 0.973, blue: 0.941)
        public static let offWhite200 = Color(red: 0.867, green: 0.886, blue: 0.925)
        public static let offWhite300 = Color(red: 0.682, green: 0.725, blue: 0.800)
        public static let offWhite400 = Color(red: 0.486, green: 0.541, blue: 0.639)
        public static let offWhite500 = Color(red: 0.353, green: 0.408, blue: 0.518)

        public static let ice200 = Color(red: 0.663, green: 0.796, blue: 0.910)
        public static let ice300 = Color(red: 0.518, green: 0.690, blue: 0.855)
        public static let ice400 = Color(red: 0.369, green: 0.565, blue: 0.776)
        public static let ice500 = Color(red: 0.267, green: 0.467, blue: 0.682)

        public static let amber300 = Color(red: 0.949, green: 0.784, blue: 0.475)
        public static let amber400 = Color(red: 0.902, green: 0.663, blue: 0.294)
        public static let red300 = Color(red: 0.941, green: 0.627, blue: 0.627)
        public static let red400 = Color(red: 0.878, green: 0.420, blue: 0.420)

        public static let textPrimary = offWhite50
        public static let textSecondary = offWhite200
        public static let textMuted = offWhite300
        public static let textTertiary = offWhite400
        public static let textDisabled = offWhite500

        public static let accent = ice400
        public static let accentHover = ice300
        public static let accentSoft = ice400.opacity(0.18)
        public static let statusOK = ice300
        public static let statusLow = amber400
        public static let statusCritical = red400
        public static let statusOffline = offWhite500
        public static let hairlineSubtle = offWhite200.opacity(0.09)
        public static let hairlineDefault = offWhite200.opacity(0.14)
        public static let hairlineStrong = offWhite200.opacity(0.22)
        public static let signalGlow = ice200.opacity(0.38)
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
        public static let charging = Beacon.ice300
        public static let healthy = Beacon.ice300
        public static let warning = Beacon.amber400
        public static let stale = Beacon.offWhite500
        public static let critical = Beacon.red400
        public static let sync = Beacon.ice400
        public static let accent = Beacon.ice400

        #if os(macOS)
        public static let panel = macSemanticColor(
            light: MacSemanticColor(red: 0.965, green: 0.970, blue: 0.976, alpha: 0.96),
            dark: MacSemanticColor(red: 0.086, green: 0.137, blue: 0.247, alpha: 0.96)
        )
        public static let panelTint = macSemanticColor(
            light: MacSemanticColor(red: 0.925, green: 0.935, blue: 0.948, alpha: 0.92),
            dark: MacSemanticColor(red: 0.110, green: 0.173, blue: 0.290, alpha: 0.90)
        )
        public static let card = macSemanticColor(
            light: MacSemanticColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 0.92),
            dark: MacSemanticColor(red: 0.110, green: 0.173, blue: 0.290, alpha: 0.94)
        )
        public static let row = macSemanticColor(
            light: MacSemanticColor(red: 0.982, green: 0.985, blue: 0.990, alpha: 0.95),
            dark: MacSemanticColor(red: 0.141, green: 0.212, blue: 0.341, alpha: 0.92)
        )
        public static let separator = macSemanticColor(
            light: MacSemanticColor(red: 0.000, green: 0.000, blue: 0.000, alpha: 0.12),
            dark: MacSemanticColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 0.12)
        )
        public static let glassStroke = macSemanticColor(
            light: MacSemanticColor(red: 0.000, green: 0.000, blue: 0.000, alpha: 0.10),
            dark: MacSemanticColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 0.16)
        )
        public static let controlPill = macSemanticColor(
            light: MacSemanticColor(red: 0.940, green: 0.947, blue: 0.956, alpha: 0.95),
            dark: MacSemanticColor(red: 0.180, green: 0.263, blue: 0.408, alpha: 0.90)
        )
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
        public static let tertiaryText = Color.secondary.opacity(0.72)

        #if os(macOS)
        /// Subtle hover highlight for list rows — matches native macOS selection style.
        public static let hover = macSemanticColor(
            light: MacSemanticColor(red: 0.000, green: 0.390, blue: 1.000, alpha: 0.08),
            dark: MacSemanticColor(red: 0.360, green: 0.610, blue: 1.000, alpha: 0.16)
        )
        #else
        public static let hover = Color.accentColor.opacity(0.10)
        #endif

        #if os(macOS)
        private struct MacSemanticColor {
            let red: CGFloat
            let green: CGFloat
            let blue: CGFloat
            let alpha: CGFloat
        }

        private static func macSemanticColor(light: MacSemanticColor, dark: MacSemanticColor) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [.darkAqua, .aqua])
                let color = match == .darkAqua ? dark : light
                return NSColor(
                    srgbRed: color.red,
                    green: color.green,
                    blue: color.blue,
                    alpha: color.alpha
                )
            })
        }
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
    func beaconPopoverSurface(
        cornerRadius: CGFloat = NativeMacStyle.popoverCornerRadius,
        theme: BeaconThemePalette = .dark
    ) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(theme.panel.opacity(0.96))
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            .blendMode(.screen)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(theme.hairlineDefault, lineWidth: 0.8)
                    }
                    .shadow(color: theme.shadow, radius: 48, x: 0, y: 16)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
