import SwiftUI

struct SoftSwitch: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? C.green : Color(red: 0.22, green: 0.22, blue: 0.24))
                Circle()
                    .fill(.white)
                    .padding(2)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            }
            .frame(width: 40, height: 22)
        }
        .buttonStyle(QuietPressStyle())
        .animation(.easeOut(duration: 0.16), value: isOn)
    }
}

struct SoftSelect: View {
    var title: String? = nil
    var value: String
    var options: [(String, String)]
    var wide = false
    var icon: String? = nil
    var onSelect: (String) -> Void
    @State private var open = false

    var chosenLabel: String { options.first { $0.0 == value }?.1 ?? value }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title, !title.isEmpty {
                Mix(text: title, size: 12, weight: .semibold, color: open ? C.cyan : C.muted)
            }
            Button { open.toggle() } label: {
                HStack(spacing: 10) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(open ? C.cyan : C.muted)
                            .frame(width: 18)
                    }
                    Mix(text: chosenLabel, size: 15, weight: .medium, color: .white)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(C.muted)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: wide ? .infinity : nil, alignment: .leading)
                .background(open ? C.fieldFillFocus : C.fieldFill)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(open ? C.fieldStrokeFocus : C.fieldStroke, lineWidth: open ? 1.5 : 1)
                )
            }
            .buttonStyle(QuietPressStyle())
            .popover(isPresented: $open, arrowEdge: .top) {
                VStack(spacing: 2) {
                    ForEach(options, id: \.0) { option in
                        let chosen = option.0 == value
                        Button {
                            onSelect(option.0)
                            open = false
                        } label: {
                            HStack(spacing: 10) {
                                Mix(text: option.1, size: 14, weight: chosen ? .semibold : .regular, color: chosen ? C.cyan : .white)
                                Spacer()
                                if chosen {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(C.cyan)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(chosen ? C.cyan.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .frame(minWidth: 240)
                .background(C.cardElevated)
                .presentationBackground(C.cardElevated)
            }
        }
    }
}

struct TabStrip: View {
    @EnvironmentObject var model: Model

    private var activeId: String? {
        model.stack.isEmpty ? model.page : nil
    }

    var body: some View {
        HStack(spacing: 2) {
            tab("home", "house.fill", model.t("home"))
            tab("configs", "list.bullet", model.t("configs"))
            tab("speedtest", "gauge.with.dots.needle.67percent", model.t("speedTab"))
            tab("settings", "gearshape.fill", model.t("settings"))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, 4)
    }

    func tab(_ id: String, _ icon: String, _ title: String) -> some View {
        let on = activeId == id
        return Button { model.go(id) } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(on ? C.accent : Color.white.opacity(0.72))
                Mix(
                    text: title,
                    size: 10,
                    weight: .semibold,
                    color: on ? C.accent : Color.white.opacity(0.70)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

func sub<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        BackTitle(title: title)
        content()
    }
}

struct BackTitle: View {
    @EnvironmentObject var model: Model
    var title: String
    var body: some View {
        HStack(spacing: 12) {
            Button { model.pop() } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(C.cyan)
                    .frame(width: 32, height: 32)
                    .background(C.cyan.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(QuietPressStyle())
            .accessibilityLabel(model.t("back"))
            Mix(text: title, size: PageLayout.titleSize, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PageLayout.horizontal)
        .padding(.top, PageLayout.top)
        .padding(.bottom, 8)
        .background(WindowMoveHandle())
    }
}
