import AppKit
import SwiftUI

@MainActor
enum RelativeTimeLabel {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func string(for date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: .now)
    }
}

enum AuthorAvatarSource {
    // GitHub noreply 이메일에 든 공개 ID·사용자명만 사용한다.
    // 이메일 자체는 어떤 네트워크 요청에도 실리지 않는다.
    static func url(for email: String) -> URL? {
        let email = email.lowercased()
        let suffix = "@users.noreply.github.com"
        guard email.hasSuffix(suffix) else { return nil }
        let local = email.dropLast(suffix.count)

        if let plusIndex = local.firstIndex(of: "+") {
            let id = local[..<plusIndex]
            guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
            return URL(string: "https://avatars.githubusercontent.com/u/\(id)?s=64&v=4")
        }

        guard
            !local.isEmpty,
            local.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
        else {
            return nil
        }
        return URL(string: "https://github.com/\(local).png?size=64")
    }
}

enum AuthorIdentity {
    static func initials(for name: String) -> String {
        let letters = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
        let joined = letters.joined().uppercased()
        return joined.isEmpty ? "?" : joined
    }

    // 실행마다 바뀌는 hashValue 대신 안정적인 해시로 같은 작성자에게 항상 같은 색을 준다.
    static func colorIndex(for identity: String, paletteCount: Int) -> Int {
        guard paletteCount > 0 else { return 0 }
        var hash: UInt64 = 5381
        for scalar in identity.lowercased().unicodeScalars {
            hash = (hash << 5) &+ hash &+ UInt64(scalar.value)
        }
        return Int(hash % UInt64(paletteCount))
    }
}

struct RepositoryAuthorBadge: View {
    let name: String
    let email: String
    @AppStorage("loadsGitHubAvatars") private var loadsGitHubAvatars = true
    @State private var resolvedAvatarURL: URL?
    @Environment(\.gallaeTheme) private var theme

    var body: some View {
        Group {
            if let resolvedAvatarURL {
                AsyncImage(url: resolvedAvatarURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 28, height: 28)
                            .clipShape(.circle)
                    } else {
                        initialsBadge
                    }
                }
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            } else {
                initialsBadge
            }
        }
        .task(id: "\(loadsGitHubAvatars)|\(email)") {
            guard loadsGitHubAvatars else {
                resolvedAvatarURL = nil
                return
            }
            if let directURL = AuthorAvatarSource.url(for: email) {
                resolvedAvatarURL = directURL
                return
            }
            resolvedAvatarURL = nil
            let lookedUp = await GitHubAvatarLookup.shared.avatarURL(for: email)
            guard !Task.isCancelled else { return }
            resolvedAvatarURL = lookedUp
        }
    }

    private var initialsBadge: some View {
        let palette = theme.colors.authorBadgeColors
        let color = palette[AuthorIdentity.colorIndex(
            for: email.isEmpty ? name : email,
            paletteCount: palette.count
        )]
        return Text(AuthorIdentity.initials(for: name))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color.gradient, in: .circle)
            .accessibilityHidden(true)
    }
}
