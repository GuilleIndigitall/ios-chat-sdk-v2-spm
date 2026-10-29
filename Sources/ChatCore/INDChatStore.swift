import Combine
import Foundation

@MainActor
public final class INDChatStore: ObservableObject, INDChatControlling {
    @Published public private(set) var state: INDChatUIState

    private let configuration: INDChatConfiguration
    private let transport: INDChatTransport
    private let logger: INDChatLogger
    private let multimediaUploader: INDChatMultimediaUploading
    private let tagRepository: INDChatTagPersisting
    private let tagScope: INDChatTagScope
    private let requestedTags: [String]
    private var tagsInFlight = Set<String>()
    private var nextHistoryMessageID: Int?
    private var pendingMultimediaUpload: INDChatMultimediaUpload?
    private var multimediaUploadTask: Task<Void, Never>?
    nonisolated private let temporaryFiles = INDChatTemporaryFiles()

    public convenience init(
        configuration: INDChatConfiguration,
        transport: INDChatTransport? = nil,
        logger: INDChatLogger? = nil
    ) {
        self.init(
            configuration: configuration,
            transport: transport,
            logger: logger,
            multimediaUploader: INDChatMultimediaUploader(),
            tagRepository: INDChatTagRepository()
        )
    }

    init(
        configuration: INDChatConfiguration,
        transport: INDChatTransport? = nil,
        logger: INDChatLogger? = nil,
        multimediaUploader: INDChatMultimediaUploading,
        tagRepository: INDChatTagPersisting = INDChatTagRepository()
    ) {
        self.configuration = configuration
        let logger = logger ?? INDChatLogger(level: configuration.logLevel)
        self.logger = logger
        self.transport = transport ?? INDChatSocketIOTransport(logger: logger)
        self.multimediaUploader = multimediaUploader
        self.tagRepository = tagRepository
        self.tagScope = INDChatTagScope(
            baseURL: configuration.baseURL,
            channelKey: configuration.channelKey,
            contactCode: configuration.contactCode
        )
        let excludedTags = Set(indChatNormalizedTags(configuration.unassignTags).map { $0.lowercased() })
        self.requestedTags = indChatNormalizedTags(configuration.assignTags).filter { !excludedTags.contains($0.lowercased()) }
        self.state = INDChatUIState(isOpen: configuration.initiallyOpen)
        self.transport.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in self?.handle(event) }
        }
        if configuration.initiallyOpen { open() }
    }

    deinit {
        multimediaUploadTask?.cancel()
        temporaryFiles.removeAll()
        transport.disconnect()
    }

    public func open() {
        guard !state.isOpen || state.connection == .idle || state.connection == .disconnected else { return }
        state.isOpen = true
        do {
            logger.log(.info, module: "state", "Opening chat")
            let endpoint = try configuration.validatedEndpoint()
            state.connection = .connecting
            state.error = nil
            transport.connect(endpoint: endpoint)
        } catch let error as INDChatError {
            logger.log(.error, module: "state", "Invalid connection configuration")
            state.connection = .disconnected
            state.error = error
        } catch {
            logger.log(.error, module: "state", "The connection could not be prepared")
            state.connection = .disconnected
            state.error = .invalidConfiguration("The connection could not be prepared")
        }
    }

    public func close() {
        guard state.isOpen else { return }
        state.isOpen = false
        logger.log(.info, module: "state", "Closing chat")
        state.connection = .disconnected
        state.error = nil
        state.applicationId = nil
        state.isLoadingOlderMessages = false
        state.hasOlderMessages = false
        nextHistoryMessageID = nil
        cancelMultimediaUpload()
        removeLocalMultimediaFiles()
        transport.disconnect()
    }

    public func toggle() { state.isOpen ? close() : open() }

    public func clearAllTags() {
        tagRepository.clearConfirmedTags(for: tagScope)
        tagsInFlight.removeAll()
    }

    @discardableResult
    public func sendText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if handleDebugCommand(trimmed) { return true }
        guard state.canSendText else { return false }
        let message = INDChatMessage(
            id: UUID().uuidString,
            content: .text(trimmed),
            direction: .contact,
            createdAt: Date(),
            status: .pending
        )
        state.messages.append(message)
        sortMessages()
        transport.emit(event: "message:send", payload: [
            "clientMessageId": message.id,
            "messageContent": ["body": trimmed]
        ])
        return true
    }

    @discardableResult
    public func sendMultimedia(_ upload: INDChatMultimediaUpload) -> Bool {
        guard state.canSendText,
              !state.isUploadingMultimedia,
              validate(upload) else { return false }
        state.isUploadingMultimedia = true
        state.error = nil
        pendingMultimediaUpload = upload
        transport.emit(event: "multimedia:prepare", payload: [:])
        return true
    }

    @discardableResult
    public func buttonClicked(payload: String, text: String, quote: INDChatMessageQuote? = nil) -> Bool {
        let normalizedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state.canSendText, !normalizedPayload.isEmpty, !normalizedText.isEmpty else { return false }
        let message = INDChatMessage(
            id: UUID().uuidString,
            content: .text(normalizedText),
            direction: .contact,
            createdAt: Date(),
            status: .pending,
            quote: quote,
            buttonClick: INDChatButtonClick(payload: normalizedPayload, text: normalizedText)
        )
        state.messages.append(message)
        sortMessages()
        var button: [String: Any] = ["payload": normalizedPayload, "text": normalizedText]
        if let quote { button["quote"] = ["author": quote.author as Any, "content": quote.content] }
        transport.emit(event: "message:send", payload: [
            "clientMessageId": message.id,
            "messageContent": ["buttonClicked": button]
        ])
        return true
    }

    public func retryMessage(id: String) {
        guard let index = state.messages.firstIndex(where: { $0.id == id }),
              state.messages[index].direction == .contact,
              state.messages[index].status == .error,
              state.canSendText else { return }
        if let buttonClick = state.messages[index].buttonClick {
            retryButtonClick(buttonClick, quote: state.messages[index].quote, id: id, index: index)
            return
        }
        guard case .text = state.messages[index].content else {
            guard case .multimedia = state.messages[index].content else { return }
            retryMultimediaMessage(at: index, id: id)
            return
        }
        state.messages[index].status = .pending
        state.messages[index].error = nil
        switch state.messages[index].content {
        case let .text(body):
            transport.emit(event: "message:send", payload: [
                "clientMessageId": id,
                "messageContent": ["body": body]
            ])
        default:
            return
        }
    }

    private func retryMultimediaMessage(at index: Int, id: String) {
        guard case let .multimedia(multimedia) = state.messages[index].content,
              let multimediaID = multimedia.multimediaID else { return }
        state.messages[index].status = .pending
        state.messages[index].error = nil
        var payload: [String: Any] = ["multimediaType": multimedia.type.rawValue, "multimediaId": multimediaID]
        if multimedia.type == .document, let filename = multimedia.filename { payload["multimediaFilename"] = filename }
        if let caption = multimedia.caption { payload["caption"] = caption }
        transport.emit(event: "message:send", payload: ["clientMessageId": id, "messageContent": ["multimedia": payload]])
    }

    private func retryButtonClick(_ buttonClick: INDChatButtonClick, quote: INDChatMessageQuote?, id: String, index: Int) {
        state.messages[index].status = .pending
        state.messages[index].error = nil
        var button: [String: Any] = ["payload": buttonClick.payload, "text": buttonClick.text]
        if let quote { button["quote"] = ["author": quote.author as Any, "content": quote.content] }
        transport.emit(event: "message:send", payload: [
            "clientMessageId": id,
            "messageContent": ["buttonClicked": button]
        ])
    }

    public func requestOlderMessages() {
        guard state.canSendText, !state.isLoadingOlderMessages, state.hasOlderMessages else { return }
        state.isLoadingOlderMessages = true
        transport.emit(event: "history:request", payload: nextHistoryMessageID.map { ["fromMessageId": $0] } ?? [:])
    }

    private func handle(_ event: INDChatTransportEvent) {
        logger.log(.debug, module: "state", "Processing Socket.IO event: \(event.name)")
        switch event {
        case .connected:
            guard state.isOpen else { return }
            state.connection = .authenticating
        case let .disconnected(reconnecting, message):
            guard state.isOpen else { return }
            cancelMultimediaUpload()
            state.connection = reconnecting ? .reconnecting : .disconnected
            if reconnecting {
                state.error = nil
            } else {
                state.error = .connection(message)
                state.applicationId = nil
                state.isLoadingOlderMessages = false
                state.hasOlderMessages = false
                nextHistoryMessageID = nil
            }
        case let .authenticated(payload):
            guard state.isOpen else { return }
            state.connection = .authenticated
            state.error = nil
            state.applicationId = applicationID(from: payload)
            state.isLoadingOlderMessages = true
            assignPendingTags()
        case let .authenticateError(payload):
            let message = indChatErrorMessage(from: payload)
            state.connection = .unauthorized
            state.error = .authentication(message)
            state.applicationId = nil
            state.isLoadingOlderMessages = false
            cancelMultimediaUpload()
        case let .historyReceived(payload):
            guard let batch = INDChatMessageNormalizer.batch(from: payload) else {
                logger.log(.warning, module: "state", "Discarded history:received with an unsupported format")
                state.isLoadingOlderMessages = false
                return
            }
            logger.log(.info, module: "state", "History received: \(batch.messages.count) messages")
            nextHistoryMessageID = batch.nextMessageID
            state.hasOlderMessages = nextHistoryMessageID != nil
            state.isLoadingOlderMessages = false
            merge(batch.messages)
        case let .historyError(payload):
            state.isLoadingOlderMessages = false
            let message = indChatErrorMessage(from: payload) ?? "The message history could not be retrieved"
            state.error = .server(message)
        case let .messageReceived(payload):
            guard let batch = INDChatMessageNormalizer.batch(from: payload) else {
                logger.log(.warning, module: "state", "Discarded message:received with an unsupported format")
                return
            }
            logger.log(.info, module: "state", "Real-time message(s) received: \(batch.messages.count)")
            merge(batch.messages)
        case let .messageSent(payload):
            updateOutgoingStatusFromAck(payload: payload, status: .sent)
        case let .messageSendError(payload):
            updateOutgoingStatusFromAck(payload: payload, status: .error)
        case let .messageStatusError(payload):
            let message = indChatErrorMessage(from: payload) ?? "The message status could not be processed"
            state.error = .server(message)
        case let .multimediaPrepared(payload):
            beginMultimediaUpload(with: payload)
        case let .multimediaPrepareError(payload):
            state.isUploadingMultimedia = false
            pendingMultimediaUpload = nil
            let message = indChatErrorMessage(from: payload) ?? "The multimedia upload could not be prepared"
            state.error = .server(message)
        case let .tagAssigned(payload):
            saveConfirmedTags(from: payload)
        case .tagAssignError:
            tagsInFlight.removeAll()
        }
    }

    private func merge(_ messages: [INDChatMessage]) {
        for incoming in messages {
            if let clientMessageID = incoming.clientMessageId,
               let index = state.messages.firstIndex(where: { $0.id == clientMessageID }) {
                replaceLocalMessage(at: index, with: incoming)
                continue
            }
            if let index = state.messages.firstIndex(where: { $0.id == incoming.id || ($0.serverId != nil && $0.serverId == incoming.serverId) }) {
                removeLocalFile(from: state.messages[index])
                state.messages[index] = incoming
                continue
            }
            if incoming.direction == .contact,
               case let .multimedia(remoteMultimedia) = incoming.content,
               let multimediaID = remoteMultimedia.multimediaID,
               let index = state.messages.firstIndex(where: {
                   guard $0.direction == .contact, case let .multimedia(localMultimedia) = $0.content else { return false }
                   return localMultimedia.multimediaID == multimediaID
               }) {
                replaceLocalMessage(at: index, with: incoming)
                continue
            }
            if incoming.direction == .contact,
               case let .text(text) = incoming.content,
               let index = state.messages.firstIndex(where: {
                   guard $0.direction == .contact, case let .text(local) = $0.content else { return false }
                   return local == text && abs($0.createdAt.timeIntervalSince(incoming.createdAt)) <= 15 && Date().timeIntervalSince($0.createdAt) <= 60
               }) {
                state.messages[index].serverId = incoming.serverId
                state.messages[index].status = .sent
                continue
            }
            state.messages.append(incoming)
        }
        sortMessages()
    }

    private func assignPendingTags() {
        let confirmedTags = Set(indChatNormalizedTags(tagRepository.confirmedTags(for: tagScope)).map { $0.lowercased() })
        let tags = requestedTags.filter {
            !confirmedTags.contains($0.lowercased()) && !tagsInFlight.contains($0.lowercased())
        }
        guard !tags.isEmpty else { return }
        tagsInFlight.formUnion(tags.map { $0.lowercased() })
        transport.emit(event: "contact:tag:assign", payload: ["tags": tags])
    }

    private func saveConfirmedTags(from payload: Any) {
        guard let value = payload as? [String: Any] else { return }
        let confirmed = indChatNormalizedTags(value["tags"] as? [String] ?? [])
        guard !confirmed.isEmpty else { return }
        let requestedByName = Dictionary(uniqueKeysWithValues: requestedTags.map { ($0.lowercased(), $0) })
        let accepted = confirmed.compactMap { requestedByName[$0.lowercased()] }
        guard !accepted.isEmpty else { return }
        let existing = tagRepository.confirmedTags(for: tagScope)
        tagRepository.saveConfirmedTags(indChatNormalizedTags(existing + accepted), for: tagScope)
        tagsInFlight.subtract(accepted.map { $0.lowercased() })
    }

    private func updateOutgoingStatusFromAck(payload: Any, status: INDChatMessageStatus) {
        guard let value = payload as? [String: Any],
              let clientMessageID = value["clientMessageId"] as? String,
              let index = state.messages.firstIndex(where: { $0.id == clientMessageID }) else { return }
        state.messages[index].status = status
        state.messages[index].error = status == .error ? (value["message"] as? String ?? "The message could not be sent") : nil
        if status == .sent, let sentAt = date(from: value["sentAt"]) {
            state.messages[index].createdAt = sentAt
            sortMessages()
        }
    }

    private func beginMultimediaUpload(with payload: Any) {
        guard state.isUploadingMultimedia, let upload = pendingMultimediaUpload else { return }
        guard let applicationID = state.applicationId else {
            failMultimediaUpload(.server("No applicationId was received for the multimedia upload"))
            return
        }
        guard let value = payload as? [String: Any],
              let jwt = value["jwt"] as? String,
              !jwt.isEmpty else {
            state.isUploadingMultimedia = false
            pendingMultimediaUpload = nil
            logger.log(.error, module: "state", "multimedia:prepared did not include a valid JWT")
            state.error = .server("The multimedia upload could not be prepared")
            return
        }

        logger.log(.info, module: "state", "Uploading multimedia file")
        let baseURL = configuration.baseURL
        multimediaUploadTask = Task { [weak self, multimediaUploader] in
            do {
                let multimediaID = try await multimediaUploader.upload(
                    upload,
                    baseURL: baseURL,
                    applicationID: applicationID,
                    jwt: jwt
                )
                self?.completeMultimediaUpload(upload, multimediaID: multimediaID)
            } catch let error as INDChatError {
                self?.failMultimediaUpload(error)
            } catch {
                self?.failMultimediaUpload(.server("The multimedia file could not be uploaded"))
            }
        }
    }

    private func completeMultimediaUpload(_ upload: INDChatMultimediaUpload, multimediaID: Int) {
        guard state.isUploadingMultimedia else { return }
        clearMultimediaUploadState()
        logger.log(.info, module: "state", "Multimedia file uploaded; sending message")
        let clientMessageID = UUID().uuidString
        do {
            let localURL = try persistLocally(upload, clientMessageID: clientMessageID)
            state.messages.append(INDChatMessage(
                id: clientMessageID,
                clientMessageId: clientMessageID,
                content: .multimedia(INDChatMultimedia(
                    type: upload.type,
                    url: localURL,
                    filename: upload.filename,
                    caption: upload.caption,
                    mimeType: upload.mimeType,
                    multimediaID: multimediaID
                )),
                direction: .contact,
                createdAt: Date(),
                status: .pending
            ))
            sortMessages()
        } catch {
            failMultimediaUpload(.server("The multimedia file could not be prepared for display"))
            return
        }
        var multimedia: [String: Any] = [
            "multimediaType": upload.type.rawValue,
            "multimediaId": multimediaID
        ]
        if upload.type == .document { multimedia["multimediaFilename"] = upload.filename }
        if let caption = upload.caption { multimedia["caption"] = caption }
        transport.emit(event: "message:send", payload: [
            "clientMessageId": clientMessageID,
            "messageContent": ["multimedia": multimedia]
        ])
    }

    private func failMultimediaUpload(_ error: INDChatError) {
        clearMultimediaUploadState()
        logger.log(.error, module: "state", "Multimedia upload failed: \(error.localizedDescription)")
        state.error = error
    }

    private func cancelMultimediaUpload() {
        multimediaUploadTask?.cancel()
        clearMultimediaUploadState()
    }

    private func clearMultimediaUploadState() {
        multimediaUploadTask = nil
        pendingMultimediaUpload = nil
        state.isUploadingMultimedia = false
    }

    private func persistLocally(_ upload: INDChatMultimediaUpload, clientMessageID: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("IndigitallChat", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = "\(clientMessageID)-\(upload.filename.replacingOccurrences(of: "/", with: "_"))"
        let url = directory.appendingPathComponent(filename)
        try upload.data.write(to: url, options: .atomic)
        temporaryFiles.insert(url)
        return url
    }

    private func replaceLocalMessage(at index: Int, with incoming: INDChatMessage) {
        let localID = state.messages[index].id
        removeLocalFile(from: state.messages[index])
        state.messages[index] = INDChatMessage(
            id: localID,
            serverId: incoming.serverId,
            clientMessageId: incoming.clientMessageId ?? localID,
            content: incoming.content,
            direction: incoming.direction,
            createdAt: incoming.createdAt,
            status: .sent,
            quote: incoming.quote,
            buttonClick: nil
        )
    }

    private func removeLocalMultimediaFiles() {
        state.messages.forEach(removeLocalFile)
    }

    private func removeLocalFile(from message: INDChatMessage) {
        guard case let .multimedia(multimedia) = message.content,
              multimedia.url.isFileURL else { return }
        try? FileManager.default.removeItem(at: multimedia.url)
          temporaryFiles.remove(multimedia.url)
    }

    private func date(from value: Any?) -> Date? {
        if let value = value as? TimeInterval { return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1_000 : value) }
        if let value = value as? NSNumber { return date(from: value.doubleValue) }
        guard let value = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func validate(_ upload: INDChatMultimediaUpload) -> Bool {
        guard !upload.data.isEmpty,
              !upload.filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !upload.mimeType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let limit: Int
        switch upload.type {
        case .image:
            guard ["image/png", "image/jpeg"].contains(upload.mimeType.lowercased()) else { return false }
            limit = 5 * 1_024 * 1_024
        case .video:
            guard ["video/mp4", "video/3gpp"].contains(upload.mimeType.lowercased()) else { return false }
            limit = 15 * 1_024 * 1_024
        case .audio:
            limit = 15 * 1_024 * 1_024
        case .document:
            limit = 100 * 1_024 * 1_024
        }
        return upload.data.count <= limit
    }

    private func applicationID(from payload: Any) -> Int? {
        guard let value = payload as? [String: Any] else { return nil }
        if let id = value["applicationId"] as? Int { return id }
        if let id = value["applicationId"] as? NSNumber { return id.intValue }
        return nil
    }

    private func sortMessages() { state.messages.sort { $0.createdAt < $1.createdAt } }

    private func handleDebugCommand(_ text: String) -> Bool {
        guard let command = INDChatDebugFixture.command(from: text) else { return false }

        #if DEBUG
        if configuration.debug {
            logger.log(.debug, module: "state", "Mostrando fixture local: \(command.name)")
            state.messages.append(command.message)
            sortMessages()
        }
        #endif

        // Known fixture commands are deliberately discarded in release builds, and when
        // debug fixtures are disabled, so they are never emitted to the chat backend.
        return true
    }
}

