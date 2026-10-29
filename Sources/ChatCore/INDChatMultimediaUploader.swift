import Foundation

protocol INDChatMultimediaUploading: Sendable {
    func upload(
        _ upload: INDChatMultimediaUpload,
        baseURL: String,
        applicationID: Int,
        jwt: String
    ) async throws -> Int
}

struct INDChatMultimediaUploader: INDChatMultimediaUploading {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func upload(
        _ upload: INDChatMultimediaUpload,
        baseURL: String,
        applicationID: Int,
        jwt: String
    ) async throws -> Int {
        var components = try uploadURLComponents(from: baseURL, applicationID: applicationID)
        components.queryItems = [URLQueryItem(name: "jwt", value: jwt)]
        guard let url = components.url else {
            throw INDChatError.invalidConfiguration("The multimedia upload URL could not be created")
        }

        let boundary = "INDChat-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(upload, boundary: boundary)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw INDChatError.server("Invalid multimedia response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw INDChatError.server(serverMessage(from: data) ?? "The multimedia file could not be uploaded")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseData = object["data"] as? [String: Any],
              let identifier = responseData["id"] as? NSNumber else {
            throw INDChatError.server("The multimedia response does not include an identifier")
        }
        return identifier.intValue
    }

    private func uploadURLComponents(from baseURL: String, applicationID: Int) throws -> URLComponents {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let chatURL = URLComponents(string: trimmedBaseURL),
              chatURL.scheme?.lowercased() == "https",
              let host = chatURL.host?.lowercased() else {
            throw INDChatError.invalidConfiguration("baseURL must be a valid HTTPS URL")
        }

        let suffix = ".chat-v2.indigitall.com"
        let environment: String
        if host == "chat-v2.indigitall.com" {
            environment = ""
        } else if host.hasSuffix(suffix) {
            environment = String(host.dropLast(suffix.count)) + "."
        } else {
            throw INDChatError.invalidConfiguration("baseURL must use the chat-v2.indigitall.com domain")
        }

        guard let components = URLComponents(string: "https://\(environment)api.indigitall.com/v2/chat/\(applicationID)/multimedia") else {
            throw INDChatError.invalidConfiguration("The multimedia upload URL could not be created")
        }
        return components
    }

    func multipartBody(_ upload: INDChatMultimediaUpload, boundary: String) -> Data {
        var body = Data()
        let lineBreak = "\r\n"
        func append(_ value: String) { body.append(value.data(using: .utf8)!) }
        func appendField(_ name: String, _ value: String) {
            append("--\(boundary)\(lineBreak)")
            append("Content-Disposition: form-data; name=\"\(name)\"\(lineBreak)\(lineBreak)")
            append("\(value)\(lineBreak)")
        }

        appendField("type", upload.type.rawValue)
        appendField("title", upload.filename)
        append("--\(boundary)\(lineBreak)")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(upload.filename)\"\(lineBreak)")
        append("Content-Type: \(upload.mimeType)\(lineBreak)\(lineBreak)")
        body.append(upload.data)
        append(lineBreak)
        append("--\(boundary)--\(lineBreak)")
        return body
    }

    private func serverMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["message"] as? String
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}