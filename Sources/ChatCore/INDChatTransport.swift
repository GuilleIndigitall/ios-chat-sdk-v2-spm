@preconcurrency import SocketIO
import Foundation

public enum INDChatTransportEvent {
    case connected
    case disconnected(reconnecting: Bool, message: String?)
    case authenticated(Any)
    case authenticateError(Any)
    case historyReceived(Any)
    case historyError(Any)
    case messageSent(Any)
    case messageSendError(Any)
    case messageReceived(Any)
    case messageStatusError(Any)
    case multimediaPrepared(Any)
    case multimediaPrepareError(Any)
    case tagAssigned(Any)
    case tagAssignError(Any)

    var name: String {
        switch self {
        case .connected: "connected"
        case .disconnected: "disconnected"
        case .authenticated: "contact:authenticated"
        case .authenticateError: "contact:authenticateError"
        case .historyReceived: "history:received"
        case .historyError: "history:error"
        case .messageSent: "message:sent"
        case .messageSendError: "message:sendError"
        case .messageReceived: "message:received"
        case .messageStatusError: "message:statusError"
        case .multimediaPrepared: "multimedia:prepared"
        case .multimediaPrepareError: "multimedia:prepareError"
        case .tagAssigned: "contact:tag:assigned"
        case .tagAssignError: "contact:tag:assignError"
        }
    }
}

public protocol INDChatTransport: AnyObject {
    var onEvent: ((INDChatTransportEvent) -> Void)? { get set }
    func connect(endpoint: INDChatEndpoint)
    func disconnect()
    func emit(event: String, payload: [String: Any])
}

public final class INDChatSocketIOTransport: INDChatTransport, @unchecked Sendable {
    public var onEvent: ((INDChatTransportEvent) -> Void)?

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private let queue = DispatchQueue(label: "com.indigitall.ios.ios-chat.socket")
    private let logger: INDChatLogger

    public init(logger: INDChatLogger = .init()) {
        self.logger = logger
    }

    public func connect(endpoint: INDChatEndpoint) {
        logger.log(.info, module: "socket", "Starting Socket.IO connection")
        disconnect()
        var config: SocketIOClientConfiguration = [
            .log(false),
            .compress,
            .reconnects(true),
            .reconnectAttempts(5),
            .reconnectWait(1),
            .reconnectWaitMax(10),
            .path(endpoint.socketPath),
            .connectParams(endpoint.query)
        ]
        if endpoint.transports == [.websocket] { config.insert(.forceWebsockets(true)) }
        if endpoint.transports == [.polling] { config.insert(.forcePolling(true)) }
        let manager = SocketManager(
            socketURL: endpoint.url,
            config: config
        )
        let socket = manager.defaultSocket
        installHandlers(on: socket)
        self.manager = manager
        self.socket = socket
        socket.connect(withPayload: endpoint.auth)
    }

    public func disconnect() {
        logger.log(.info, module: "socket", "Disconnecting Socket.IO")
        socket?.removeAllHandlers()
        socket?.disconnect()
        socket = nil
        manager = nil
    }

    public func emit(event: String, payload: [String: Any]) {
        logger.log(.debug, module: "socket", "Emitting event \(event)")
        queue.async { [weak self] in self?.socket?.emit(event, payload) }
    }

