import Foundation

struct INDChatIncomingMessageBatch {
    let messages: [INDChatMessage]
    let isHistoryResponse: Bool
    let contactID: Int?
    let nextMessageID: Int?
}

enum INDChatMessageNormalizer {
    static func batch(from payload: Any) -> INDChatIncomingMessageBatch? {
        let dictionaries: [[String: Any]]
        let isHistoryResponse: Bool
        let contactID: Int?
        let nextMessageID: Int?
        if let values = payload as? [[String: Any]] {
            dictionaries = values
            isHistoryResponse = false
            contactID = nil
            nextMessageID = nil
        } else if let value = payload as? [String: Any], let values = value["messages"] as? [[String: Any]] {
            dictionaries = values
            isHistoryResponse = true
            contactID = (value["contactId"] as? NSNumber)?.intValue ?? value["contactId"] as? Int
            nextMessageID = (value["nextMessageId"] as? NSNumber)?.intValue ?? value["nextMessageId"] as? Int
        } else if let value = payload as? [String: Any], let chatMessage = value["chatMessage"] as? [String: Any] {
            dictionaries = [chatMessage]
            isHistoryResponse = false
            contactID = nil
            nextMessageID = nil
        } else {
            return nil
        }
        return INDChatIncomingMessageBatch(
            messages: dictionaries.compactMap(message(from:)),
            isHistoryResponse: isHistoryResponse,
            contactID: contactID,
            nextMessageID: nextMessageID
        )
    }

    static func messages(from payload: Any) -> [INDChatMessage] { batch(from: payload)?.messages ?? [] }

    static func message(from value: [String: Any]) -> INDChatMessage? {
        guard let serverID = string(value["id"]),
              let contentType = string(value["contentType"])?.lowercased(),
              let rawContent = value["content"],
              let sendType = string(value["sendType"])?.lowercased(),
              let date = date(from: value) else { return nil }

        let direction: INDChatDirection
        switch sendType {
        case "incoming": direction = .contact
        case "proactive", "reactive": direction = .business
        default: return nil
        }

        let content: INDChatMessageContent
        switch contentType {
        case "text", "text/plain":
            guard let body = text(from: rawContent)?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else { return nil }
            content = .text(body)
        case "multimedia":
            guard let multimedia = multimedia(from: rawContent) else { return nil }
            content = .multimedia(multimedia)
        case "template":
            guard let template = template(from: rawContent) else { return nil }
            content = .template(template)
        case "carousel":
            let templates = carousel(from: rawContent)
            guard !templates.isEmpty else { return nil }
            content = .carousel(templates)
        case "interactive":
            guard let interactive = interactive(from: rawContent) else { return nil }
            content = .interactive(interactive)
        case "contacts":
            let contacts = contacts(from: rawContent)
            guard !contacts.isEmpty else { return nil }
            content = .contacts(contacts)
        case "location":
            guard let location = location(from: rawContent) else { return nil }
            content = .location(location)
        default:
            return nil
        }

        return INDChatMessage(
            id: "server:\(serverID)",
            serverId: serverID,
            clientMessageId: string(value["clientMessageId"]),
            content: content,
            direction: direction,
            createdAt: date,
            status: .sent,
            quote: quote(from: value["quote"])
        )
    }

    private static func text(from content: Any) -> String? {
        if let text = content as? String { return text }
        if let content = content as? [String: Any] { return string(content["body"]) ?? string(content["text"]) }
        return nil
    }

    private static func multimedia(from content: Any) -> INDChatMultimedia? {
        guard let content = content as? [String: Any],
              let value = content["multimedia"] as? [String: Any] else { return nil }
        return multimedia(from: value)
    }

