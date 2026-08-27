import Foundation

enum BeaconL10n {
    static func string(_ key: String, bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(
        _ key: String,
        _ arguments: CVarArg...,
        bundle: Bundle = .main
    ) -> String {
        String(
            format: string(key, bundle: bundle),
            locale: Locale.current,
            arguments: arguments
        )
    }
}
