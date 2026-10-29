import SwiftUI
import Combine

struct SelectedConfigCard: View {
    @EnvironmentObject var model: Model
    var profile: [String: Any]
    var showPower = false

    var body: some View {
        let runtime = model.runtime
        let connected = runtime["connected"] as? Bool ?? false
        let connecting = (runtime["phase"] as? String ?? "idle") == "connecting"
        let name = profile["remark"] as? String ?? runtime["profile_name"] as? String ?? model.t("none")
        let ping = jsonInt(profile["ping"])
        let down = jsonInt(runtime["download_speed"])
        let up = jsonInt(runtime["upload_speed"])
        let proto = ((profile["protocol"] as? String) ?? "").uppercased()
        let address = profile["address"] as? String ?? ""
        let port = jsonInt(profile["port"])
        let endpoint = port > 0 ? "\(address):\(port)" : address

        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Mix(text: name, size: 13, weight: .semibold)
                        .lineLimit(1)
                    if connected {
                        Circle()
                            .fill(C.lime)
                            .frame(width: 6, height: 6)
                            .shadow(color: C.lime.opacity(0.6), radius: 3)
                    }
                }
                if !proto.isEmpty {
                    Mix(text: proto, size: 11, weight: .medium, color: C.muted)
                        .lineLimit(1)
                }
                if !endpoint.isEmpty {
                    Mix(text: endpoint, size: 11, color: C.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: ping == 0 ? "wifi.slash" : "dot.radiowaves.left.and.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PingMark.color(ping))
                    Mix(text: PingMark.label(ping, timeout: model.t("pingTimeout")), size: 11, weight: .bold, color: PingMark.color(ping))
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(C.lime.opacity(0.9))
                    Text(formatBps(down))
                        .font(.custom("Inter", size: 11).weight(.semibold))
                        .foregroundStyle(C.muted)
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(C.lime.opacity(0.9))
                    Text(formatBps(up))
                        .font(.custom("Inter", size: 11).weight(.semibold))
                        .foregroundStyle(C.muted)
                }
            }

            if showPower {
                PowerConnectButton(
                    connected: connected,
                    connecting: connecting,
                    dock: true,
                    action: {
                        if connected { model.disconnectTunnel() }
                        else { model.connectTunnel() }
                    }
                )
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(C.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(C.light ? 0.08 : 0.22), radius: 14, y: 5)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard connected else { return }
            let response = model.call("tick")
            if let data = response["data"] as? [String: Any] { model.state = data }
        }
    }
}

struct ConfigConnectDock: View {
    @EnvironmentObject var model: Model

    var body: some View {
        if let profile = model.activeConnectionProfile() {
            SelectedConfigCard(profile: profile, showPower: true)
        }
    }
}
