import Foundation

protocol INDChatTagPersisting: Sendable {
    func confirmedTags(for scope: INDChatTagScope) -> [String]
    func saveConfirmedTags(_ tags: [String], for scope: INDChatTagScope)
    func clearConfirmedTags(for scope: INDChatTagScope)
}

struct INDChatTagScope: Sendable {
    let baseURL: String
    let channelKey: String
    let contactCode: String

    var storageKey: String {
        "com.indigitall.chat.confirmed-tags.\(stableIdentifier)"
    }

    private var stableIdentifier: String {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in "\(baseURL.lowercased())|\(channelKey)|\(contactCode.lowercased())".utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

final class INDChatTagRepository: INDChatTagPersisting, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func confirmedTags(for scope: INDChatTagScope) -> [String] {
        defaults.stringArray(forKey: scope.storageKey) ?? []
    }

    func saveConfirmedTags(_ tags: [String], for scope: INDChatTagScope) {
        defaults.set(tags, forKey: scope.storageKey)
    }

    func clearConfirmedTags(for scope: INDChatTagScope) {
        defaults.removeObject(forKey: scope.storageKey)
    }
}

func indChatNormalizedTags(_ tags: [String]) -> [String] {
    var seen = Set<String>()
    return tags.compactMap { tag in
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { return nil }
        return trimmed
    }
}
