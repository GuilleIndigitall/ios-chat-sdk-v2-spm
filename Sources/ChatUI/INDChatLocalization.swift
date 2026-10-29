import ChatCore
import Foundation

enum INDChatLocalization {
    static func text(_ key: String, configuration: INDChatConfiguration) -> String {
        let language = resolvedLanguage(for: configuration.localeIdentifier)
        let bundle = localizedBundle(for: language)
        return NSLocalizedString(key, tableName: nil, bundle: bundle, value: englishValue(for: key), comment: "")
    }

    static func dateLabel(for date: Date, relativeTo now: Date = .now, configuration: INDChatConfiguration) -> String {
        let locale = Locale(identifier: configuration.localeIdentifier ?? Locale.current.identifier)
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(date) { return text("chat.date.today", configuration: configuration) }
        if calendar.isDateInYesterday(date) { return text("chat.date.yesterday", configuration: configuration) }
        return date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }

    private static func resolvedLanguage(for localeIdentifier: String?) -> String {
        let identifier = localeIdentifier ?? Locale.current.identifier
        switch Locale(identifier: identifier).language.languageCode?.identifier.lowercased() {
        case "es": return "es"
        case "pt": return "pt"
        default: return "en"
        }
    }

    private static func localizedBundle(for language: String) -> Bundle {
        guard let path = Bundle.module.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .module }
        return bundle
    }

    private static func englishValue(for key: String) -> String {
        [
            "chat.open": "Open chat",
            "chat.open.hint": "Opens a support conversation",
            "chat.close": "Close chat",
            "chat.dismiss": "Dismiss",
            "chat.connecting": "Connecting…",
            "chat.reconnecting": "Reconnecting…",
            "chat.unauthorized": "Unauthorized",
            "chat.disconnected": "Disconnected",
            "chat.loadOlder": "Load earlier messages",
            "chat.loadingOlder": "Loading earlier messages",
            "chat.scrollToLatest": "Scroll to latest message",
            "chat.retry": "Retry",
            "chat.empty": "There are no messages yet",
            "chat.contacts": "Contacts",
            "chat.viewContact": "View contact",
            "chat.viewContacts": "View contacts",
            "chat.location": "Location",
            "chat.date.today": "Today",
            "chat.date.yesterday": "Yesterday"
        ][key] ?? key
    }
}
