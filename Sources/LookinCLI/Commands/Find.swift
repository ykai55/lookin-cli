import ArgumentParser
import Foundation
import LookinCore
import LookinTransport

struct Find: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "find",
        abstract: "Find views by substring match on class, label, or accessibilityIdentifier.",
    )

    @OptionGroup var output: OutputOptions

    @Argument(help: "Substring to search for.")
    var query: String

    enum ByField: String, ExpressibleByArgument, CaseIterable {
        case `class`, label, axId = "ax-id"
    }

    @Option(name: .long, help: "Field to match: class | label | ax-id (default: class).")
    var by: ByField = .class

    @Option(name: .long, help: "Max results to return.")
    var limit: Int = 50

    func run() throws {
        let session = try loadSession()
        let hierarchy = try runAsync { try await Tree.fetchHierarchy(session: session) }
        let roots = hierarchy.displayItems ?? []
        let all = flatItems(from: roots)
        let needle = query.lowercased()

        let matches = all.filter { item in
            let obj = item.viewObject ?? item.layerObject
            switch by {
            case .class:
                return (obj?.rawClassName() ?? "").lowercased().contains(needle)
            case .label:
                return (item.customDisplayTitle ?? "").lowercased().contains(needle)
            case .axId:
                return (obj?.specialTrace ?? "").lowercased().contains(needle)
            }
        }.prefix(limit)

        struct FindEnvelope: Encodable {
            let query: String
            let by: String
            let matchCount: Int
            let results: [PublicNode]
        }

        let envelope = FindEnvelope(
            query: query,
            by: by.rawValue,
            matchCount: matches.count,
            results: matches.map { PublicNode(from: $0, depth: 0) },
        )
        try emit(envelope, options: output)
        exitSuccess()
    }
}
