import SwiftUI

public enum DesignTokens {
    public enum Radius {
        public static let chip: CGFloat = 4
        public static let row: CGFloat = 12
        public static let card: CGFloat = 14
        public static let panel: CGFloat = 24
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
        public static let card = Color(nsColor: .controlBackgroundColor).opacity(0.82)
        public static let row = Color(nsColor: .controlBackgroundColor)
        public static let separator = Color(nsColor: .separatorColor).opacity(0.55)
        #elseif os(iOS)
        public static let panel = Color(.systemBackground)
        public static let panelTint = Color(.secondarySystemBackground)
        public static let card = Color(.secondarySystemBackground)
        public static let row = Color(.secondarySystemBackground)
        public static let separator = Color(.separator)
        #else
        public static let panel = Color.black
        public static let panelTint = Color.black.opacity(0.6)
        public static let card = Color.white.opacity(0.12)
        public static let row = Color.white.opacity(0.12)
        public static let separator = Color.white.opacity(0.16)
        #endif

        public static let text = Color.primary
        public static let secondaryText = Color.secondary
        public static let tertiaryText = Color.secondary.opacity(0.72)
    }
}
