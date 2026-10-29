import Foundation

public enum INDChatLogLevel: Int, CaseIterable, Comparable, Sendable {
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4

    public static func < (lhs: INDChatLogLevel, rhs: INDChatLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var name: String {
        switch self {
        case .debug: "debug"
        case .info: "info"
        case .warning: "warning"
        case .error: "error"
        }
    }
}

public final class INDChatLogger: @unchecked Sendable {
    public var level: INDChatLogLevel
    public var sink: @Sendable (INDChatLogLevel, String, String) -> Void

    public init(
        level: INDChatLogLevel = .debug,
        sink: @escaping @Sendable (INDChatLogLevel, String, String) -> Void = { level, module, message in
            print("[INDChat][\(module)][\(level)] \(message)")
        }
    ) {
        self.level = level
        self.sink = sink
    }

    public func log(_ level: INDChatLogLevel, module: String, _ message: @autoclosure () -> String) {
        guard level.rawValue >= self.level.rawValue else { return }
        sink(level, module, message())
    }

    public func redactedDescription(of payload: Any) -> String {
        String(describing: redact(payload))
    }

    private func redact(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return Dictionary(uniqueKeysWithValues: dictionary.map { key, value in
                let normalizedKey = key.lowercased()
                let isSensitive = ["channelkey", "contactcode", "contactname", "token", "jwt", "password", "secret"].contains(normalizedKey)
                return (key, isSensitive ? "<redacted>" : redact(value))
            })
        }
        if let array = value as? [Any] { return array.map(redact) }
        return value
    }
}