    private static func multimedia(from value: [String: Any]) -> INDChatMultimedia? {
        guard
              let type = string(value["multimediaType"]).flatMap(INDChatMultimediaType.init(rawValue:)),
              let urlText = string(value["multimediaUrl"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: urlText),
              url.scheme?.lowercased() == "https",
              url.host != nil else { return nil }

        let filename = string(value["multimediaFilename"])?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard type != .document || filename != nil else { return nil }
        let caption = string(value["caption"])?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let multimediaID = integer(value["multimediaId"])
        return INDChatMultimedia(type: type, url: url, filename: filename, caption: caption, multimediaID: multimediaID)
    }

    private static func template(from content: Any) -> INDChatTemplate? {
        guard let content = content as? [String: Any] else { return nil }
        let value = (content["template"] as? [String: Any]) ?? content
        let components = value["components"] as? [[String: Any]] ?? []
        let header = components.first(where: { string($0["type"])?.uppercased() == "HEADER" })
        let body = components.first(where: { string($0["type"])?.uppercased() == "BODY" })
        let footer = components.first(where: { string($0["type"])?.uppercased() == "FOOTER" })
        guard let bodyText = string(body?["text"] ?? value["body"])?.trimmingCharacters(in: .whitespacesAndNewlines), !bodyText.isEmpty else { return nil }
        let buttons = (components.first(where: { string($0["type"])?.uppercased() == "BUTTONS" })?["buttons"] as? [[String: Any]] ?? value["buttons"] as? [[String: Any]] ?? []).compactMap(interactiveOption)
        let headerMultimedia = header?["multimedia"] as? [String: Any]
        let templateMultimedia: INDChatMultimedia?
        if let headerMultimedia {
            templateMultimedia = multimedia(from: headerMultimedia)
        } else {
            templateMultimedia = nil
        }
        return INDChatTemplate(
            id: string(value["id"]) ?? UUID().uuidString,
            header: string(header?["text"])?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            body: bodyText,
            footer: string(footer?["text"])?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            multimedia: templateMultimedia,
            buttons: buttons
        )
    }

    private static func carousel(from content: Any) -> [INDChatTemplate] {
        if let values = content as? [[String: Any]] { return values.compactMap(template(from:)) }
        guard let value = content as? [String: Any] else { return [] }
        let cards = value["carousel"] as? [[String: Any]] ?? value["cards"] as? [[String: Any]] ?? value["templates"] as? [[String: Any]] ?? []
        return cards.compactMap(template(from:))
    }

    private static func interactive(from content: Any) -> INDChatInteractive? {
        guard let content = content as? [String: Any] else { return nil }
        let value = (content["interactive"] as? [String: Any]) ?? content
          guard let kind = string(value["type"] ?? value["interactiveType"]).flatMap(INDChatInteractiveKind.init(rawValue:)),
              let rawBody = value["body"],
              let body = text(from: rawBody)?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else { return nil }
          let action = value["action"] as? [String: Any] ?? [:]
          let directOptions = value["buttons"] as? [[String: Any]] ?? value["options"] as? [[String: Any]] ?? value["rows"] as? [[String: Any]] ?? action["buttons"] as? [[String: Any]] ?? action["options"] as? [[String: Any]] ?? []
          let sections = value["sections"] as? [[String: Any]] ?? action["sections"] as? [[String: Any]] ?? []
          let sectionOptions = sections.flatMap { section in
            section["rows"] as? [[String: Any]] ?? section["buttons"] as? [[String: Any]] ?? []
        }
        let options = (directOptions + sectionOptions).compactMap(interactiveOption)
        guard !options.isEmpty || kind != .button && kind != .list else { return nil }
        return INDChatInteractive(kind: kind, body: body, options: options)
    }

    private static func interactiveOption(_ value: [String: Any]) -> INDChatInteractiveOption? {
        let reply = value["reply"] as? [String: Any] ?? value["button"] as? [String: Any] ?? [:]
        guard let title = string(reply["title"] ?? reply["text"] ?? value["title"] ?? value["text"] ?? value["label"])?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        let url = string(reply["url"] ?? value["url"]).flatMap(URL.init(string:)).flatMap { $0.scheme?.lowercased() == "https" && $0.host != nil ? $0 : nil }
        let payload = string(reply["id"] ?? reply["payload"] ?? value["payload"] ?? value["id"])?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return INDChatInteractiveOption(
            id: payload ?? UUID().uuidString,
            title: title,
            payload: payload,
            url: url,
            phoneNumber: string(reply["phone"] ?? reply["phoneNumber"] ?? value["phone"] ?? value["phoneNumber"])?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    private static func contacts(from content: Any) -> [INDChatContact] {
        guard let content = content as? [String: Any] else { return [] }
        let values = content["contacts"] as? [[String: Any]] ?? []
        return values.compactMap { value in
            let nameValue = value["name"] as? [String: Any]
            guard let name = string(nameValue?["formattedName"] ?? nameValue?["firstName"] ?? value["name"] ?? value["formattedName"])?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
            let phones = strings(value["phones"], keys: ["phone", "number"])
            let emails = strings(value["emails"], keys: ["email", "address"])
            let addresses = strings(value["addresses"], keys: ["address", "formattedAddress"])
            let urls = strings(value["urls"] ?? value["links"], keys: ["url", "link"]).compactMap(URL.init(string:)).filter { $0.scheme?.lowercased() == "https" && $0.host != nil }
            guard !phones.isEmpty || !emails.isEmpty || !addresses.isEmpty || !urls.isEmpty else { return nil }
            return INDChatContact(name: name, phones: phones, emails: emails, addresses: addresses, urls: urls)
        }
    }

    private static func location(from content: Any) -> INDChatLocation? {
        guard let content = content as? [String: Any], let value = (content["location"] as? [String: Any]) ?? Optional(content),
              let latitude = double(value["latitude"]), let longitude = double(value["longitude"]),
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        return INDChatLocation(latitude: latitude, longitude: longitude, name: string(value["name"])?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty, address: string(value["address"])?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
    }

    private static func quote(from value: Any?) -> INDChatMessageQuote? {
        guard let value = value as? [String: Any] else { return nil }
        let rawContent = value["content"] ?? value["body"]
        guard let content = rawContent.flatMap(text(from:))?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else { return nil }
        let direction: INDChatDirection?
        switch string(value["sendType"] ?? value["direction"])?.lowercased() {
        case "incoming": direction = .contact
        case "proactive", "reactive", "outgoing": direction = .business
        default: direction = nil
        }
        return INDChatMessageQuote(
            author: string(value["author"] ?? value["name"])?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            content: content,
            referencedMessageID: string(value["messageId"] ?? value["id"]),
            direction: direction
        )
    }

    private static func strings(_ value: Any?, keys: [String]) -> [String] {
        let values = value as? [Any] ?? []
        return values.compactMap { item in
            if let text = string(item)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty { return text }
            guard let dictionary = item as? [String: Any] else { return nil }
            return keys.lazy.compactMap { string(dictionary[$0])?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }.first
        }
    }

    private static func date(from value: [String: Any]) -> Date? {
        for key in ["createdAt", "timespan", "timestamp"] {
            if let date = date(value[key]) { return date }
        }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        if let seconds = value as? TimeInterval { return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds) }
        if let number = value as? NSNumber { return date(number.doubleValue) }
        guard let text = value as? String else { return nil }
        if let timestamp = Double(text) { return date(timestamp) }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
