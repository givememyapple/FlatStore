import Foundation

enum ReportWriter {
    static func save(sessions: [Session], path: String) {
        var lines = [
            "+---------------------+---------------------+---------------------+",
            "| login               | time_in             | time_out            |",
            "+---------------------+---------------------+---------------------+"
        ]
        for s in sessions {
            lines.append(s.toLine())
        }
        lines.append("+---------------------+---------------------+---------------------+")

        do {
            try lines.joined(separator: "\n")
                .write(toFile: path, atomically: true, encoding: .utf8)
            print("Session report saved to \(path)")
        } catch {
            print("Failed to save report: \(error)")
        }
    }
}