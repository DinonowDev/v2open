import Foundation

enum ImportURL {
    /// Normalizes deep links before sending them to `v2core` import (Hiddify / sub schemes).
    static func linkText(from url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "hiddify" {
            if url.host == "import" {
                var payload = url.path
                if payload.hasPrefix("/") {
                    payload = String(payload.dropFirst())
                }
                if payload.isEmpty {
                    payload = url.pathComponents.filter { $0 != "/" }.dropFirst().joined(separator: "/")
                }
                var link = "hiddify://import/\(payload)"
                if let frag = url.fragment, !frag.isEmpty {
                    link += "#\(frag)"
                }
                return link
            }
        }
        if scheme == "sub" {
            var link = url.absoluteString
            if link.hasPrefix("sub:/") && !link.hasPrefix("sub://") {
                link = "sub://" + link.dropFirst("sub:/".count)
            }
            return link
        }
        return url.absoluteString
    }
}
