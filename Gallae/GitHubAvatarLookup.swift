import Foundation

// commit 이메일로 GitHub 공개 계정을 조회한다. 이메일은 GitHub API에만 전송되고,
// 성공 결과는 이메일별로 저장해 반복 조회하지 않는다. 실패는 세션 안에서만 기억한다.
@MainActor
final class GitHubAvatarLookup {
    static let shared = GitHubAvatarLookup()
    private static let cacheKey = "gitHubAvatarURLsByEmail"

    private var cache: [String: URL]
    private var unresolvedEmails: Set<String> = []
    private var pendingLookups: [String: Task<URL?, Never>] = [:]
    private let defaults: UserDefaults
    private let lookup: @Sendable (String) async -> URL?

    init(
        defaults: UserDefaults = .standard,
        lookup: @escaping @Sendable (String) async -> URL? = GitHubAvatarLookup.fetchAvatar
    ) {
        self.defaults = defaults
        self.lookup = lookup
        let stored = defaults.dictionary(forKey: Self.cacheKey) as? [String: String]
        cache = stored?.compactMapValues(URL.init(string:)) ?? [:]
    }

    func avatarURL(for email: String) async -> URL? {
        let key = email.lowercased()
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached }
        guard !unresolvedEmails.contains(key) else { return nil }
        if let pending = pendingLookups[key] { return await pending.value }

        // Badges share the lookup; one disappearing badge must not cancel it for the others.
        let pending = Task { await lookup(key) }
        pendingLookups[key] = pending
        defer { pendingLookups[key] = nil }
        guard let avatarURL = await pending.value else {
            unresolvedEmails.insert(key)
            return nil
        }
        cache[key] = avatarURL
        defaults.set(cache.mapValues(\.absoluteString), forKey: Self.cacheKey)
        return avatarURL
    }

    private nonisolated static func fetchAvatar(for key: String) async -> URL? {
        guard var components = URLComponents(string: "https://api.github.com/search/users") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: "\(key) in:email"),
            URLQueryItem(name: "per_page", value: "1")
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return Self.avatarURL(fromSearchResponse: data)
        } catch {
            return nil
        }
    }

    nonisolated static func avatarURL(fromSearchResponse data: Data) -> URL? {
        struct SearchResponse: Decodable {
            struct Item: Decodable {
                let avatarURL: String

                enum CodingKeys: String, CodingKey {
                    case avatarURL = "avatar_url"
                }
            }

            let items: [Item]
        }

        guard
            let response = try? JSONDecoder().decode(SearchResponse.self, from: data),
            let item = response.items.first,
            let url = URL(string: item.avatarURL + "&s=64")
        else {
            return nil
        }
        return url
    }
}
