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
