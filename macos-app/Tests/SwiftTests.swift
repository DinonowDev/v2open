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
        failed += check("version newer patch", AppVersion.parse("1.2.0").isNewer(than: AppVersion.parse("1.1.9")))
        failed += check("version not newer same", !AppVersion.parse("1.2.0", build: 3).isNewer(than: AppVersion.parse("1.2.0", build: 3)))
        failed += check("version newer build", AppVersion.parse("1.2.0", build: 4).isNewer(than: AppVersion.parse("1.2.0", build: 3)))
        failed += check("asset build", v2openAssetBuild("V2Open-1.2.0-build12-macos-arm64.zip") == 12)
        failed += check(
            "pick arm64 asset",
            v2openPickReleaseAsset(
                names: ["V2Open-1.2.0-build3-macos-x86_64.zip", "V2Open-1.2.0-build3-macos-arm64.zip", "notes.txt"],
                arch: "arm64"
            ) == "V2Open-1.2.0-build3-macos-arm64.zip"
        )
        failed += check(
            "pick higher intel build",
            v2openPickReleaseAsset(
                names: ["V2Open-1.2.0-build2-macos-x86_64.zip", "V2Open-1.2.0-build9-macos-x86_64.zip"],
                arch: "x86_64"
            ) == "V2Open-1.2.0-build9-macos-x86_64.zip"
        )
        failed += check("locale appsChoose en", LocaleStore.string("appsChoose", language: "en") == "Choose apps")

        if let hiddify = URL(string: "hiddify://import/https://example.com/sub#MyName") {
            let t = ImportURL.linkText(from: hiddify)
            failed += check("import url hiddify https", t == "hiddify://import/https://example.com/sub#MyName")
        }
        if let hiddifyVless = URL(string: "hiddify://import/vless://uuid@host:443#n") {
            let t = ImportURL.linkText(from: hiddifyVless)
            failed += check("import url hiddify vless", t.hasPrefix("hiddify://import/vless://"))
        }
        if let sub = URL(string: "sub://https://example.com/a") {
            failed += check("import url sub", ImportURL.linkText(from: sub).hasPrefix("sub://https://"))
        }
        if let clash = URL(string: "clash://install-config?url=https://example.com/sub") {
            failed += check("import url clash", ImportURL.linkText(from: clash).hasPrefix("clash://"))
        }

        let enc = RouteMatcherKind.domainSuffix.encode("google.com")
        failed += check("matcher suffix encode", enc.domains == ["suffix:google.com"])
        let rows = RouteMatcherKind.rows(
            domains: ["suffix:test.com", "geosite:cn"],
            ips: ["geoip:ir"],
            port: "443",
            network: "tcp",
            protocolName: ""
        )
        failed += check("matcher rows count", rows.count == 5)
        let flat = RouteMatcherKind.flatten([
            MatcherRow(kind: .geosite, value: "google"),
            MatcherRow(kind: .geoip, value: "ir")
        ])
        failed += check("matcher flatten geosite", flat.domains.contains("geosite:google"))
        failed += check("matcher flatten geoip", flat.ips.contains("geoip:ir"))
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
