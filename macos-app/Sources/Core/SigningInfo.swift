import Foundation

struct SigningInfo: Equatable {
    var kind: String
    var authority: String
    var teamID: String
    var spctlAccepted: Bool
    var staplerValid: Bool

    static func current(appURL: URL = Bundle.main.bundleURL) -> SigningInfo {
        let path = appURL.path
        let codesign = shell("codesign -dv --verbose=4 \"\(path)\" 2>&1") ?? ""
        var authority = ""
        var team = ""
        for line in codesign.split(separator: "\n") {
            let text = String(line)
            if text.hasPrefix("Authority=") {
                authority = String(text.dropFirst("Authority=".count))
            }
            if text.hasPrefix("TeamIdentifier=") {
                team = String(text.dropFirst("TeamIdentifier=".count))
            }
        }
        let spctl = shell("spctl --assess --type execute \"\(path)\" 2>&1") != nil
        let stapler = shell("xcrun stapler validate \"\(path)\" 2>&1") != nil

        let kind: String
        if authority.contains("Developer ID Application"), stapler, spctl {
            kind = "notarized"
        } else if authority.contains("Developer ID Application") {
            kind = "developer-id"
        } else if authority == "-" || authority.isEmpty || team == "not set" {
            kind = "adhoc"
        } else if authority.contains("Apple Development") || authority.contains("Mac Developer") {
            kind = "development"
        } else {
            kind = "signed"
        }

        return SigningInfo(
            kind: kind,
            authority: authority.isEmpty ? "—" : authority,
            teamID: team.isEmpty ? "—" : team,
            spctlAccepted: spctl,
            staplerValid: stapler
        )
    }

    private static func shell(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
