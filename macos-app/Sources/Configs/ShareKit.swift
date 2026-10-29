import AppKit
import CoreImage
import SwiftUI
import UniformTypeIdentifiers

enum ShareKit {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func qrImage(from text: String, scale: CGFloat = 8) -> NSImage? {
        let data = text.data(using: .utf8) ?? Data()
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    static func copyQR(_ text: String) {
        guard let image = qrImage(from: text) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    static func clashYAML(_ profile: [String: Any]) -> String {
        let name = profile["remark"] as? String ?? "proxy"
        let proto = (profile["protocol"] as? String ?? "").lowercased()
        let server = profile["address"] as? String ?? ""
        let port = jsonInt(profile["port"])
        switch proto {
        case "ss", "shadowsocks":
            return """
            proxies:
              - name: \(name)
                type: ss
                server: \(server)
                port: \(port)
                cipher: \(profile["method"] as? String ?? "aes-128-gcm")
                password: \(profile["password"] as? String ?? "")
            """
        case "vmess":
            return """
            proxies:
              - name: \(name)
                type: vmess
                server: \(server)
                port: \(port)
                uuid: \(profile["uuid"] as? String ?? "")
                alterId: 0
                cipher: auto
                tls: \((profile["tls"] as? String ?? "") != "none")
                network: \(profile["network"] as? String ?? "tcp")
            """
        case "trojan":
            return """
            proxies:
              - name: \(name)
                type: trojan
                server: \(server)
                port: \(port)
                password: \(profile["password"] as? String ?? profile["uuid"] as? String ?? "")
                sni: \(profile["sni"] as? String ?? server)
            """
        default:
            return """
            proxies:
              - name: \(name)
                type: \(proto.isEmpty ? "vless" : proto)
                server: \(server)
                port: \(port)
                uuid: \(profile["uuid"] as? String ?? "")
                tls: \((profile["tls"] as? String ?? "") != "none")
                network: \(profile["network"] as? String ?? "tcp")
            """
        }
    }

    static func v2boxType() -> UTType {
        UTType(filenameExtension: "v2box") ?? .data
    }
}

struct ProfileShareSheet: View {
    @EnvironmentObject var model: Model
    var profile: [String: Any]
    var groupId: String
    var onClose: () -> Void
    @State private var password = ""
    @State private var note = ""
    @State private var allowed = ""
    @State private var expires = ""

    var body: some View {
        SheetBackdrop(onDismiss: onClose) {
            SheetCard {
                VStack(alignment: .leading, spacing: 0) {
                    SheetHeader(title: model.t("share"), subtitle: profile["remark"] as? String ?? "", close: onClose, closeLabel: model.t("cancel"))
                    if let image = ShareKit.qrImage(from: profile["link"] as? String ?? "", scale: 6) {
                        HStack {
                            Spacer()
                            Image(nsImage: image)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 148, height: 148)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Spacer()
                        }
                        .padding(.bottom, 12)
                    }
                    VStack(spacing: 0) {
                        shareRow(model.t("copyLink")) { ShareKit.copy(profile["link"] as? String ?? ""); model.showToast(model.t("saved"), tone: .success) }
                        SettingsDivider(inset: 14)
                        shareRow(model.t("copyJsonXray")) { copyJSON("xray") }
                        SettingsDivider(inset: 14)
                        shareRow(model.t("copyJsonSing")) { copyJSON("singbox") }
                        SettingsDivider(inset: 14)
                        shareRow(model.t("copyQr")) { ShareKit.copyQR(profile["link"] as? String ?? ""); model.showToast(model.t("saved"), tone: .success) }
                        SettingsDivider(inset: 14)
                        shareRow(model.t("shareClash")) {
                            ShareKit.copy(ShareKit.clashYAML(profile["data"] as? [String: Any] ?? profile))
                            model.showToast(model.t("saved"), tone: .success)
                        }
                        SettingsDivider(inset: 14)
                        shareRow(model.t("shareSsr")) {
                            ShareKit.copy(profile["link"] as? String ?? "")
                            model.showToast(model.t("saved"), tone: .success)
                        }
                    }
                    .background(C.cardElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.bottom, 12)
                    Mix(text: model.t("lockShare"), size: 13, weight: .semibold)
                        .padding(.bottom, 8)
                    V2Field(placeholder: model.t("filePassword"), text: $password, latin: true, secure: true, icon: "key.fill")
                        .padding(.bottom, 8)
                    V2Field(placeholder: model.t("shareNote"), text: $note, icon: "text.quote")
                        .padding(.bottom, 8)
                    V2Field(placeholder: model.t("allowedIds"), text: $allowed, latin: true, icon: "person.crop.circle.badge.checkmark")
                        .padding(.bottom, 8)
                    V2Field(placeholder: model.t("expiresAt"), text: $expires, latin: true, icon: "calendar")
                        .padding(.bottom, 12)
                    SheetActionButton(title: model.t("lockShare"), primary: true, icon: "lock.rectangle") { lockShare() }
                    SheetActionButton(title: model.t("cancel"), quiet: true, action: onClose)
                }
            }
        }
    }

    func shareRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Mix(text: title, size: 13, weight: .medium)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(C.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func copyJSON(_ kind: String) {
        let data = model.call("profile_json", ["id": profile["id"] as? String ?? ""])["data"] as? [String: Any] ?? [:]
        ShareKit.copy(data[kind] as? String ?? "")
        model.showToast(model.t("saved"), tone: .success)
    }

    func lockShare() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(profile["remark"] as? String ?? "config").v2box"
        panel.allowedContentTypes = [ShareKit.v2boxType()]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var args: [String: Any] = [
            "path": url.path,
            "password": password,
            "id": profile["id"] as? String ?? "",
            "group_id": groupId,
            "note": note,
            "allowed_ids": allowed
        ]
        if let n = UInt64(expires.trimmingCharacters(in: .whitespaces)) { args["expires_at"] = n }
        let response = model.call("share_locked", args)
        if response["ok"] as? Bool == false {
            model.showToast(response["error"] as? String ?? model.t("failed"), tone: .error)
        } else {
            model.showToast(model.t("saved"), tone: .success)
            onClose()
        }
    }
}

struct ProfileQRSheet: View {
    @EnvironmentObject var model: Model
    var profile: [String: Any]
    var onClose: () -> Void

    var body: some View {
        SheetBackdrop(onDismiss: onClose) {
            SheetCard {
                VStack(alignment: .leading, spacing: 0) {
                    SheetHeader(title: model.t("showQr"), subtitle: profile["remark"] as? String ?? "", close: onClose, closeLabel: model.t("cancel"))
                    if let image = ShareKit.qrImage(from: profile["link"] as? String ?? "", scale: 8) {
                        HStack {
                            Spacer()
                            Image(nsImage: image)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 196, height: 196)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            Spacer()
                        }
                        .padding(.bottom, 14)
                    }
                    SheetActionButton(title: model.t("copyQr"), primary: true, icon: "doc.on.clipboard") {
                        ShareKit.copyQR(profile["link"] as? String ?? "")
                        model.showToast(model.t("saved"), tone: .success)
                    }
                    SheetActionButton(title: model.t("copyLink"), icon: "link") {
                        ShareKit.copy(profile["link"] as? String ?? "")
                        model.showToast(model.t("saved"), tone: .success)
                    }
                    SheetActionButton(title: model.t("cancel"), quiet: true, action: onClose)
                }
            }
        }
    }
}