    private func installHandlers(on socket: SocketIOClient) {
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            self?.logger.log(.info, module: "socket", "Event received: connect")
            self?.onEvent?(.connected)
        }
        socket.on(clientEvent: .disconnect) { [weak self] data, _ in
            self?.logger.log(.warning, module: "socket", "Event received: disconnect | data: \(self?.logger.redactedDescription(of: data) ?? "[]")")
            self?.onEvent?(.disconnected(reconnecting: false, message: indChatErrorMessage(from: data)))
        }
        socket.on(clientEvent: .reconnect) { [weak self] data, _ in
            self?.logger.log(.info, module: "socket", "Event received: reconnect | data: \(self?.logger.redactedDescription(of: data) ?? "[]")")
            self?.onEvent?(.disconnected(reconnecting: true, message: indChatErrorMessage(from: data)))
        }
        socket.on(clientEvent: .reconnectAttempt) { [weak self] data, _ in
            self?.logger.log(.warning, module: "socket", "Socket.IO reconnection attempt | remaining: \(self?.logger.redactedDescription(of: data) ?? "[]")")
        }
        socket.on(clientEvent: .error) { [weak self] data, _ in
            self?.logger.log(.error, module: "socket", "Socket.IO error | data: \(self?.logger.redactedDescription(of: data) ?? "[]")")
        }
        socket.on(clientEvent: .statusChange) { [weak self] data, _ in
            self?.logger.log(.debug, module: "socket", "Socket.IO status change | data: \(self?.logger.redactedDescription(of: data) ?? "[]")")
        }
        socket.on("contact:authenticated") { [weak self] data, _ in
            self?.logger.log(.info, module: "socket", "Event received: contact:authenticated | data: \(self?.logger.redactedDescription(of: data) ?? "[]")")
            self?.onEvent?(.authenticated(data.first as Any))
        }
        socket.on("contact:authenticateError") { [weak self] data, _ in
            self?.logger.log(.error, module: "socket", "Event received: contact:authenticateError | data: \(self?.logger.redactedDescription(of: data) ?? "[]")")
            self?.onEvent?(.authenticateError(data.first as Any))
        }
        socket.on("history:received") { [weak self] data, _ in
            self?.logger.log(.debug, module: "socket", "Event received: history:received | data: \(self?.logger.redactedDescription(of: data) ?? "[]")")
            self?.onEvent?(.historyReceived(data.first as Any))
        }
        socket.on("history:error") { [weak self] data, _ in
            self?.logger.log(.warning, module: "socket", "Event received: history:error | data: \(self?.logger.redactedDescription(of: data) ?? "[]")")
            self?.onEvent?(.historyError(data.first as Any))
        }
        socket.on("message:sent") { [weak self] data, _ in
            self?.logger.log(.debug, module: "socket", "Event received: message:sent | data: \(self?.logger.redactedDescription(of: data) ?? "[]")")
            self?.onEvent?(.messageSent(data.first as Any))
        }
        socket.on("message:sendError") { [weak self] data, _ in
            self?.logger.log(.warning, module: "socket", "Event received: message:sendError | data: \(self?.logger.redactedDescription(of: data) ?? "[]")")
            self?.onEvent?(.messageSendError(data.first as Any))
        }
        socket.on("message:received") { [weak self] data, _ in
            self?.logger.log(.debug, module: "socket", "Event received: message:received | data: \(self?.logger.redactedDescription(of: data) ?? "[]")")
            self?.onEvent?(.messageReceived(data.first as Any))
        }
        socket.on("message:statusError") { [weak self] data, _ in
            self?.logger.log(.warning, module: "socket", "Event received: message:statusError | data: \(self?.logger.redactedDescription(of: data) ?? "[]")")
            self?.onEvent?(.messageStatusError(data.first as Any))
        }
        socket.on("multimedia:prepared") { [weak self] data, _ in
            self?.logger.log(.debug, module: "socket", "Event received: multimedia:prepared | data: \(self?.logger.redactedDescription(of: data) ?? "[]")")
            self?.onEvent?(.multimediaPrepared(data.first as Any))
        }
        socket.on("multimedia:prepareError") { [weak self] data, _ in
            self?.logger.log(.warning, module: "socket", "Event received: multimedia:prepareError | data: \(self?.logger.redactedDescription(of: data) ?? "[]")")
            self?.onEvent?(.multimediaPrepareError(data.first as Any))
        }
        socket.on("contact:tag:assigned") { [weak self] data, _ in
            self?.logger.log(.debug, module: "socket", "Event received: contact:tag:assigned | data: \(self?.logger.redactedDescription(of: data) ?? "[]")")
            self?.onEvent?(.tagAssigned(data.first as Any))
        }
        socket.on("contact:tag:assignError") { [weak self] data, _ in
            self?.logger.log(.warning, module: "socket", "Event received: contact:tag:assignError | data: \(self?.logger.redactedDescription(of: data) ?? "[]")")
            self?.onEvent?(.tagAssignError(data.first as Any))
        }
    }
}

func indChatErrorMessage(from payload: Any) -> String? {
    if let message = (payload as? [String: Any])?["message"] as? String,
       !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return message
    }
    if let values = payload as? [Any] {
        return values.lazy.compactMap(indChatErrorMessage(from:)).first
    }
    return payload as? String
}
