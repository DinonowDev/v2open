import AppKit
import SwiftUI

struct ConfigSearchMotion {
    static func spring(_ reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(duration: 0.38, bounce: 0.14)
    }

    static func open(_ reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.72, anchor: .trailing))
                .combined(with: .offset(y: -6)),
            removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .trailing))
        )
    }
}

struct QuietIconPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ConfigSearchFieldKit: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let field = Self.locateTextField(from: nsView) else { return }
            field.focusRingType = .none
            field.isBordered = false
            field.isBezeled = false
            field.drawsBackground = false
            field.backgroundColor = .clear
            if let cell = field.cell as? NSTextFieldCell {
                cell.focusRingType = .none
                cell.drawsBackground = false
                cell.backgroundColor = .clear
            }
            if let editor = field.currentEditor() as? NSTextView {
                editor.insertionPointColor = NSColor(red: 0.243, green: 0.878, blue: 0.961, alpha: 1)
            }
        }
    }

    private static func locateTextField(from view: NSView) -> NSTextField? {
        var parent = view.superview
        while let current = parent {
            if let found = findTextField(in: current) { return found }
            parent = current.superview
        }
        return nil
    }

    private static func findTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField { return field }
        for child in view.subviews {
            if let found = findTextField(in: child) { return found }
        }
        return nil
    }
}

struct ConfigSearchHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var query: String
    var title: String
    var placeholder: String
    var latin: Bool
    @State private var searching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Mix(text: title, size: PageLayout.titleSize, weight: .bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WindowMoveHandle())
                searchButton
            }

            if searching {
                ConfigSearchField(
                    query: $query,
                    placeholder: placeholder,
                    latin: latin,
                    onClose: closeSearch
                )
                .padding(.top, 10)
                .transition(ConfigSearchMotion.open(reduceMotion))
            }
        }
        .padding(.top, PageLayout.top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onExitCommand(perform: closeSearch)
    }

    private var searchButton: some View {
        Button(action: toggleSearch) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: searching ? "xmark" : "magnifyingglass")
                    .font(.system(size: searching ? 12 : 14, weight: .bold))
                    .foregroundStyle(searching || !query.isEmpty ? C.cyan : C.muted)
                    .frame(width: 32, height: 32)
                    .background(buttonFill)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(
                            searching || !query.isEmpty ? C.cyan.opacity(0.45) : C.line,
                            lineWidth: 1
                        )
                    )

                if !query.isEmpty && !searching {
                    Circle()
                        .fill(C.cyan)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(C.bgGradientTop, lineWidth: 1.5))
                        .offset(x: 1, y: -1)
                }
            }
            .shadow(color: searching ? C.cyan.opacity(0.18) : .clear, radius: 8, y: 0)
            .contentShape(Circle())
        }
        .buttonStyle(QuietIconPressStyle())
        .help(placeholder)
        .accessibilityLabel(placeholder)
        .accessibilityAddTraits(searching ? .isSelected : [])
    }

    private var buttonFill: some View {
        Circle().fill(
            searching || !query.isEmpty
                ? C.cyan.opacity(0.16)
                : C.overlay.opacity(0.06)
        )
    }

    private func toggleSearch() {
        if searching {
            closeSearch()
        } else {
            withAnimation(ConfigSearchMotion.spring(reduceMotion)) { searching = true }
        }
    }

    private func closeSearch() {
        withAnimation(ConfigSearchMotion.spring(reduceMotion)) { searching = false }
    }
}

struct ConfigSearchField: View {
    @EnvironmentObject var model: Model
    @Environment(\.themeLight) private var themeLight
    @Binding var query: String
    var placeholder: String
    var latin: Bool
    var onClose: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        let _ = themeLight
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [C.cyan.opacity(focused ? 0.34 : 0.22), C.cyan.opacity(0.10)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(C.cyan)
            }
            .frame(width: 26, height: 26)

            ZStack(alignment: .leading) {
                if query.isEmpty {
                    Mix(text: placeholder, size: 14, weight: .medium, color: C.muted.opacity(0.78))
                        .allowsHitTesting(false)
                }
                TextField("", text: $query)
                    .textFieldStyle(.plain)
                    .font(.custom(latin ? "Inter" : "Vazir", size: 14.5).weight(.medium))
                    .foregroundStyle(C.text)
                    .focused($focused)
                    .background(ConfigSearchFieldKit())
            }

            if !query.isEmpty {
                Button {
                    query = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(C.text.opacity(0.92))
                        .frame(width: 18, height: 18)
                        .background(C.overlay.opacity(0.14))
                        .clipShape(Circle())
                }
                .buttonStyle(QuietIconPressStyle())
                .help(model.t("cancel"))
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 10)
        .frame(height: 40)
        .background(fieldBackground)
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(
                    colors: focused
                        ? [C.cyan.opacity(0.9), C.accent.opacity(0.42)]
                        : [C.hairline, C.overlay.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: focused ? 1.2 : 1
            )
        )
        .shadow(color: focused ? C.cyan.opacity(0.28) : .black.opacity(0.18), radius: focused ? 12 : 6, y: focused ? 0 : 2)
        .animation(.easeOut(duration: 0.18), value: focused)
        .onAppear { focused = true }
        .onExitCommand {
            if query.isEmpty { onClose() } else { query = "" }
        }
    }

    @ViewBuilder private var fieldBackground: some View {
        ZStack {
            Capsule().fill(C.cardElevated)
            Capsule().fill(
                LinearGradient(
                    colors: [
                        C.overlay.opacity(focused ? 0.10 : 0.055),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}
