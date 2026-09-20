import Darwin
import Foundation

do {
    try CLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    fputs("kvinta: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
