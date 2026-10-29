import AppKit
import SwiftUI
import WebKit

struct SpeedTestGoGauge: View {
    @EnvironmentObject var model: Model
    var mbps: Double
    var idle: Bool
    var showGoButton: Bool
    var phase: SpeedGaugePhase
    var running: Bool
    var tested: Bool
    var themeLight: Bool
    var progressTick: Int
    var unit: String
    var caption: String = ""
    var onGo: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                SpeedometerChart(
                    mbps: mbps,
                    idle: idle,
                    running: running,
                    phase: phase,
                    themeLight: themeLight,
                    progressTick: progressTick,
                    unit: unit
                )
                .opacity(idle ? 0 : 1)
                .allowsHitTesting(!idle && tested && !running)

                SpeedGoButton(title: model.t("speedGo"), action: onGo)
                    .compositingGroup()
                    .opacity(showGoButton ? 1 : 0)
                    .scaleEffect(showGoButton ? 1 : 1.22, anchor: .center)
                    .allowsHitTesting(showGoButton)

                if tested && !running && !idle {
                    Button(action: onGo) {
                        Color.clear
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)

            Group {
                if tested && !running {
                    Button(action: onGo) {
                        Mix(
                            text: caption,
                            size: 13,
                            weight: .semibold,
                            color: C.cyan
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Mix(
                        text: captionText,
                        size: 13,
                        weight: .semibold,
                        color: running && !idle
                            ? (phase == .upload ? C.speedUp : C.speedDown)
                            : C.muted
                    )
                }
            }
            .opacity(showGoButton || running || tested ? 1 : 0)
            .frame(height: 18)
        }
        .frame(height: 260)
        .frame(maxWidth: .infinity)
        .animation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.46), value: idle)
        .animation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.46), value: showGoButton)
    }

    private var captionText: String {
        if !caption.isEmpty { return caption }
        if showGoButton { return tested ? model.t("speedRetry") : model.t("runSpeed") }
        return model.t("testing")
    }
}

private struct SpeedGoButton: View {
    var title: String
    var action: () -> Void

    private var ring: AngularGradient {
        AngularGradient(
            colors: [
                C.cyan,
                C.accent,
                C.accentDeep,
                C.accent,
                C.cyan
            ],
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(270)
        )
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(C.cyan.opacity(0.18))
                    .frame(width: 172, height: 172)
                    .blur(radius: 18)
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [C.hairline, C.line],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .frame(width: 156, height: 156)
                Circle()
                    .stroke(ring, lineWidth: 4)
                    .frame(width: 146, height: 146)
                    .shadow(color: C.cyan.opacity(0.35), radius: 10)
                Circle()
                    .stroke(C.cyan.opacity(0.28), lineWidth: 2)
                    .frame(width: 126, height: 126)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [C.powerOffTop, C.powerOffBottom],
                            center: .center,
                            startRadius: 6,
                            endRadius: 58
                        )
                    )
                    .frame(width: 112, height: 112)
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [C.overlay.opacity(0.14), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    )
                    .overlay(
                        Circle().stroke(C.overlay.opacity(0.12), lineWidth: 1)
                    )
                Mix(text: title, size: 26, weight: .bold)
            }
            .contentShape(Circle())
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel(title)
    }
}

private struct SpeedometerChart: NSViewRepresentable {
    var mbps: Double
    var idle: Bool
    var running: Bool
    var phase: SpeedGaugePhase
    var themeLight: Bool
    var progressTick: Int
    var unit: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "gaugeReady")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.setValue(false, forKey: "drawsBackground")
        web.underPageBackgroundColor = .clear
        web.allowsMagnification = false
        web.allowsBackForwardNavigationGestures = false
        context.coordinator.web = web
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "speedometer") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        let _ = progressTick
        context.coordinator.push(
            mbps: mbps,
            idle: idle,
            running: running,
            phase: phase,
            themeLight: themeLight,
            unit: unit
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var web: WKWebView?
        private var ready = false
        private var pending: String?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "gaugeReady" else { return }
            markReady()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            markReady()
        }

        private func markReady() {
            guard !ready else { return }
            ready = true
            if let pending, let web {
                web.evaluateJavaScript(pending, completionHandler: nil)
                self.pending = nil
            }
        }

        func push(
            mbps: Double,
            idle: Bool,
            running: Bool,
            phase: SpeedGaugePhase,
            themeLight: Bool,
            unit: String
        ) {
            let phaseName: String
            switch phase {
            case .upload: phaseName = "upload"
            case .finished: phaseName = "finished"
            default: phaseName = "download"
            }
            let json: [String: Any] = [
                "mbps": mbps,
                "idle": idle,
                "running": running,
                "phase": phaseName,
                "light": themeLight,
                "unit": unit,
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: json),
                  let body = String(data: data, encoding: .utf8) else { return }
            let js = "window.gaugeSet && window.gaugeSet(\(body))"
            if ready, let web {
                web.evaluateJavaScript(js, completionHandler: nil)
            } else {
                pending = js
            }
        }
    }
}
