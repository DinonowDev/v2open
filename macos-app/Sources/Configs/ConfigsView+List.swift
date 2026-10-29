import AppKit
import SwiftUI

extension ConfigsView {

    func groupCard(_ group: [String: Any]) -> some View {
        let profiles = group["profiles"] as? [[String: Any]] ?? []
        let gid = group["id"] as? String ?? ""
        let name = {
            let raw = group["name"] as? String ?? ""
            return raw.isEmpty ? model.t("local") : raw
        }()
        let subtitle = model.t("custom")
        let expanded = !collapsedGroups.contains(gid)
        return VStack(alignment: .leading, spacing: 0) {
            Button { toggleGroup(gid) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(C.cyan)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Mix(text: name, size: 15, weight: .bold)
                            if group["pinned"] as? Bool == true {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(C.cyan)
                            }
                            Text("\(profiles.count)")
                                .font(.custom("Inter", size: 11).weight(.bold))
                                .foregroundStyle(C.cyan)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(C.cyan.opacity(0.14))
                                .clipShape(Capsule())
                        }
                        if !subtitle.isEmpty {
                            Mix(text: subtitle, size: 12, color: C.muted)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                if !profiles.isEmpty {
                    Button {
                        model.connectTunnel(groupId: gid, smart: true)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .bold))
                            Mix(text: model.t("smartConnect"), size: 11, weight: .semibold)
                        }
                        .foregroundStyle(C.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(C.cyan.opacity(0.14))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                ConfigRowIconButton(systemName: "dot.radiowaves.left.and.right", label: model.t("pingAll")) {
                    runPing(profileIds: profileIds(in: group), args: pingArgs(groupId: gid))
                }
                ConfigRowIconButton(systemName: group["pinned"] as? Bool == true ? "pin.slash" : "pin", label: model.t("pinGroup")) {
                    _ = model.call("pin_group", ["id": gid, "pinned": !(group["pinned"] as? Bool == true)])
                    model.refresh()
                }
                ConfigRowIconButton(systemName: "doc.on.doc", label: model.t("copyAllLinks")) {
                    copyGroupLinks(gid: gid)
                }
                ConfigRowIconButton(systemName: "square.and.arrow.up", label: model.t("exportGroup")) {
                    exportGroup(gid: gid, name: name)
                }
                ConfigRowIconButton(systemName: "trash", label: model.t("deleteAllLocal")) {
                    clearGroup(gid: gid)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .contextMenu {
                Button(group["pinned"] as? Bool == true ? model.t("unpinGroup") : model.t("pinGroup")) {
                    _ = model.call("pin_group", ["id": gid, "pinned": !(group["pinned"] as? Bool == true)])
                    model.refresh()
                }
                Button(model.t("copyAllLinks")) { copyGroupLinks(gid: gid) }
                Button(model.t("exportGroup")) { exportGroup(gid: gid, name: name) }
                Divider()
                Button(model.t("deleteAllLocal"), role: .destructive) { clearGroup(gid: gid) }
            }

            if expanded {
                Rectangle().fill(C.line).frame(height: 1)
                if profiles.isEmpty {
                    Mix(text: model.t("empty"), size: 13, color: C.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                } else {
                    ForEach(profiles.indices, id: \.self) { i in
                        profileRow(profiles[i], groupId: gid, last: i == profiles.count - 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if model.glassy {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.card)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(C.line, lineWidth: 1))
    }

    func toggleGroup(_ id: String) {
        if collapsedGroups.contains(id) { collapsedGroups.remove(id) }
        else { collapsedGroups.insert(id) }
    }

    func profileRow(_ profile: [String: Any], groupId: String, last: Bool) -> some View {
        let proto = ((profile["protocol"] as? String) ?? "").uppercased()
        let ping = jsonInt(profile["ping"])
        let down = jsonInt(profile["download_bps"])
        let up = jsonInt(profile["upload_bps"])
        let selected = (model.settings["selected_id"] as? String) == (profile["id"] as? String)
        let pid = profile["id"] as? String ?? ""
        let port = jsonInt(profile["port"])
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(selected ? C.cyan : Color.clear)
                    .frame(width: 3)
                    .padding(.vertical, 6)
                    .padding(.trailing, 10)

                Button {
                    _ = model.call("select", ["id": pid])
                    model.refresh()
                } label: {
                    HStack(spacing: 10) {
                        Text(String(proto.prefix(4)))
                            .font(.custom("Inter", size: 10).weight(.heavy))
                            .foregroundStyle(selected ? C.cyan : C.muted)
                            .frame(width: 34, height: 34)
                            .background(selected ? C.cyan.opacity(0.18) : C.overlay.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Mix(text: profile["remark"] as? String ?? "", size: 12, weight: .medium)
                                .lineLimit(1)
                            Mix(
                                text: "\(profile["address"] as? String ?? ""):\(port > 0 ? port : 0)",
                                size: 11,
                                color: C.muted
                            )
                            .lineLimit(1)
                            if let created = createdLabel(profile) {
                                Mix(text: created, size: 10, color: C.muted.opacity(0.8))
                                    .lineLimit(1)
                            }
                            if down > 0 || up > 0 {
                                Mix(text: "↓ \(formatBps(down))  ↑ \(formatBps(up))", size: 10, color: C.muted.opacity(0.85))
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        Group {
                            if model.pingingIds.contains(pid) {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 36, height: 16)
                            } else {
                                Mix(
                                    text: PingMark.label(ping, timeout: model.t("pingTimeout")),
                                    size: 11,
                                    weight: .bold,
                                    color: PingMark.color(ping)
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(minWidth: 36, alignment: .trailing)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    ConfigRowIconButton(
                        systemName: "dot.radiowaves.left.and.right",
                        label: model.t("ping"),
                        active: model.pingingIds.contains(pid)
                    ) {
                        runPing(profileIds: [pid], args: pingArgs(profileId: pid))
                    }
                    .disabled(model.pingingIds.contains(pid))

                    ConfigRowMoreMenu {
                        profileMenu(profile, groupId: groupId)
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 10)
            }
            .padding(.leading, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? C.cyan.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? C.cyan.opacity(0.28) : Color.clear, lineWidth: 1)
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 2)

            if !last {
                Rectangle()
                    .fill(C.line.opacity(0.85))
                    .frame(height: 1)
                    .padding(.leading, 58)
                    .padding(.trailing, 12)
            }
        }
        .contextMenu {
            profileMenu(profile, groupId: groupId)
        }
    }

    @ViewBuilder
    func profileMenu(_ profile: [String: Any], groupId: String) -> some View {
        let pid = profile["id"] as? String ?? ""
        Button(model.t("ping")) { runPing(profileIds: [pid], args: pingArgs(profileId: pid)) }
        Button(model.t("copyLink")) {
            ShareKit.copy(profile["link"] as? String ?? "")
        }
        Button(model.t("copyJsonXray")) { copyProfileJSON(pid, key: "xray") }
        Button(model.t("copyJsonSing")) { copyProfileJSON(pid, key: "singbox") }
        Button(model.t("showQr")) { qrProfile = profile }
        Button(model.t("copyQr")) { ShareKit.copyQR(profile["link"] as? String ?? "") }
        Button(model.t("share")) {
            shareGroupId = groupId
            shareProfile = profile
        }
        Button(model.t("lockShare")) {
            shareGroupId = groupId
            shareProfile = profile
        }
        Button(model.t("edit")) {
            model.draft = (profile["data"] as? [String: Any]) ?? profile
            model.draft["id"] = profile["id"] as Any
            model.push("editor")
        }
        Divider()
        Button(model.t("delete"), role: .destructive) {
            _ = model.call("delete", ["id": pid])
            model.refresh()
        }
    }

    func copyProfileJSON(_ id: String, key: String) {
        let data = model.call("profile_json", ["id": id])["data"] as? [String: Any] ?? [:]
        ShareKit.copy(data[key] as? String ?? "")
        model.showToast(model.t("saved"), tone: .success)
    }

    func createdLabel(_ profile: [String: Any]) -> String? {
        let raw = jsonInt(profile["created_at"])
        guard raw > 0 else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(raw))
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return "\(model.t("createdAt")) · \(fmt.string(from: date))"
    }

    func exportGroup(gid: String, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let response = model.call("export_group", ["id": gid, "path": url.path])
        model.showToast(response["ok"] as? Bool == false ? (response["error"] as? String ?? model.t("failed")) : model.t("saved"), tone: response["ok"] as? Bool == false ? .error : .success)
    }

    func copyGroupLinks(gid: String) {
        let response = model.call("export_group", ["id": gid])
        let text = (response["data"] as? [String: Any])?["text"] as? String ?? ""
        ShareKit.copy(text)
        model.showToast(model.t("saved"), tone: .success)
    }

    func clearGroup(gid: String) {
        let alert = NSAlert()
        alert.messageText = model.t("deleteAllLocal")
        alert.informativeText = model.t("confirmDeleteAll")
        alert.addButton(withTitle: model.t("delete"))
        alert.addButton(withTitle: model.t("cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        _ = model.call("clear_group", ["id": gid])
        model.refresh()
        model.showToast(model.t("saved"), tone: .success)
    }
}
