import Foundation

public struct INDChatEndpoint: Equatable, Sendable {
    private static let webChatSocketPath = "/webchat/socket"
    private static let supportedTransports: [INDChatSocketTransport] = [.websocket, .polling]

    public let url: URL
    public let socketPath: String
    public let query: [String: String]
    public let auth: [String: String]
    public let transports: [INDChatSocketTransport]

    init(configuration: INDChatConfiguration) throws {
        let trimmedBase = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard let components = URLComponents(string: trimmedBase),
              let url = components.url,
              components.scheme == "https" || components.scheme == "http" else {
            throw INDChatError.invalidConfiguration("baseURL debe ser una URL HTTP(S) válida")
        }

        self.url = url
        self.socketPath = Self.webChatSocketPath
        self.query = [
            "contactCode": configuration.contactCode,
            "contactName": configuration.contactName ?? ""
        ].filter { !$0.value.isEmpty }
        self.auth = ["channelKey": configuration.channelKey]
        self.transports = Self.supportedTransports
    }
}
