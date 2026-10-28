import AppKit
import Foundation

import AppKit
import CoreText
import SwiftUI

@_silgen_name("v2_init")
func v2_init(_ data: UnsafePointer<CChar>, _ bin: UnsafePointer<CChar>, _ rules: UnsafePointer<CChar>) -> Int32

@_silgen_name("v2_call")
func v2_call(_ method: UnsafePointer<CChar>, _ args: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

@_silgen_name("v2_free")
func v2_free(_ ptr: UnsafeMutablePointer<CChar>?)

func v2RPC(method: String, args: [String: Any] = [:]) -> [String: Any] {
    let data = (try? JSONSerialization.data(withJSONObject: args)) ?? Data("{}".utf8)
    let argsText = String(data: data, encoding: .utf8) ?? "{}"
    let raw: UnsafeMutablePointer<CChar>? = method.withCString { m in
        argsText.withCString { a in v2_call(m, a) }
    }
    guard let raw else {
        DevLog.error("rpc", "\(method): not ready")
        return ["ok": false, "error": "not ready"]
    }
    defer { v2_free(raw) }
    let text = String(cString: raw)
    let response = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? ["ok": false]
    if response["ok"] as? Bool == false {
        let err = response["error"] as? String ?? "unknown"
        DevLog.error("rpc", "\(method): \(err)")
    }
    return response
}
