import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: Model
    @State private var mountedTabs: Set<String> = ["home"]

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
                if model.stack.isEmpty {
                    mainTabStack
                } else {
                    stackedPage
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
                RootFixedPowerButton()
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
        .onChange(of: model.page) { _, page in
            mountedTabs.insert(normalizedTab(page))
        }
        .onOpenURL { model.handleOpenURL($0) }
    }

    private func normalizedTab(_ page: String) -> String {
        page.isEmpty || page == "home" ? "home" : page
    }

    private var activeTab: String { normalizedTab(model.page) }

    @ViewBuilder
    private var mainTabStack: some View {
        let tab = activeTab
        ZStack {
            cachedTab("home", active: tab == "home") { HomeView(isActive: tab == "home") }
            cachedTab("configs", active: tab == "configs") { ConfigsView() }
            cachedTab("speedtest", active: tab == "speedtest") { SpeedTestView() }
            cachedTab("settings", active: tab == "settings") { SettingsView() }
        }
        .onAppear { mountedTabs.insert(tab) }
    }

    @ViewBuilder
    private func cachedTab<Content: View>(
        _ id: String,
        active: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if mountedTabs.contains(id) {
            content()
                .opacity(active ? 1 : 0)
                .allowsHitTesting(active)
                .accessibilityHidden(!active)
                .zIndex(active ? 1 : 0)
        }
    }

    @ViewBuilder
    private var stackedPage: some View {
        switch model.current {
        case "routing": RoutingView()
        case "geo_assets": GeoAssetsView()
        case "route_editor": RouteEditorView()
        case "dns": DNSView()
        case "dns_items": DnsItemsView()
        case "xray_advanced": XrayAdvancedView()
        case "warp": WarpView()
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
        default: SettingsView()
        }
    }

    var showFixedPower: Bool {
        guard model.settings["fab_fixed"] as? Bool == true else { return false }
        if model.settings["fab_home_only"] as? Bool == true {
            return model.current == "home"
        }
        return true
    }
}

struct RootFixedPowerButton: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var liveRuntime: LiveRuntime

    var body: some View {
        let runtime = liveRuntime.values.isEmpty ? model.runtime : liveRuntime.values
        let connected = runtime["connected"] as? Bool ?? false
        let connecting = (runtime["phase"] as? String ?? "") == "connecting"
        PowerConnectButton(
            connected: connected,
            connecting: connecting,
            compact: true,
            action: {
                if connected { model.disconnectTunnel() }
                else { model.connectTunnel() }
            }
        )
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
