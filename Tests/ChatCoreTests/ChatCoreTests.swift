@testable import ChatCore
import XCTest

final class ChatCoreTests: XCTestCase {
    func testThemeDefaultsToWhatsAppVisualStyle() {
        let theme = INDChatTheme()

        XCTAssertEqual(theme.visualStyle, .whatsApp)
        XCTAssertEqual(theme.launcherAppearance, .init())
    }

    func testThemeAcceptsCustomLauncherAppearance() {
        let appearance = INDChatLauncherAppearance(
            icon: .asset(name: "SupportLauncher"),
            iconColorHex: "#FFFFFF",
            backgroundColorHex: "#123456"
        )
        let theme = INDChatTheme(launcherAppearance: appearance)

        XCTAssertEqual(theme.launcherAppearance, appearance)
    }

    func testThemeAcceptsCustomHeaderAndConversationBackgrounds() {
        let header = INDChatHeaderBackground.gradient(INDChatGradient(
            colors: ["#112233", "#445566"],
            startPoint: .leading,
            endPoint: .trailing
        ))
        let conversation = INDChatConversationBackground.image(assetName: "ChatBackground")
        let appearance = INDChatCustomAppearance(
            headerBackground: header,
            conversationBackground: conversation
        )
        let theme = INDChatTheme(visualStyle: .custom(appearance))

        XCTAssertEqual(theme.visualStyle, .custom(appearance))
    }

    @MainActor
    func testDebugInteractiveFixtureIsLocalAndDoesNotRequireAuthentication() {
        let transport = FakeTransport()
        let store = INDChatStore(
            configuration: INDChatConfiguration(
                baseURL: "https://chat.example.com",
                channelKey: "channel",
                contactCode: "contact",
                debug: true
            ),
            transport: transport
        )

        XCTAssertTrue(store.sendText("/interactive ¿Confirmas tu cita?"))
        XCTAssertTrue(transport.emissions.isEmpty)
        XCTAssertEqual(store.state.messages.count, 1)
        guard case let .interactive(interactive) = store.state.messages[0].content else {
            return XCTFail("Se esperaba un fixture interactive")
        }
        XCTAssertEqual(interactive.body, "¿Confirmas tu cita?")
    }

    @MainActor
    func testKnownDebugCommandIsDiscardedWhenDebugIsDisabled() {
        let transport = FakeTransport()
        let store = INDChatStore(
            configuration: INDChatConfiguration(baseURL: "https://chat.example.com", channelKey: "channel", contactCode: "contact"),
            transport: transport
        )

        XCTAssertTrue(store.sendText("/carousel"))
        XCTAssertTrue(transport.emissions.isEmpty)
        XCTAssertTrue(store.state.messages.isEmpty)
    }

    func testEndpointUsesBaseURLAndWebchatSocketPath() throws {
        let configuration = INDChatConfiguration(
            baseURL: "https://chat.example.com",
            channelKey: "channel",
            contactCode: "contact"
        )
        let endpoint = try configuration.validatedEndpoint()

        XCTAssertEqual(endpoint.url.absoluteString, "https://chat.example.com")
        XCTAssertEqual(endpoint.socketPath, "/webchat/socket")
        XCTAssertEqual(endpoint.auth["channelKey"], "channel")
        XCTAssertEqual(endpoint.query["contactCode"], "contact")
    }

    func testTextMessageNormalizesLegacyTimestamp() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let message = INDChatMessageNormalizer.message(from: [
            "id": "42",
            "contentType": "text",
            "content": ["body": "Hola"],
            "sendType": "incoming",
            "timestamp": date.timeIntervalSince1970
        ])

