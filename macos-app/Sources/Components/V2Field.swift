import AppKit
import SwiftUI

struct V2Field: View {
    @EnvironmentObject var model: Model
    @Environment(\.themeLight) private var themeLight
    var label: String? = nil
    var placeholder: String = ""
    @Binding var text: String
    var latin: Bool = true
    var secure: Bool = false
    var search: Bool = false
    var pasteable: Bool = false
    var invalid: Bool = false
    var icon: String? = nil
    var hint: String? = nil
    var axis: Axis = .horizontal
    var lineLimit: ClosedRange<Int> = 3...10
    @FocusState private var focused: Bool
    @State private var revealed = false

    private var font: Font {
        .custom(latin ? "Inter" : (model.fa ? "Vazir" : "Inter"), size: 15)
    }

    private var leadingIcon: String? {
        if search { return "magnifyingglass" }
        return icon
    }

    private var stroke: Color {
        if invalid { return Color(red: 1, green: 0.36, blue: 0.45).opacity(0.9) }
        return focused ? C.fieldStrokeFocus : C.fieldStroke
    }

    var body: some View {
        let _ = themeLight
        VStack(alignment: .leading, spacing: 7) {
            if let label, !label.isEmpty {
                Mix(text: label, size: 12, weight: .semibold, color: invalid ? Color(red: 1, green: 0.45, blue: 0.52) : (focused ? C.cyan : C.muted))
            }
            HStack(alignment: axis == .vertical ? .top : .center, spacing: 10) {
                if let leadingIcon {
                    Image(systemName: leadingIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(focused ? C.cyan : C.muted)
                        .frame(width: 18)
                        .padding(.top, axis == .vertical ? 2 : 0)
                }
                Group {
                    if secure && !revealed {
                        SecureField(placeholder, text: $text)
                    } else if axis == .vertical {
                        TextField(placeholder, text: $text, axis: .vertical)
                            .lineLimit(lineLimit)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(C.text)
                .focused($focused)
                if secure {
                    fieldTool(revealed ? "eye.slash" : "eye") { revealed.toggle() }
                        .accessibilityLabel(revealed ? "Hide" : "Show")
                }
                if pasteable {
                    fieldTool("doc.on.clipboard") {
                        if let pasted = NSPasteboard.general.string(forType: .string) {
                            text = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    .help(model.t("paste"))
                    .accessibilityLabel(model.t("paste"))
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, (secure || pasteable) ? 8 : 14)
            .padding(.vertical, 12)
            .background(fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(stroke, lineWidth: focused || invalid ? 1.5 : 1)
            )
            .shadow(color: focused && !invalid ? C.fieldGlow : .clear, radius: focused ? 10 : 0, y: 0)
            .animation(.easeOut(duration: 0.16), value: focused)
            if let hint, !hint.isEmpty {
                Mix(text: hint, size: 11, color: invalid ? Color(red: 1, green: 0.45, blue: 0.52) : C.muted.opacity(0.9))
                    .padding(.leading, 4)
            }
        }
    }

    private func fieldTool(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(C.muted)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var fieldBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(focused ? C.fieldFillFocus : C.fieldFill)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [C.overlay.opacity(focused ? 0.08 : 0.04), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}
