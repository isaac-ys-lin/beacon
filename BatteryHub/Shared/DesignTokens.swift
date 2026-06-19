import SwiftUI

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

    public enum Palette {
        public static let charging = Color.green
        public static let healthy = Color(red: 0.36, green: 0.78, blue: 0.38)
        public static let warning = Color(red: 0.94, green: 0.62, blue: 0.20)
        public static let stale = Color(red: 0.72, green: 0.64, blue: 0.52)
        public static let critical = Color(red: 0.88, green: 0.22, blue: 0.20)
        public static let sync = Color.blue
        public static let accent = Color(red: 0.0, green: 0.39, blue: 1.0)

        #if os(macOS)
        public static let panel = Color(nsColor: .windowBackgroundColor).opacity(0.92)
        public static let panelTint = Color(nsColor: .underPageBackgroundColor).opacity(0.62)
        public static let card = Color(nsColor: .controlBackgroundColor).opacity(0.74)
        public static let row = Color(nsColor: .controlBackgroundColor)
        public static let separator = Color(nsColor: .separatorColor).opacity(0.55)
        public static let glassStroke = Color.white.opacity(0.28)
        public static let controlPill = Color(nsColor: .controlBackgroundColor).opacity(0.58)
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
        public static let hover = Color(nsColor: .selectedContentBackgroundColor).opacity(0.10)
        #else
        public static let hover = Color.accentColor.opacity(0.10)
        #endif
    }
}

public enum NativeMacStyle {
    public static let popoverCornerRadius: CGFloat = 26
    public static let panelCornerRadius: CGFloat = 14
    public static let rowCornerRadius: CGFloat = 7

    public static var subtleStroke: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor).opacity(0.26)
        #else
        Color(.separator).opacity(0.26)
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
        if #available(macOS 26.0, iOS 26.0, *) {
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
        if #available(macOS 26.0, iOS 26.0, *) {
            self.containerBackground(.regularMaterial, for: .window)
        } else {
            self.background(.regularMaterial)
        }
    }
}
