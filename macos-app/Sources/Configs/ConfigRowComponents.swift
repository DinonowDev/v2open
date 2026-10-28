import SwiftUI

struct ConfigActionBar: View {
    var sortTitle: String
    var addTitle: String
    var qrTitle: String
    var updateTitle: String
    var pingTitle: String
    var onAdd: () -> Void
    var onQR: () -> Void
    var onSort: () -> Void
    var onUpdate: () -> Void
    var onPing: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            addButton
            barDivider
            iconButton("qrcode.viewfinder", help: qrTitle, action: onQR)
            barDivider
            sortButton
            barDivider
            iconButton("arrow.clockwise", help: updateTitle, action: onUpdate)
            barDivider
            iconButton("dot.radiowaves.left.and.right", help: pingTitle, action: onPing)
        }
        .frame(height: 40)
        .background(C.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(C.line, lineWidth: 1)
        )
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(C.cyan)
        }
        .buttonStyle(.plain)
        .help(addTitle)
    }

    private var sortButton: some View {
        Button(action: onSort) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(C.muted)
                Mix(text: sortTitle, size: 12, weight: .semibold, color: .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(C.muted)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(sortTitle)
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(C.cyan)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var barDivider: some View {
        Rectangle()
            .fill(C.line)
            .frame(width: 1, height: 18)
    }
}

struct ConfigChip: View {
    var title: String
    var accent = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Mix(text: title, size: 13, weight: .semibold, color: accent ? C.cyan : .white)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(accent ? C.cyan.opacity(0.12) : C.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(accent ? C.cyan.opacity(0.35) : C.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct ConfigIconButton: View {
    var systemName: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(C.cyan)
                .frame(width: 36, height: 36)
                .background(C.cyan.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(C.cyan.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct ConfigRowIconLabel: View {
    var systemName: String
    var active = false
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(active ? C.cyan : C.muted)
            .frame(width: 28, height: 28)
            .background(Color.white.opacity(active ? 0.08 : 0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(C.line.opacity(0.9), lineWidth: 1))
    }
}

struct ConfigRowIconButton: View {
    var systemName: String
    var label: String
    var active = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            ConfigRowIconLabel(systemName: systemName, active: active)
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

struct ConfigRowMoreMenu<Content: View>: View {
    @State private var open = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        ConfigRowIconButton(systemName: "ellipsis", label: "More") {
            open.toggle()
        }
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                content()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .frame(minWidth: 140)
        }
    }
}

struct ConfigMiniButton: View {
    var title: String
    var danger = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Mix(text: title, size: 11, weight: .semibold, color: danger ? Color(red: 1, green: 0.36, blue: 0.45) : C.muted)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(C.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