        XCTAssertEqual(message?.id, "server:42")
        XCTAssertEqual(message?.serverId, "42")
        XCTAssertEqual(message?.direction, .contact)
        XCTAssertEqual(message?.body, "Hola")
    }

    func testMultimediaMessagesNormalizeSupportedReceivedContent() {
        let payloads: [(INDChatMultimediaType, [String: Any])] = [
            (.image, ["multimediaType": "image", "multimediaUrl": "https://cdn.example.com/image.jpg", "caption": "Imagen"]),
            (.video, ["multimediaType": "video", "multimediaUrl": "https://cdn.example.com/video.mp4"]),
            (.audio, ["multimediaType": "audio", "multimediaUrl": "https://cdn.example.com/audio.m4a"]),
            (.document, ["multimediaType": "document", "multimediaUrl": "https://cdn.example.com/manual.pdf", "multimediaFilename": "manual.pdf"])
        ]

        for (expectedType, multimedia) in payloads {
            let message = INDChatMessageNormalizer.message(from: [
                "id": UUID().uuidString,
                "contentType": "multimedia",
                "content": ["multimedia": multimedia],
                "sendType": "proactive",
                "createdAt": "2026-07-10T10:00:00.000Z"
            ])

            guard case let .multimedia(value)? = message?.content else {
                XCTFail("Se esperaba contenido multimedia \(expectedType)")
                continue
            }
            XCTAssertEqual(value.type, expectedType)
            XCTAssertEqual(value.url.host, "cdn.example.com")
        }
    }

    func testMultimediaMessageRejectsUnusableContent() {
        let invalidURL = INDChatMessageNormalizer.message(from: [
            "id": 42,
            "contentType": "multimedia",
            "content": ["multimedia": ["multimediaType": "image", "multimediaUrl": "http://cdn.example.com/image.jpg"]],
            "sendType": "proactive",
            "createdAt": "2026-07-10T10:00:00.000Z"
        ])
        let documentWithoutName = INDChatMessageNormalizer.message(from: [
            "id": 43,
            "contentType": "multimedia",
            "content": ["multimedia": ["multimediaType": "document", "multimediaUrl": "https://cdn.example.com/manual.pdf"]],
            "sendType": "proactive",
            "createdAt": "2026-07-10T10:00:00.000Z"
        ])

        XCTAssertNil(invalidURL)
        XCTAssertNil(documentWithoutName)
    }

    func testRichReceivedContentNormalizesAndRejectsInvalidLocation() {
        let common: [String: Any] = ["id": 1, "sendType": "proactive", "createdAt": "2026-09-09T10:00:00.000Z"]
        let template = INDChatMessageNormalizer.message(from: common.merging([
            "contentType": "template",
            "content": ["template": ["id": "welcome", "components": [["type": "BODY", "text": "Bienvenido"]]]]
        ]) { $1 })
        let carousel = INDChatMessageNormalizer.message(from: common.merging([
            "contentType": "carousel",
            "content": ["cards": [["id": "one", "components": [["type": "BODY", "text": "Primera"]]], ["id": "two", "components": [["type": "BODY", "text": "Segunda"]]]]]
        ]) { $1 })
        let interactive = INDChatMessageNormalizer.message(from: common.merging([
            "contentType": "interactive",
            "content": ["interactive": ["type": "button", "body": "¿Continuar?", "buttons": [["id": "yes", "title": "Sí", "payload": "opaque-value"]]]]
        ]) { $1 })
        let contactsPayload: [String: Any] = [
            "contacts": [[
                "name": "Ana",
                "phones": [["phone": "+34600000000"]],
                "emails": [["email": "ana@example.com"]]
            ]]
        ]
        let contacts = INDChatMessageNormalizer.message(from: common.merging([
            "contentType": "contacts",
            "content": contactsPayload
        ]) { $1 })
        let location = INDChatMessageNormalizer.message(from: common.merging([
            "contentType": "location", "content": ["location": ["latitude": 40.4168, "longitude": -3.7038, "name": "Madrid"]]
        ]) { $1 })
        let invalidLocation = INDChatMessageNormalizer.message(from: common.merging([
            "contentType": "location", "content": ["location": ["latitude": 100.0, "longitude": -3.7038]]
        ]) { $1 })

        guard case let .template(templateContent)? = template?.content else { return XCTFail("Se esperaba template") }
        XCTAssertEqual(templateContent.body, "Bienvenido")
        guard case let .carousel(carouselContent)? = carousel?.content else { return XCTFail("Se esperaba carrusel") }
        XCTAssertEqual(carouselContent.count, 2)
        guard case let .interactive(interactiveContent)? = interactive?.content else { return XCTFail("Se esperaba interactive") }
        XCTAssertEqual(interactiveContent.options.first?.payload, "opaque-value")
        guard case let .contacts(contactsContent)? = contacts?.content else { return XCTFail("Se esperaban contactos") }
        XCTAssertEqual(contactsContent.first?.emails, ["ana@example.com"])
        guard case let .location(locationContent)? = location?.content else { return XCTFail("Se esperaba ubicación") }
        XCTAssertEqual(locationContent.latitude, 40.4168)
        XCTAssertNil(invalidLocation)
    }

    func testNestedInteractiveReplyNormalizesAsActionableButton() {
        let message = INDChatMessageNormalizer.message(from: [
            "id": 2,
            "contentType": "interactive",
            "content": ["interactive": [
                "type": "button",
                "body": ["text": "Selecciona una opción"],
                "action": ["buttons": [["type": "reply", "reply": ["id": "opaque-reply", "title": "Continuar"]]]]
            ]],
            "sendType": "proactive",
            "createdAt": "2026-09-09T10:00:00.000Z"
        ])

        guard case let .interactive(interactive)? = message?.content else { return XCTFail("Se esperaba interactive") }
        XCTAssertEqual(interactive.body, "Selecciona una opción")
        XCTAssertEqual(interactive.options, [INDChatInteractiveOption(id: "opaque-reply", title: "Continuar", payload: "opaque-reply")])
    }

    func testQuoteNormalizesReferenceAndDirectionForNavigation() {
        let message = INDChatMessageNormalizer.message(from: [
            "id": 3,
            "contentType": "text",
            "content": "Respuesta",
            "sendType": "incoming",
            "createdAt": "2026-09-09T10:00:00.000Z",
            "quote": [
                "messageId": 2,
                "content": "Mensaje original",
                "sendType": "proactive",
                "author": "Agente"
            ]
        ])

        XCTAssertEqual(message?.quote, INDChatMessageQuote(
            author: "Agente",
            content: "Mensaje original",
            referencedMessageID: "2",
            direction: .business
        ))
    }

    func testMultimediaUploaderUsesWebChatJWTMultipartRequest() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultimediaUploadURLProtocol.self]
        let uploader = INDChatMultimediaUploader(session: URLSession(configuration: configuration))
        MultimediaUploadURLProtocol.response = (201, #"{"data":{"id":123}}"#.data(using: .utf8)!)
        let upload = INDChatMultimediaUpload(
            data: Data("PDF".utf8),
            type: .document,
            filename: "manual.pdf",
            mimeType: "application/pdf"
        )

        let identifier = try await uploader.upload(
            upload,
            baseURL: "https://dev.chat-v2.indigitall.com/webchat",
            applicationID: 4444,
            jwt: "temporary-jwt"
        )

        XCTAssertEqual(identifier, 123)
        XCTAssertEqual(MultimediaUploadURLProtocol.request?.url?.absoluteString, "https://dev.api.indigitall.com/v2/chat/4444/multimedia?jwt=temporary-jwt")
        XCTAssertEqual(MultimediaUploadURLProtocol.request?.httpMethod, "POST")
        XCTAssertTrue(MultimediaUploadURLProtocol.request?.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = String(data: uploader.multipartBody(upload, boundary: "test-boundary"), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("name=\"type\""))
        XCTAssertTrue(body.contains("document"))
        XCTAssertTrue(body.contains("name=\"title\""))
        XCTAssertTrue(body.contains("manual.pdf"))
        XCTAssertTrue(body.contains("name=\"file\"; filename=\"manual.pdf\""))
        XCTAssertNil(MultimediaUploadURLProtocol.request?.value(forHTTPHeaderField: "Authorization"))
    }

    func testMultimediaUploaderDerivesProductionAPIURLWithoutEnvironmentPrefix() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultimediaUploadURLProtocol.self]
        let uploader = INDChatMultimediaUploader(session: URLSession(configuration: configuration))
        MultimediaUploadURLProtocol.response = (201, #"{"data":{"id":123}}"#.data(using: .utf8)!)

        _ = try await uploader.upload(
            INDChatMultimediaUpload(data: Data("image".utf8), type: .image, filename: "image.jpg", mimeType: "image/jpeg"),
            baseURL: "https://chat-v2.indigitall.com/webchat",
            applicationID: 4444,
            jwt: "temporary-jwt"
        )

        XCTAssertEqual(MultimediaUploadURLProtocol.request?.url?.absoluteString, "https://api.indigitall.com/v2/chat/4444/multimedia?jwt=temporary-jwt")
    }

    @MainActor
    func testHistoryObjectIsMergedAndCompletesLoading() async {
        let transport = FakeTransport()
        let store = INDChatStore(
            configuration: INDChatConfiguration(baseURL: "https://chat.example.com", channelKey: "channel", contactCode: "contact"),
            transport: transport
        )
        store.open()
        transport.publish(.connected)
        await Task.yield()
        transport.publish(.authenticated(["applicationId": 4444]))
        await Task.yield()

        XCTAssertTrue(transport.emissions.isEmpty)

        transport.publish(.historyReceived([
            "contactId": 297,
            "nextMessageId": 119,
            "messages": [[
                "id": 120,
                "contentType": "text",
                "content": ["body": "Hola, ¿en qué puedo ayudarte?"],
                "sendType": "proactive",
                "createdAt": "2025-12-12T11:11:13.267Z"
            ]]
        ]))
        await Task.yield()

        XCTAssertFalse(store.state.isLoadingOlderMessages)
        XCTAssertEqual(store.state.applicationId, 4444)
        XCTAssertTrue(store.state.hasOlderMessages)
        XCTAssertEqual(store.state.messages.count, 1)
        XCTAssertEqual(store.state.messages.first?.direction, .business)
    }

    @MainActor
    func testEmptyAutomaticHistoryFinishesLoadingAndPreventsPagination() async {
        let transport = FakeTransport()
        let store = INDChatStore(
            configuration: INDChatConfiguration(baseURL: "https://chat.example.com", channelKey: "channel", contactCode: "contact"),
            transport: transport
        )
        store.open()
        transport.publish(.connected)
        await Task.yield()
        transport.publish(.authenticated(["applicationId": 4444]))
        await Task.yield()
        transport.publish(.historyReceived(["messages": []]))
        await Task.yield()

        XCTAssertFalse(store.state.isLoadingOlderMessages)
        XCTAssertFalse(store.state.hasOlderMessages)
        store.requestOlderMessages()
        XCTAssertTrue(transport.emissions.isEmpty)
    }

    @MainActor
    func testHistoryPaginationUsesNextMessageIdCursor() async {
        let transport = FakeTransport()
        let store = INDChatStore(
            configuration: INDChatConfiguration(baseURL: "https://chat.example.com", channelKey: "channel", contactCode: "contact"),
            transport: transport
        )
        store.open()
        transport.publish(.connected)
        await Task.yield()
        transport.publish(.authenticated(["applicationId": 4444]))
        await Task.yield()
        transport.publish(.historyReceived(["nextMessageId": 120, "messages": []]))
        await Task.yield()

        store.requestOlderMessages()
        XCTAssertEqual(transport.emissions.last?.event, "history:request")
        XCTAssertEqual(transport.emissions.last?.payload["fromMessageId"] as? Int, 120)
    }

    @MainActor
    func testAuthenticationErrorStopsLoadingAndSetsUnauthorizedState() async {
        let transport = FakeTransport()
        let store = INDChatStore(
            configuration: INDChatConfiguration(baseURL: "https://chat.example.com", channelKey: "channel", contactCode: "contact"),
            transport: transport
        )
        store.open()
        transport.publish(.connected)
        await Task.yield()
        transport.publish(.authenticateError([["code": "INVALID_CHANNEL_KEY", "message": "Invalid channelKey"]]))
        await Task.yield()

        XCTAssertEqual(store.state.connection, .unauthorized)
        XCTAssertFalse(store.state.isLoadingOlderMessages)
        XCTAssertEqual(store.state.error, .authentication("Invalid channelKey"))
    }

    @MainActor
    func testTerminalDisconnectShowsConnectionErrorAndStopsLoading() async {
        let transport = FakeTransport()
        let store = INDChatStore(
            configuration: INDChatConfiguration(baseURL: "https://chat.example.com", channelKey: "channel", contactCode: "contact"),
            transport: transport
        )
        store.open()
        transport.publish(.disconnected(reconnecting: false, message: "Reconnect Failed"))
        await Task.yield()

        XCTAssertEqual(store.state.connection, .disconnected)
        XCTAssertEqual(store.state.error, .connection("Reconnect Failed"))
        XCTAssertFalse(store.state.isLoadingOlderMessages)
        XCTAssertFalse(store.state.hasOlderMessages)
    }

    @MainActor
    func testReconnectingDoesNotShowTerminalConnectionError() async {
        let transport = FakeTransport()
        let store = INDChatStore(
            configuration: INDChatConfiguration(baseURL: "https://chat.example.com", channelKey: "channel", contactCode: "contact"),
            transport: transport
        )
        store.open()
        transport.publish(.disconnected(reconnecting: true, message: "Network unavailable"))
        await Task.yield()

        XCTAssertEqual(store.state.connection, .reconnecting)
        XCTAssertNil(store.state.error)
    }

    @MainActor
    func testManualCloseClearsConnectionError() async {
        let transport = FakeTransport()
        let store = INDChatStore(
            configuration: INDChatConfiguration(baseURL: "https://chat.example.com", channelKey: "channel", contactCode: "contact"),
            transport: transport
        )
        store.open()
        transport.publish(.disconnected(reconnecting: false, message: "Reconnect Failed"))
        await Task.yield()
        store.close()

        XCTAssertEqual(store.state.connection, .disconnected)
        XCTAssertNil(store.state.error)
    }

    @MainActor
    func testRealtimeArrayIsMergedWithoutCompletingHistoryRequest() async {
        let transport = FakeTransport()
        let store = INDChatStore(
            configuration: INDChatConfiguration(baseURL: "https://chat.example.com", channelKey: "channel", contactCode: "contact"),
            transport: transport
        )
        store.open()
        transport.publish(.connected)
        await Task.yield()
        transport.publish(.authenticated(["applicationId": 4444]))
        await Task.yield()

        transport.publish(.messageReceived([
            "chatMessage": [
                "id": 123,
                "contentType": "text",
                "content": ["body": "Hola"],
                "sendType": "reactive",
                "createdAt": "2026-07-10T10:00:00.000Z"
            ]
        ]))
        await Task.yield()

        XCTAssertTrue(store.state.isLoadingOlderMessages)
        XCTAssertEqual(store.state.messages.first?.body, "Hola")
        XCTAssertEqual(store.state.messages.first?.direction, .business)
        XCTAssertTrue(transport.emissions.isEmpty)
    }

    @MainActor
    func testSendRequiresAuthenticatedState() async throws {
        let transport = FakeTransport()
            let store = INDChatStore(
                configuration: INDChatConfiguration(baseURL: "https://chat.example.com", channelKey: "channel", contactCode: "contact"),
            transport: transport
        )
        XCTAssertFalse(store.sendText("Hola"))

        store.open()
        transport.publish(.connected)
        await Task.yield()
        transport.publish(.authenticated(["applicationId": 4444]))
        await Task.yield()
        XCTAssertTrue(store.sendText("  Hola  "))
        XCTAssertEqual(store.state.messages.last?.body, "Hola")
        XCTAssertEqual(store.state.messages.last?.status, .pending)
        XCTAssertEqual(transport.emissions.last?.event, "message:send")
    }

    @MainActor
    func testAckAndSendErrorUpdateByClientMessageId() async {
        let transport = FakeTransport()
        let store = INDChatStore(
            configuration: INDChatConfiguration(baseURL: "https://chat.example.com", channelKey: "channel", contactCode: "contact"),
            transport: transport
        )
        store.open()
        transport.publish(.connected)
        await Task.yield()
        transport.publish(.authenticated(["applicationId": 4444]))
        await Task.yield()
        XCTAssertTrue(store.sendText("Hola"))
        guard let messageID = store.state.messages.last?.id else {
            XCTFail("Debe existir mensaje local")
            return
        }

        transport.publish(.messageSent(["clientMessageId": messageID]))
        await Task.yield()
        XCTAssertEqual(store.state.messages.last?.status, .sent)

        transport.publish(.messageSendError(["clientMessageId": messageID, "message": "Failed to process message"]))
        await Task.yield()
        XCTAssertEqual(store.state.messages.last?.status, .error)
    }

    @MainActor
    func testMultimediaUploadPreparesThenSendsReturnedIdentifier() async {
        let transport = FakeTransport()
        let uploadStarted = expectation(description: "La subida REST comienza")
        let uploader = FakeMultimediaUploader(result: .success(123), onUpload: { uploadStarted.fulfill() })
        let store = INDChatStore(
            configuration: INDChatConfiguration(
                baseURL: "https://chat.example.com",
                channelKey: "channel",
                contactCode: "contact"
            ),
            transport: transport,
            multimediaUploader: uploader
        )
        store.open()
        transport.publish(.connected)
        await Task.yield()
        transport.publish(.authenticated(["applicationId": 4444]))
        await Task.yield()

        XCTAssertTrue(store.sendMultimedia(INDChatMultimediaUpload(
            data: Data("image".utf8),
            type: .image,
            filename: "image.png",
            mimeType: "image/png"
        )))
        XCTAssertTrue(store.state.isUploadingMultimedia)
        XCTAssertEqual(transport.emissions.last?.event, "multimedia:prepare")

        transport.publish(.multimediaPrepared(["jwt": "temporary-jwt", "expiresInSeconds": 600]))
        await fulfillment(of: [uploadStarted])
        await Task.yield()

        XCTAssertFalse(store.state.isUploadingMultimedia)
        XCTAssertEqual(uploader.request?.applicationID, 4444)
        XCTAssertEqual(uploader.request?.jwt, "temporary-jwt")
        XCTAssertEqual(transport.emissions.last?.event, "message:send")
        guard let localMessage = store.state.messages.last,
              case let .multimedia(localMultimedia) = localMessage.content else {
            XCTFail("Debe insertarse un mensaje multimedia optimista")
            return
        }
        XCTAssertEqual(localMessage.status, .pending)
        XCTAssertTrue(localMultimedia.url.isFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: localMultimedia.url.path))
        XCTAssertEqual(localMultimedia.multimediaID, 123)
        let multimedia = transport.emissions.last?.payload["messageContent"] as? [String: [String: Any]]
        XCTAssertEqual(multimedia?["multimedia"]?["multimediaId"] as? Int, 123)
        XCTAssertEqual(multimedia?["multimedia"]?["multimediaType"] as? String, "image")
        XCTAssertEqual(transport.emissions.last?.payload["clientMessageId"] as? String, localMessage.id)

        transport.publish(.messageSent(["clientMessageId": localMessage.id, "sentAt": "2026-09-09T09:47:01.569Z"]))
        await Task.yield()
        XCTAssertEqual(store.state.messages.last?.status, .sent)
    }

    @MainActor
    func testFailedOptimisticMultimediaRetriesWithoutUploadingAgainAndReconciles() async {
        let transport = FakeTransport()
        let uploadStarted = expectation(description: "La subida REST comienza")
        let uploader = FakeMultimediaUploader(result: .success(456), onUpload: { uploadStarted.fulfill() })
        let store = INDChatStore(
            configuration: INDChatConfiguration(baseURL: "https://dev.chat-v2.indigitall.com/webchat", channelKey: "channel", contactCode: "contact"),
            transport: transport,
            multimediaUploader: uploader
        )
        store.open()
        transport.publish(.connected)
        await Task.yield()
        transport.publish(.authenticated(["applicationId": 4444]))
        await Task.yield()
        XCTAssertTrue(store.sendMultimedia(INDChatMultimediaUpload(data: Data("PDF".utf8), type: .document, filename: "manual.pdf", mimeType: "application/pdf")))
        transport.publish(.multimediaPrepared(["jwt": "temporary-jwt"]))
        await fulfillment(of: [uploadStarted])
        await Task.yield()

        guard let localMessage = store.state.messages.last else {
            XCTFail("Debe existir el mensaje optimista")
            return
        }
        transport.publish(.messageSendError(["clientMessageId": localMessage.id, "message": "Rejected"]))
        await Task.yield()
        XCTAssertEqual(store.state.messages.last?.status, .error)

        store.retryMessage(id: localMessage.id)
        guard let retriedMultimedia = transport.emissions.last?.payload["messageContent"] as? [String: [String: Any]] else {
            XCTFail("El reintento debe contener multimedia")
            return
        }
        XCTAssertEqual(transport.emissions.last?.payload["clientMessageId"] as? String, localMessage.id)
        XCTAssertEqual(retriedMultimedia["multimedia"]?["multimediaId"] as? Int, 456)
        XCTAssertEqual(store.state.messages.last?.status, .pending)

        guard let localURL = localMultimediaURL(from: store.state.messages.last) else {
            XCTFail("El mensaje optimista debe conservar su archivo local")
            return
        }
        transport.publish(.messageReceived(["chatMessage": [
            "id": 999,
            "clientMessageId": localMessage.id,
            "contentType": "multimedia",
            "content": ["multimedia": [
                "multimediaType": "document",
                "multimediaId": 456,
                "multimediaUrl": "https://cdn.example.com/manual.pdf",
                "multimediaFilename": "manual.pdf"
            ]],
            "sendType": "incoming",
            "createdAt": "2026-09-09T09:47:02.000Z"
        ]]))
        await Task.yield()

        XCTAssertEqual(store.state.messages.count, 1)
        XCTAssertEqual(store.state.messages.first?.id, localMessage.id)
        XCTAssertEqual(store.state.messages.first?.serverId, "999")
        XCTAssertEqual(store.state.messages.first?.status, .sent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: localURL.path))
    }

    func testLocalMultimediaSourcesPreserveEveryType() throws {
        for type in INDChatMultimediaType.allCases {
            let multimedia = INDChatMultimedia(
                type: type,
                url: URL(fileURLWithPath: "/tmp/\(type.rawValue)"),
                filename: "file.\(type.rawValue)",
                mimeType: "application/octet-stream",
                multimediaID: 1
            )
            XCTAssertEqual(multimedia.type, type)
            XCTAssertTrue(multimedia.url.isFileURL)
            XCTAssertNotNil(multimedia.filename)
            XCTAssertNotNil(multimedia.mimeType)
            XCTAssertEqual(multimedia.multimediaID, 1)
        }
    }

    @MainActor
    func testInteractiveReplyPreservesOpaquePayloadAndQuote() async {
        let transport = FakeTransport()
        let store = INDChatStore(
            configuration: INDChatConfiguration(baseURL: "https://chat.example.com", channelKey: "channel", contactCode: "contact"),
            transport: transport
        )
        store.open()
        transport.publish(.connected)
        await Task.yield()
        transport.publish(.authenticated(["applicationId": 4444]))
        await Task.yield()

        let quote = INDChatMessageQuote(author: "Bot", content: "¿Continuar?")
        XCTAssertTrue(store.buttonClicked(payload: "opaque-value", text: "Sí", quote: quote))
        guard let sent = store.state.messages.last,
              let button = (transport.emissions.last?.payload["messageContent"] as? [String: [String: Any]])?["buttonClicked"] else {
            return XCTFail("Debe emitirse buttonClicked")
        }
        XCTAssertEqual(sent.status, .pending)
        XCTAssertEqual(sent.quote, quote)
        XCTAssertEqual(button["payload"] as? String, "opaque-value")
        XCTAssertEqual(button["text"] as? String, "Sí")
        XCTAssertEqual(transport.emissions.last?.payload["clientMessageId"] as? String, sent.id)

        transport.publish(.messageSendError(["clientMessageId": sent.id, "message": "Rejected"]))
        await Task.yield()
        store.retryMessage(id: sent.id)
        let retriedButton = (transport.emissions.last?.payload["messageContent"] as? [String: [String: Any]])?["buttonClicked"]
        XCTAssertEqual(store.state.messages.last?.status, .pending)
        XCTAssertEqual(retriedButton?["payload"] as? String, "opaque-value")
        XCTAssertEqual(retriedButton?["text"] as? String, "Sí")
    }

    @MainActor
    func testTagsAreNormalizedAssignedOnceAndPersistedOnlyAfterConfirmation() async {
        let transport = FakeTransport()
        let tags = FakeTagRepository()
        let store = INDChatStore(
            configuration: INDChatConfiguration(
                baseURL: "https://chat.example.com",
                channelKey: "channel",
                contactCode: "contact",
                assignTags: [" New ", "new", "Priority", "Ignored"],
                unassignTags: [" ignored "]
            ),
            transport: transport,
            multimediaUploader: FakeMultimediaUploader(result: .success(1)),
            tagRepository: tags
        )

        store.open()
        transport.publish(.connected)
        await Task.yield()
        transport.publish(.authenticated(["applicationId": 4444]))
        await Task.yield()

        XCTAssertEqual(transport.emissions.last?.event, "contact:tag:assign")
        XCTAssertEqual(transport.emissions.last?.payload["tags"] as? [String], ["New", "Priority"])
        XCTAssertTrue(tags.tags.isEmpty)

        transport.publish(.authenticated(["applicationId": 4444]))
        await Task.yield()
        XCTAssertEqual(transport.emissions.filter { $0.event == "contact:tag:assign" }.count, 1)

        transport.publish(.tagAssigned(["tags": ["New"]]))
        await Task.yield()
        XCTAssertEqual(tags.tags, ["New"])
        store.clearAllTags()
        XCTAssertTrue(tags.tags.isEmpty)
    }
}

