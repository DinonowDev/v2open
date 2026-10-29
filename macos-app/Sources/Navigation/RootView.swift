import AppKit
import SwiftUI
import Combine

struct RootView: View {
    @EnvironmentObject var model: Model
    var body: some View { themed(model.themeLight) }
    @ViewBuilder func themed(_ light: Bool) -> some View {
        let _ = C.apply(light: light)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 78)
                WindowMoveHandle()
            }
            .environment(\.layoutDirection, .leftToRight)
            .frame(height: PageLayout.titleBar)
            .frame(maxWidth: .infinity)

            Group {
                switch model.current {
                case "configs": ConfigsView()
                case "settings": SettingsView()
                case "routing": RoutingView()
                case "geo_assets": GeoAssetsView()
                case "route_editor": RouteEditorView()
                case "dns": DNSView()
                case "dns_items": DnsItemsView()
                case "xray_advanced": XrayAdvancedView()
                case "network_settings": NetworkSettingsView()
                case "speed_settings": SpeedTestSettingsView()
                case "on_demand": OnDemandView()
                case "backup_settings": BackupSettingsView()
                case "logs": LogsView()
                case "advanced": AdvancedSettingsView()
                case "diagnostics": DiagnosticsView()
                case "clash_status": ClashStatusView()
                case "about": AboutView()
                case "terms": LegalView(kind: .terms)
                case "privacy": LegalView(kind: .privacy)
                case "editor": EditorView()
                case "more": ToolsView()
                case "apps": AppsTunnelView()
                case "speedtest": SpeedTestView()
                default: HomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            LinearGradient(
                colors: [C.bgGradientTop, C.bgGradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .frame(width: AppFrame.width, height: AppFrame.height)
        .scrollIndicators(.hidden)
        .clipped()
        .environment(\.layoutDirection, model.rtl ? .rightToLeft : .leftToRight)
        .environment(\.themeLight, light)
        .environment(\.glassy, model.glassy)
        .preferredColorScheme(model.settings["theme"] as? String == "system" ? nil : (light ? .light : .dark))
        .overlay(alignment: .bottom) {
            TabStrip()
        }
        .overlay(alignment: .bottomTrailing) {
            if showFixedPower {
                PowerConnectButton(
                    connected: model.runtime["connected"] as? Bool ?? false,
                    connecting: (model.runtime["phase"] as? String ?? "") == "connecting",
                    compact: true,
                    action: {
                        if model.runtime["connected"] as? Bool == true { model.disconnectTunnel() }
                        else { model.connectTunnel() }
                    }
                )
                .padding(.trailing, 18)
                .padding(.bottom, 92)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                AppToastView(item: toast)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if let note = model.pendingNote, !note.isEmpty {
                CreatorNoteSheet(note: note) { model.pendingNote = nil }
            }
        }
        .animation(.easeOut(duration: 0.22), value: model.toast?.id)
        .onReceive(Timer.publish(every: 4, on: .main, in: .common).autoconnect()) { _ in
            let response = model.call("tick")
            if let data = response["data"] as? [String: Any] { model.state = data }
            if model.settings["icloud"] as? Bool == true { CloudSync.shared.kick() }
        }
        .onOpenURL { model.handleOpenURL($0) }
    }

    var showFixedPower: Bool {
        guard model.settings["fab_fixed"] as? Bool == true else { return false }
        if model.settings["fab_home_only"] as? Bool == true {
            return model.current == "home"
        }
        return true
    }
}

struct CreatorNoteSheet: View {
    @EnvironmentObject var model: Model
    var note: String
    var onClose: () -> Void

    var body: some View {
        SheetBackdrop(onDismiss: onClose) {
            SheetCard {
                VStack(alignment: .leading, spacing: 0) {
                    SheetHeader(title: model.t("creatorMessage"), subtitle: "", close: onClose, closeLabel: model.t("cancel"))
                    Mix(text: note, size: 14)
                        .padding(.bottom, 14)
                    SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark", action: onClose)
                }
            }
        }
    }
}

struct PageHeader<Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    var caption: String? = nil
    var trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        caption: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.caption = caption
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Mix(text: title, size: PageLayout.titleSize, weight: .bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                trailing
            }
            if let subtitle, !subtitle.isEmpty {
                Mix(text: subtitle, size: PageLayout.subtitleSize, color: C.muted)
                    .padding(.top, PageLayout.titleToSubtitle)
            }
            if let caption, !caption.isEmpty {
                Mix(text: caption, size: PageLayout.captionSize, color: C.muted)
                    .padding(.top, PageLayout.subtitleToCaption)
            }
        }
        .padding(.top, PageLayout.top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WindowMoveHandle())
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, caption: String? = nil) {
        self.init(title: title, subtitle: subtitle, caption: caption) { EmptyView() }
    }
}