private enum INDChatDebugFixture {
    case contact(String)
    case image(String)
    case video(String)
    case audio(String)
    case document(String)
    case location(String)
    case template(String)
    case carousel
    case interactive(String)

    var name: String {
        switch self {
        case .contact: "contact"
        case .image: "image"
        case .video: "video"
        case .audio: "audio"
        case .document: "document"
        case .location: "location"
        case .template: "template"
        case .carousel: "carousel"
        case .interactive: "interactive"
        }
    }

    var message: INDChatMessage {
        let content: INDChatMessageContent
        switch self {
        case let .contact(name):
            content = .contacts([INDChatContact(
                name: name,
                phones: ["+34 600 000 000"],
                emails: ["demo@example.com"],
                addresses: ["Puerta del Sol, Madrid"],
                urls: [URL(string: "https://example.com")!]
            )])
        case let .image(url):
            content = .multimedia(Self.multimedia(type: .image, url: url, filename: "imagen.jpg"))
        case let .video(url):
            content = .multimedia(Self.multimedia(type: .video, url: url, filename: "video.mp4"))
        case let .audio(url):
            content = .multimedia(Self.multimedia(type: .audio, url: url, filename: "audio.mp3"))
        case let .document(url):
            content = .multimedia(Self.multimedia(type: .document, url: url, filename: "documento.pdf"))
        case let .location(name):
            content = .location(INDChatLocation(latitude: 40.4168, longitude: -3.7038, name: name, address: "Puerta del Sol, Madrid"))
        case let .template(body):
            content = .template(INDChatTemplate(
                id: "debug-template",
                header: "Modo desarrollo",
                body: body,
                footer: "Fixture local",
                buttons: [INDChatInteractiveOption(id: "debug-template-reply", title: "Aceptar", payload: "debug-template-accept")]
            ))
        case .carousel:
            content = .carousel([
                Self.carouselTemplate(id: "1", body: "Producto uno"),
                Self.carouselTemplate(id: "2", body: "Producto dos"),
                Self.carouselTemplate(id: "3", body: "Producto tres")
            ])
        case let .interactive(body):
            content = .interactive(INDChatInteractive(
                kind: .button,
                body: body,
                options: [
                    INDChatInteractiveOption(id: "debug-yes", title: "Sí", payload: "debug-yes"),
                    INDChatInteractiveOption(id: "debug-no", title: "No", payload: "debug-no")
                ]
            ))
        }
        return INDChatMessage(
            id: "debug-\(UUID().uuidString)",
            content: content,
            direction: .business,
            createdAt: Date(),
            status: .sent
        )
    }

