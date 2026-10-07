import Foundation

enum GallaeLabs {
    static let visualDiffKey = "labs.visualDiff"
}

/// A validated viewer document, either generated from the current comparison or imported as a snapshot.
struct VisualDiffDocument: Equatable, Sendable {
    static let maximumBytes = 4 * 1024 * 1024

    struct Metadata: Decodable {
        struct Provenance: Decodable {
            struct Repository: Decodable { let owner: String; let name: String }
            struct Revision: Decodable { let sha: String; let ref: String? }
            let repo: Repository
            let base: Revision
            let head: Revision
        }
        let kind: String
        let title: String
        let lenses: [String]
        let provenance: Provenance
    }

    let json: String
    let title: String
    let lenses: [String]
    let sourceDescription: String
    let isGenerated: Bool

    init(data: Data, generatedSource: String? = nil) throws {
        guard data.count <= Self.maximumBytes else { throw ImportError.tooLarge }
        guard let json = String(data: data, encoding: .utf8) else { throw ImportError.invalid }
        let metadata: Metadata
        do { metadata = try JSONDecoder().decode(Metadata.self, from: data) }
        catch { throw ImportError.invalid }
        let lenses = metadata.lenses.filter { ["architecture", "data-flow"].contains($0) }
        guard metadata.kind == "graph", !metadata.title.isEmpty, !lenses.isEmpty else { throw ImportError.invalid }
        self.json = json
        title = metadata.title
        self.lenses = lenses
        let provenance = metadata.provenance
        sourceDescription = generatedSource ?? "\(provenance.repo.owner)/\(provenance.repo.name) · \(provenance.base.sha.prefix(8)) → \(provenance.head.sha.prefix(8))"
        isGenerated = generatedSource != nil
    }

    static func read(from url: URL) throws -> Self {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumBytes else { throw ImportError.tooLarge }
        return try Self(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    enum ImportError: LocalizedError {
        case tooLarge, invalid
        var errorDescription: String? {
            switch self {
            case .tooLarge: "Choose a PR Lens graph smaller than 4 MiB."
            case .invalid: "Choose a PR Lens graph JSON with an architecture or data-flow view. SVGs and render manifests cannot be imported."
            }
        }
    }
}
