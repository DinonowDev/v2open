import Foundation
import AppKit
import SwiftUI

enum ConfigAddStep {
    case none, menu, clash, scan
}

func jsonInt(_ value: Any?) -> Int {
    if let value = value as? Int { return value }
    if let value = value as? NSNumber { return value.intValue }
    return -1
}

func jsonUInt(_ value: Any?) -> UInt64 {
    if let value = value as? UInt64 { return value }
    if let value = value as? Int, value >= 0 { return UInt64(value) }
    if let value = value as? NSNumber { return value.uint64Value }
    return 0
}

func formatBytes(_ bytes: UInt64) -> String {
    if bytes == 0 { return "0 B" }
    return ByteCountFormatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))), countStyle: .binary)
}

func formatBps(_ bps: Int) -> String {
    if bps <= 0 { return "—" }
    if bps >= 1_000_000 { return String(format: "%.1f MB/s", Double(bps) / 1_000_000) }
    if bps >= 1_000 { return String(format: "%.0f KB/s", Double(bps) / 1_000) }
    return "\(bps) B/s"
}

func formatSpeedRate(_ bps: Int, megabit: Bool) -> String {
    if bps <= 0 { return "—" }
    if megabit {
        return String(format: "%.2f Mbps", Double(bps) * 8 / 1_000_000)
    }
    return String(format: "%.2f MB/s", Double(bps) / 1_000_000)
}

struct AppVersion: Equatable {
    var major: Int
    var minor: Int
    var patch: Int
    var build: Int

    static func parse(_ version: String, build: Int = 0) -> AppVersion {
        let parts = version.split(separator: ".").map { part -> Int in
            let digits = part.prefix { $0.isNumber }
            return Int(digits) ?? 0
        }
        return AppVersion(
            major: parts.count > 0 ? parts[0] : 0,
            minor: parts.count > 1 ? parts[1] : 0,
            patch: parts.count > 2 ? parts[2] : 0,
            build: build
        )
    }

    func isNewer(than other: AppVersion) -> Bool {
        if major != other.major { return major > other.major }
        if minor != other.minor { return minor > other.minor }
        if patch != other.patch { return patch > other.patch }
        return build > other.build
    }

    var display: String {
        if build > 0 { return "\(major).\(minor).\(patch) (\(build))" }
        return "\(major).\(minor).\(patch)"
    }
}

func v2openAssetBuild(_ name: String) -> Int {
    guard let range = name.range(of: #"build(\d+)"#, options: .regularExpression) else { return 0 }
    let digits = name[range].filter(\.isNumber)
    return Int(digits) ?? 0
}

func v2openPickReleaseAsset(names: [String], arch: String) -> String? {
    let needle = "macos-\(arch)"
    return names
        .filter { $0.contains(needle) && $0.hasSuffix(".zip") }
        .max { v2openAssetBuild($0) < v2openAssetBuild($1) }
}

func v2openMacArch() -> String {
    #if arch(arm64)
    return "arm64"
    #elseif arch(x86_64)
    return "x86_64"
    #else
    return "arm64"
    #endif
}