    static func command(from text: String) -> Self? {
        let parts = text.split(maxSplits: 1, whereSeparator: \ .isWhitespace)
        guard let rawCommand = parts.first?.lowercased() else { return nil }
        let argument = parts.dropFirst().first
            .map(String.init)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        switch rawCommand {
        case "/contact": return Self.contact(argument ?? "Contacto de ejemplo")
        case "/image": return Self.image(argument ?? "https://picsum.photos/600/400")
        case "/video": return Self.video(argument ?? "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4")
        case "/audio": return Self.audio(argument ?? "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3")
        case "/document": return Self.document(argument ?? "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf")
        case "/location": return Self.location(argument ?? "Puerta del Sol")
        case "/template": return Self.template(argument ?? "Template de ejemplo")
        case "/carousel" where argument == nil: return Self.carousel
        case "/interactive": return Self.interactive(argument ?? "¿Confirmas tu cita?")
        default: return nil
        }
    }

    private static func multimedia(type: INDChatMultimediaType, url: String, filename: String) -> INDChatMultimedia {
        INDChatMultimedia(type: type, url: URL(string: url)!, filename: filename)
    }

    private static func carouselTemplate(id: String, body: String) -> INDChatTemplate {
        INDChatTemplate(
            id: "debug-carousel-\(id)",
            header: "Catálogo",
            body: body,
            buttons: [INDChatInteractiveOption(id: "debug-carousel-\(id)-reply", title: "Elegir", payload: "debug-carousel-\(id)")]
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private final class INDChatTemporaryFiles: @unchecked Sendable {
    private let lock = NSLock()
    private var urls = Set<URL>()

    func insert(_ url: URL) {
        lock.lock()
        urls.insert(url)
        lock.unlock()
    }

    func remove(_ url: URL) {
        lock.lock()
        urls.remove(url)
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        let temporaryURLs = urls
        urls.removeAll()
        lock.unlock()
        temporaryURLs.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
