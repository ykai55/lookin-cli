import ArgumentParser

struct Lookin: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lookin",
        abstract: "Query a running iOS app's view hierarchy via LookinServer.",
        version: "0.1.0",
        subcommands: [Attach.self, Tree.self, Attributes.self, Find.self,
                       Screenshot.self, Doctor.self, Measure.self, Invoke.self],
    )
}

Lookin.main()
