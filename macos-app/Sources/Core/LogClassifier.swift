import CoreML
import CreateML
import Foundation
import NaturalLanguage
import TabularData

/// Own 6-label log classifier. Trains an MLTextClassifier on first launch
/// from embedded samples (not a third-party weight dump).
final class LogClassifier {
    static let shared = LogClassifier()
    static let labels = ["access", "dns", "error", "warning", "info", "debug"]

    private let queue = DispatchQueue(label: "v2open.log-classifier")
    private var nlModel: NLModel?
    private var ready = false

    func prepare() {
        queue.async { [weak self] in
            self?.trainIfNeeded()
        }
    }

    func classify(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "info" }
        if let label = queue.sync(execute: { nlModel?.predictedLabel(for: trimmed) }), Self.labels.contains(label) {
            return label
        }
        return heuristic(trimmed)
    }

    func classifyLines(_ text: String, limit: Int = 80) -> [(String, String)] {
        text.split(separator: "\n").prefix(limit).map { line in
            let raw = String(line)
            return (raw, classify(raw))
        }
    }

    private func trainIfNeeded() {
        if ready { return }
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/V2Open", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let compiled = dir.appendingPathComponent("LogClassifier.mlmodelc")
        if FileManager.default.fileExists(atPath: compiled.path),
           let model = try? NLModel(contentsOf: compiled) {
            nlModel = model
            ready = true
            return
        }
        do {
            let csv = dir.appendingPathComponent("log-train.csv")
            try csvBody.write(to: csv, atomically: true, encoding: .utf8)
            let dataFrame = try DataFrame(contentsOfCSVFile: csv)
            let classifier = try MLTextClassifier(trainingData: dataFrame, textColumn: "text", labelColumn: "label")
            let raw = dir.appendingPathComponent("LogClassifier.mlmodel")
            try classifier.write(to: raw)
            let built = try MLModel.compileModel(at: raw)
            try? FileManager.default.removeItem(at: compiled)
            try FileManager.default.copyItem(at: built, to: compiled)
            nlModel = try NLModel(contentsOf: compiled)
            ready = true
        } catch {
            ready = true
        }
    }

    private func heuristic(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("dns") || lower.contains("doh") || lower.contains("dot") || lower.contains("query") && lower.contains("a ") {
            return "dns"
        }
        if lower.contains("inbound") || lower.contains("accepted") || lower.contains("from ") && (lower.contains("tcp") || lower.contains("udp")) {
            return "access"
        }
        if lower.contains("error") || lower.contains("fatal") || lower.contains("failed") || lower.contains("panic") {
            return "error"
        }
        if lower.contains("warn") || lower.contains("deprecated") {
            return "warning"
        }
        if lower.contains("debug") || lower.contains("trace") {
            return "debug"
        }
        return "info"
    }

    private var csvBody: String {
        var rows = ["text,label"]
        for (text, label) in samples {
            let escaped = "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            rows.append("\(escaped),\(label)")
        }
        return rows.joined(separator: "\n")
    }

    private var samples: [(String, String)] {
        [
            ("accepted tcp:127.0.0.1:51234 -> proxy", "access"),
            ("inbound/socks accepted connection from 192.168.1.20", "access"),
            ("[Info] [3184] proxy/socks: inbound connection from 10.0.0.8:44321", "access"),
            ("access log tcp 172.19.0.1:1080 -> 1.1.1.1:443", "access"),
            ("from 192.168.0.14:52301 accepted udp session", "access"),
            ("inbound connection established tag=socks", "access"),
            ("new request from 127.0.0.1:59120 network=tcp", "access"),
            ("accepted http CONNECT example.com:443", "access"),
            ("dns: query A google.com from 127.0.0.1", "dns"),
            ("dns query AAAA cloudflare.com -> 1.1.1.1", "dns"),
            ("DOH request https://1.1.1.1/dns-query status=200", "dns"),
            ("fake dns allocated 198.18.0.24 for api.telegram.org", "dns"),
            ("nameserver[1] 8.8.8.8 returned NOERROR", "dns"),
            ("dot lookup failed for geosite:cn", "dns"),
            ("dns cache hit for youtube.com", "dns"),
            ("resolved example.org to 93.184.216.34", "dns"),
            ("error: failed to handshake with server", "error"),
            ("fatal: core exited with status 1", "error"),
            ("connection failed: i/o timeout", "error"),
            ("panic: invalid configuration", "error"),
            ("rejected: authentication error", "error"),
            ("tls handshake error unexpected eof", "error"),
            ("dial tcp: connection refused", "error"),
            ("failed to listen on 10808", "error"),
            ("warning: insecure skip verify is on", "warning"),
            ("deprecated option mux.concurrency", "warning"),
            ("warn: route rule ignored empty domain", "warning"),
            ("certificate is about to expire", "warning"),
            ("using allowInsecure, MITM possible", "warning"),
            ("slowdown: too many pending connections", "warning"),
            ("fallback server used because primary timed out", "warning"),
            ("rule match skipped empty geosite", "warning"),
            ("info: started socks inbound on 10808", "info"),
            ("core started with 2 outbounds", "info"),
            ("routing: matched geosite:google -> proxy", "info"),
            ("using tun inbound xray0 mtu=1500", "info"),
            ("geoip.dat loaded 1234 records", "info"),
            ("observatory ping 42ms", "info"),
            ("config reloaded successfully", "info"),
            ("listening http 127.0.0.1:10807", "info"),
            ("debug dump outbound vless uuid=...", "debug"),
            ("trace packet 52 bytes from utun", "debug"),
            ("debug sniff domain=www.google.com", "debug"),
            ("verbose: balancer pick proxy-2", "debug"),
            ("debug websocket frame len=128", "debug"),
            ("trace dns iterator next", "debug"),
            ("debug mux session opened", "debug"),
            ("debug xhttp stream id=9", "debug")
        ]
    }
}
