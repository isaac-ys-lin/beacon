import SwiftUI
#if os(macOS)
import AppKit
#endif

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
        public static let healthy = Color(red: 0.36, green: 0.78, blue: 0.38)
        public static let warning = Color(red: 0.94, green: 0.62, blue: 0.20)
        public static let stale = Color(red: 0.72, green: 0.64, blue: 0.52)
        public static let critical = Color(red: 0.88, green: 0.22, blue: 0.20)
        public static let sync = Color.blue
        public static let accent = Color(red: 0.0, green: 0.39, blue: 1.0)

        #if os(macOS)
        public static let panel = macSemanticColor(
            light: MacSemanticColor(red: 0.965, green: 0.970, blue: 0.976, alpha: 0.96),
            dark: MacSemanticColor(red: 0.112, green: 0.118, blue: 0.128, alpha: 0.96)
        )
        public static let panelTint = macSemanticColor(
            light: MacSemanticColor(red: 0.925, green: 0.935, blue: 0.948, alpha: 0.92),
            dark: MacSemanticColor(red: 0.158, green: 0.168, blue: 0.184, alpha: 0.90)
        )
        public static let card = macSemanticColor(
            light: MacSemanticColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 0.92),
            dark: MacSemanticColor(red: 0.180, green: 0.190, blue: 0.208, alpha: 0.94)
        )
        public static let row = macSemanticColor(
            light: MacSemanticColor(red: 0.982, green: 0.985, blue: 0.990, alpha: 0.95),
            dark: MacSemanticColor(red: 0.205, green: 0.216, blue: 0.235, alpha: 0.92)
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
            dark: MacSemanticColor(red: 0.245, green: 0.257, blue: 0.278, alpha: 0.90)
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
    public static let popoverCornerRadius: CGFloat = 26
    public static let widgetCornerRadius: CGFloat = 22
    public static let panelCornerRadius: CGFloat = 14
    public static let rowCornerRadius: CGFloat = 7
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

public extension View {
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
