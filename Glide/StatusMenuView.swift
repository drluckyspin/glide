import SwiftUI

final class StatusMenuViewModel: ObservableObject {
    @Published var isDisabled: Bool
    @Published var enabledKeys: Set<ModifierKey>
    @Published var useMouseMove: Bool

    private let onToggleDisabled: (Bool) -> Void
    private let onSetKey: (ModifierKey, Bool) -> Void
    private let onSetMouseMove: (Bool) -> Void
    private let onReset: () -> Void

    init(
        isDisabled: Bool,
        onToggleDisabled: @escaping (Bool) -> Void,
        onSetKey: @escaping (ModifierKey, Bool) -> Void,
        onSetMouseMove: @escaping (Bool) -> Void,
        onReset: @escaping () -> Void
    ) {
        self.isDisabled = isDisabled
        self.enabledKeys = Preferences.shared.enabledKeys
        self.useMouseMove = Preferences.shared.useMouseMove
        self.onToggleDisabled = onToggleDisabled
        self.onSetKey = onSetKey
        self.onSetMouseMove = onSetMouseMove
        self.onReset = onReset
    }

    func toggleDisabled() {
        isDisabled.toggle()
        onToggleDisabled(isDisabled)
    }

    func toggleKey(_ key: ModifierKey) {
        let newValue = !enabledKeys.contains(key)
        if newValue {
            enabledKeys.insert(key)
        } else {
            enabledKeys.remove(key)
        }
        onSetKey(key, newValue)
    }

    func toggleMouseMove() {
        useMouseMove.toggle()
        onSetMouseMove(useMouseMove)
    }

    func resetDefaults() {
        onReset()
        syncFromPreferences()
    }

    func syncFromPreferences() {
        enabledKeys = Preferences.shared.enabledKeys
        useMouseMove = Preferences.shared.useMouseMove
    }
}

struct StatusMenuView: View {
    @ObservedObject var model: StatusMenuViewModel
    var onQuit: () -> Void

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(alignment: .leading, spacing: 14) {
                header

                Divider()
                    .background(Color.white.opacity(0.2))

                toggleRow(title: "Disabled", isOn: model.isDisabled) {
                    model.toggleDisabled()
                }

                VStack(spacing: 10) {
                    toggleRow(title: "Alt", isOn: model.enabledKeys.contains(.alt), isEnabled: !model.isDisabled) {
                        model.toggleKey(.alt)
                    }
                    toggleRow(title: "Cmd", isOn: model.enabledKeys.contains(.cmd), isEnabled: !model.isDisabled) {
                        model.toggleKey(.cmd)
                    }
                    toggleRow(title: "Ctrl", isOn: model.enabledKeys.contains(.ctrl), isEnabled: !model.isDisabled) {
                        model.toggleKey(.ctrl)
                    }
                    toggleRow(title: "Shift", isOn: model.enabledKeys.contains(.shift), isEnabled: !model.isDisabled) {
                        model.toggleKey(.shift)
                    }
                }
                .padding(.leading, 4)

                Divider()
                    .background(Color.white.opacity(0.2))

                toggleRow(title: "Hover move", isOn: model.useMouseMove, isEnabled: !model.isDisabled) {
                    model.toggleMouseMove()
                }

                Divider()
                    .background(Color.white.opacity(0.2))

                Button("Reset to Defaults") {
                    model.resetDefaults()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.9))

                Button("Exit") {
                    onQuit()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.9))
            }
            .padding(16)
            .background(cardBackground)
            .clipShape(BottomRoundedRectangle(radius: 14))
            .overlay(
                BottomRoundedRectangle(radius: 14)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .padding(6)
        }
        .frame(width: 220)
        .fixedSize()
    }

    private var header: some View {
        HStack {
            Text("Glide")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0.32, green: 0.18, blue: 0.55))
                    .frame(width: 24, height: 24)
                    .blur(radius: 6)
                    .opacity(0.9)
                Image("AppIcon-Purple")
                    .resizable()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func toggleRow(title: String, isOn: Bool, isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(isEnabled ? .white : .white.opacity(0.5))
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isEnabled ? accent : .white.opacity(0.35))
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var accent: Color {
        Color(red: 0.70, green: 0.52, blue: 1.0)
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.03, blue: 0.08),
                Color(red: 0.14, green: 0.08, blue: 0.22),
                Color(red: 0.05, green: 0.04, blue: 0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(red: 0.18, green: 0.16, blue: 0.24))
    }

    // headerGlow removed; icon glow is handled inside the header ZStack.
}

struct BottomRoundedRectangle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}
