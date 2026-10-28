import AppKit
import SwiftUI

extension ConfigsView {

    func groupCard(_ group: [String: Any]) -> some View {
        let profiles = group["profiles"] as? [[String: Any]] ?? []
        let gid = group["id"] as? String ?? ""
        let name = (group["kind"] as? String) == "local" ? model.t("local") : (group["name"] as? String ?? "")
        let subtitle = (group["kind"] as? String) == "local" ? model.t("custom") : (group["url"] as? String ?? "")
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

            if (group["kind"] as? String) == "subscription" {
                SubscriptionQuotaView(group: group)
                HStack(spacing: 8) {
                    ConfigRowIconButton(systemName: "arrow.clockwise", label: model.t("update")) {
                        if let err = model.invoke("update_group", ["id": gid]) {
                            model.showToast(err, tone: .error)
                        } else {
                            model.showToast(model.t("subRefreshed"), tone: .success)
                        }
                    }
                    ConfigRowIconButton(systemName: "dot.radiowaves.left.and.right", label: model.t("pingAll")) {
                        runPing(profileIds: profileIds(in: group), args: pingArgs(groupId: gid))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
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
                        profileRow(profiles[i], last: i == profiles.count - 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(C.line, lineWidth: 1))
    }

    func toggleGroup(_ id: String) {
        if collapsedGroups.contains(id) { collapsedGroups.remove(id) }
        else { collapsedGroups.insert(id) }
    }

    func profileRow(_ profile: [String: Any], last: Bool) -> some View {
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
                            .background(selected ? C.cyan.opacity(0.18) : Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Mix(text: profile["remark"] as? String ?? "", size: 12, weight: .medium, color: .white)
                                .lineLimit(1)
                            Mix(
                                text: "\(profile["address"] as? String ?? ""):\(port > 0 ? port : 0)",
                                size: 11,
                                color: C.muted
                            )
                            .lineLimit(1)
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
                        Button(model.fa ? "کپی لینک" : "Copy link") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString((profile["link"] as? String) ?? "", forType: .string)
                        }
                        Button(model.fa ? "ویرایش" : "Edit") {
                            model.draft = (profile["data"] as? [String: Any]) ?? profile
                            model.draft["id"] = profile["id"] as Any
                            model.push("editor")
                        }
                        Divider()
                        Button(model.fa ? "حذف" : "Delete", role: .destructive) {
                            _ = model.call("delete", ["id": pid])
                            model.refresh()
                        }
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
            Button(model.t("ping")) { runPing(profileIds: [pid], args: pingArgs(profileId: pid)) }
            Button(model.fa ? "کپی لینک" : "Copy link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString((profile["link"] as? String) ?? "", forType: .string)
            }
            Button(model.fa ? "ویرایش" : "Edit") {
                model.draft = (profile["data"] as? [String: Any]) ?? profile
                model.draft["id"] = profile["id"] as Any
                model.push("editor")
            }
            Divider()
            Button(model.fa ? "حذف" : "Delete", role: .destructive) {
                _ = model.call("delete", ["id": pid])
                model.refresh()
            }
        }
    }
}
