import Foundation

@main
enum SwiftTests {
    static func main() {
        var failed = 0
        failed += check("jsonInt nil", jsonInt(nil) == -1)
        failed += check("jsonInt int", jsonInt(8) == 8)
        failed += check("jsonInt nsnumber", jsonInt(NSNumber(value: 12)) == 12)
        failed += check("jsonUInt zero", jsonUInt(nil) == 0)
        failed += check("jsonUInt uint", jsonUInt(UInt64(9)) == 9)
        failed += check("formatBytes zero", formatBytes(0) == "0 B")
        failed += check("formatBps idle", formatBps(0) == "—")
        failed += check("formatBps bytes", formatBps(42) == "42 B/s")
        failed += check("formatBps kb", formatBps(2_000) == "2 KB/s")
        failed += check("formatSpeedRate megabit", formatSpeedRate(1_000_000, megabit: true) == "8.00 Mbps")
        failed += check("formatSpeedRate mega", formatSpeedRate(1_000_000, megabit: false) == "1.00 MB/s")
        failed += check("locale en home", LocaleStore.string("home", language: "en") == "Home")
        failed += check("locale en app", LocaleStore.string("app", language: "en") == "V2OPEN")
        failed += check("locale unknown key falls back to key", LocaleStore.string("definitelyMissingKey", language: "en") == "definitelyMissingKey")
        failed += check("locale options count", LocaleStore.options.count == 10)
        failed += check("locale options include fa", LocaleStore.options.contains(where: { $0.0 == "fa" }))
        failed += check("tunnel parse skips blanks", TunnelAppList.parse("Safari\n\n Chrome \nSafari") == ["Safari", "Chrome"])
        failed += check("tunnel serialize unique", TunnelAppList.serialize(["Safari", "safari", "Notes"]) == "Safari\nNotes")
        failed += check("tunnel canonicalize alias", TunnelAppList.canonicalize(["Chrome", "Safari"]) { $0 == "Chrome" ? "Google Chrome" : nil } == ["Google Chrome", "Safari"])
        failed += check("tunnel host ide includes process", TunnelAppList.hostIDE.contains(ProcessInfo.processInfo.processName))
        failed += check("locale appsChoose en", LocaleStore.string("appsChoose", language: "en") == "Choose apps")
        if failed > 0 {
            fputs("swift-tests: \(failed) failed\n", stderr)
            exit(1)
        }
        print("swift-tests: ok")
    }

    static func check(_ name: String, _ ok: Bool) -> Int {
        if ok {
            print("  pass  \(name)")
            return 0
        }
        print("  FAIL  \(name)")
        return 1
    }
}