private func localMultimediaURL(from message: INDChatMessage?) -> URL? {
    guard let message, case let .multimedia(multimedia) = message.content else { return nil }
    return multimedia.url
}

private final class FakeTransport: INDChatTransport, @unchecked Sendable {
    var onEvent: ((INDChatTransportEvent) -> Void)?
    var emissions: [(event: String, payload: [String: Any])] = []

    func connect(endpoint: INDChatEndpoint) {}
    func disconnect() {}
    func emit(event: String, payload: [String: Any]) { emissions.append((event, payload)) }
    func publish(_ event: INDChatTransportEvent) { onEvent?(event) }
}

private final class FakeMultimediaUploader: INDChatMultimediaUploading, @unchecked Sendable {
    struct Request {
        let applicationID: Int
        let jwt: String
    }

    let result: Result<Int, INDChatError>
    let onUpload: @Sendable () -> Void
    private(set) var request: Request?

    init(result: Result<Int, INDChatError>, onUpload: @escaping @Sendable () -> Void = {}) {
        self.result = result
        self.onUpload = onUpload
    }

    func upload(_ upload: INDChatMultimediaUpload, baseURL: String, applicationID: Int, jwt: String) async throws -> Int {
        request = Request(applicationID: applicationID, jwt: jwt)
        onUpload()
        return try result.get()
    }
}

private final class FakeTagRepository: INDChatTagPersisting, @unchecked Sendable {
    var tags: [String] = []

    func confirmedTags(for scope: INDChatTagScope) -> [String] { tags }
    func saveConfirmedTags(_ tags: [String], for scope: INDChatTagScope) { self.tags = tags }
    func clearConfirmedTags(for scope: INDChatTagScope) { tags = [] }
}

private final class MultimediaUploadURLProtocol: URLProtocol {
    static var request: URLRequest?
    static var response: (statusCode: Int, data: Data) = (500, Data())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.request = request
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.response.statusCode, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.response.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
