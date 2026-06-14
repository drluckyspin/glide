import SwiftUI

final class StatusMenuViewModel: ObservableObject {
    @Published var isDisabled: Bool
    @Published var enabledKeys: Set<ModifierKey>
    @Published var useMouseMove: Bool
    @Published var useRightClickResize: Bool

    private let onToggleDisabled: (Bool) -> Void
    private let onSetKey: (ModifierKey, Bool) -> Void
    private let onSetMouseMove: (Bool) -> Void
    private let onSetRightClickResize: (Bool) -> Void
    private let onReset: () -> Void

    init(
        isDisabled: Bool,
        onToggleDisabled: @escaping (Bool) -> Void,
        onSetKey: @escaping (ModifierKey, Bool) -> Void,
        onSetMouseMove: @escaping (Bool) -> Void,
        onSetRightClickResize: @escaping (Bool) -> Void,
        onReset: @escaping () -> Void
    ) {
        self.isDisabled = isDisabled
        self.enabledKeys = Preferences.shared.enabledKeys
        self.useMouseMove = Preferences.shared.useMouseMove
        self.useRightClickResize = Preferences.shared.useRightClickResize
        self.onToggleDisabled = onToggleDisabled
        self.onSetKey = onSetKey
        self.onSetMouseMove = onSetMouseMove
        self.onSetRightClickResize = onSetRightClickResize
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

    func toggleRightClickResize() {
        useRightClickResize.toggle()
        onSetRightClickResize(useRightClickResize)
    }

    func resetDefaults() {
        onReset()
        isDisabled = false
        syncFromPreferences()
    }

    func syncFromPreferences() {
        enabledKeys = Preferences.shared.enabledKeys
        useMouseMove = Preferences.shared.useMouseMove
        useRightClickResize = Preferences.shared.useRightClickResize
    }
}

struct StatusMenuView: View {
    @ObservedObject var model: StatusMenuViewModel
    var onQuit: () -> Void
    /// When set (e.g. by ScreenshotRenderer), shown instead of `Bundle.main` version.
    var versionOverride: String?

    private static let cornerRadius: CGFloat = 14
    private static let menuWidth: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Divider()
                .background(dividerColor)

            sectionHeader("Activation Keys")
            VStack(spacing: 10) {
                toggleRow(title: "Option", symbol: "option", isOn: model.enabledKeys.contains(.alt), isEnabled: actionsEnabled) {
                    model.toggleKey(.alt)
                }
                toggleRow(title: "Command", symbol: "command", isOn: model.enabledKeys.contains(.cmd), isEnabled: actionsEnabled) {
                    model.toggleKey(.cmd)
                }
                toggleRow(title: "Control", symbol: "control", isOn: model.enabledKeys.contains(.ctrl), isEnabled: actionsEnabled) {
                    model.toggleKey(.ctrl)
                }
                toggleRow(title: "Shift", symbol: "shift", isOn: model.enabledKeys.contains(.shift), isEnabled: actionsEnabled) {
                    model.toggleKey(.shift)
                }
            }

            Divider()
                .background(dividerColor)

            sectionHeader("Window Actions")
            VStack(spacing: 10) {
                toggleRow(title: "Glide", mouseIcon: .glide, isOn: model.useMouseMove, isEnabled: actionsEnabled, tooltip: "Hover to move") {
                    model.toggleMouseMove()
                }

                toggleRow(title: "Resize", mouseIcon: .resize, isOn: model.useRightClickResize, isEnabled: actionsEnabled, tooltip: "Right-click drag") {
                    model.toggleRightClickResize()
                }
            }

            Divider()
                .background(dividerColor)

            VStack(spacing: 10) {
                toggleRow(title: "Disable", isOn: model.isDisabled) {
                    model.toggleDisabled()
                }

                plainAction("Reset to defaults") {
                    model.resetDefaults()
                }

                plainAction("Quit") {
                    onQuit()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            menuCardShape
                .fill(cardColor)
                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 4)
        }
        .overlay(menuCardShape.stroke(Color.white.opacity(0.08), lineWidth: 1))
        .overlay {
            TopLeadingHighlight(cornerRadius: Self.cornerRadius)
                .stroke(dividerColor, style: StrokeStyle(lineWidth: 0.5, lineCap: .round, lineJoin: .round))
        }
        .compositingGroup()
        .frame(width: Self.menuWidth)
        .fixedSize()
    }

    private var actionsEnabled: Bool {
        !model.isDisabled
    }

    private var appVersion: String {
        if let versionOverride, !versionOverride.isEmpty {
            return versionOverride
        }
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private var header: some View {
        HStack {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("Glide")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                if !appVersion.isEmpty {
                    Text("v\(appVersion)")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
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
        .padding(.vertical, 2)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(sectionLabelColor)
    }

    @ViewBuilder
    private func toggleRow(
        title: String,
        symbol: String? = nil,
        mouseIcon: MouseActionIconView.Style? = nil,
        isOn: Bool,
        isEnabled: Bool = true,
        tooltip: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let row = Button(action: action) {
            HStack {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isEnabled ? accent : .white.opacity(0.4))
                        .frame(width: 16)
                } else if let mouseIcon {
                    MouseActionIconView(style: mouseIcon, color: isEnabled ? accent : .white.opacity(0.4))
                }
                Text(title)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(isEnabled ? .white : .white.opacity(0.5))
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: TooltipLabelFrameKey.self,
                                value: geo.frame(in: .named("toggleRow"))
                            )
                        }
                    }
                Spacer()
                toggleIndicator(isOn: isOn, isEnabled: isEnabled)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .coordinateSpace(name: "toggleRow")

        if let tooltip {
            row.hoverTooltip(tooltip)
        } else {
            row
        }
    }

    private func toggleIndicator(isOn: Bool, isEnabled: Bool) -> some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isEnabled ? accent : .white.opacity(0.35))
    }

    private func plainAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var accent: Color {
        Color(red: 0.70, green: 0.52, blue: 1.0)
    }

    private var cardColor: Color {
        Color(red: 0.18, green: 0.16, blue: 0.24)
    }

    private var dividerColor: Color {
        Color.white.opacity(0.2)
    }

    private var sectionLabelColor: Color {
        Color.white.opacity(0.45)
    }

    private var menuCardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius)
    }
}

/// Top-down mouse icons for window actions — matches the monoline SF Symbol style
/// used by the activation-key rows (Option, Command, etc.).
private struct MouseActionIconView: View {
    enum Style {
        case glide
        case resize
    }

    let style: Style
    let color: Color

    var body: some View {
        ZStack {
            if style == .glide {
                MouseGlideMotionShape()
                    .stroke(color, style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
            }
            if style == .resize {
                MouseRightButtonShape(style: style)
                    .fill(color)
            }
            MouseBodyShape(style: style)
                .stroke(color, style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
            MouseButtonDividerShape(style: style)
                .stroke(color, style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
        .frame(width: 16, height: 16)
    }
}

private struct MouseBodyMetrics {
    let body: CGRect
    let corner: CGFloat
    let midX: CGFloat
    let buttonLineY: CGFloat

    init(in rect: CGRect, style: MouseActionIconView.Style) {
        let xFactor: CGFloat = style == .glide ? 0.30 : 0.22
        let widthFactor: CGFloat = style == .glide ? 0.52 : 0.56
        body = CGRect(
            x: rect.width * xFactor,
            y: rect.height * 0.08,
            width: rect.width * widthFactor,
            height: rect.height * 0.84
        )
        corner = body.width / 2
        midX = body.midX
        buttonLineY = body.minY + body.height * 0.36
    }
}

private struct MouseBodyShape: Shape {
    var style: MouseActionIconView.Style

    func path(in rect: CGRect) -> Path {
        let m = MouseBodyMetrics(in: rect, style: style)
        var path = Path()
        path.addRoundedRect(
            in: m.body,
            cornerSize: CGSize(width: m.corner, height: m.corner),
            style: .continuous
        )
        return path
    }
}

private struct MouseButtonDividerShape: Shape {
    var style: MouseActionIconView.Style

    func path(in rect: CGRect) -> Path {
        let m = MouseBodyMetrics(in: rect, style: style)
        var path = Path()
        path.move(to: CGPoint(x: m.midX, y: m.body.minY + m.body.height * 0.14))
        path.addLine(to: CGPoint(x: m.midX, y: m.buttonLineY))
        return path
    }
}

private struct MouseGlideMotionShape: Shape {
    func path(in rect: CGRect) -> Path {
        let m = MouseBodyMetrics(in: rect, style: .glide)
        let lineStartX = rect.minX + rect.width * 0.06
        let lineEndX = m.body.minX - rect.width * 0.04
        let upperY = m.body.midY - m.body.height * 0.17
        let lowerY = m.body.midY + m.body.height * 0.13

        var path = Path()
        path.move(to: CGPoint(x: lineStartX, y: upperY))
        path.addLine(to: CGPoint(x: lineEndX, y: upperY))
        path.move(to: CGPoint(x: lineStartX, y: lowerY))
        path.addLine(to: CGPoint(x: lineEndX, y: lowerY))
        return path
    }
}

private struct MouseRightButtonShape: Shape {
    var style: MouseActionIconView.Style

    func path(in rect: CGRect) -> Path {
        let m = MouseBodyMetrics(in: rect, style: style)
        let inset: CGFloat = 1.15
        let rightButton = CGRect(
            x: m.midX + inset * 0.2,
            y: m.body.minY + inset * 0.35,
            width: m.body.maxX - m.midX - inset,
            height: m.buttonLineY - m.body.minY - inset * 0.25
        )
        let topTrailing = min(m.corner - inset * 0.5, rightButton.width * 0.85, rightButton.height * 0.55)
        let inner = min(1.2, rightButton.width * 0.2)
        var path = Path()
        path.addRoundedRect(
            in: rightButton,
            cornerRadii: RectangleCornerRadii(
                topLeading: inner,
                bottomLeading: inner,
                bottomTrailing: inner,
                topTrailing: topTrailing
            ),
            style: .continuous
        )
        return path
    }
}

/// Hairline highlight on the top and left inner edges, following the corner radius.
private struct TopLeadingHighlight: Shape {
    var cornerRadius: CGFloat
    var inset: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let arcRadius = max(0, cornerRadius - inset)
        let arcCenter = CGPoint(x: cornerRadius, y: cornerRadius)

        path.move(to: CGPoint(x: inset, y: rect.height - cornerRadius))
        path.addLine(to: CGPoint(x: inset, y: cornerRadius))
        path.addArc(
            center: arcCenter,
            radius: arcRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.width - cornerRadius, y: inset))
        return path
    }
}

private struct TooltipLabelFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}

private struct HoverTooltipModifier: ViewModifier {
    let text: String
    var delay: TimeInterval = 0.5

    @State private var showTooltip = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                hoverTask?.cancel()
                if hovering {
                    hoverTask = Task {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            withAnimation(.easeOut(duration: 0.12)) {
                                showTooltip = true
                            }
                        }
                    }
                } else {
                    showTooltip = false
                }
            }
            .onDisappear {
                hoverTask?.cancel()
                showTooltip = false
            }
            .overlayPreferenceValue(TooltipLabelFrameKey.self) { frame in
                GeometryReader { _ in
                    if showTooltip, frame.width > 0 {
                        Color.clear
                            .frame(width: 0, height: 0)
                            .overlay(alignment: .bottomLeading) {
                                tooltipBubble
                                    .fixedSize()
                            }
                            .position(x: frame.minX + 27, y: frame.minY - 5)
                    }
                }
                .allowsHitTesting(false)
            }
    }

    private var tooltipBubble: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0.12, green: 0.11, blue: 0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 6, y: 2)
            )
            .transition(.opacity)
    }
}

private extension View {
    func hoverTooltip(_ text: String, delay: TimeInterval = 0.5) -> some View {
        modifier(HoverTooltipModifier(text: text, delay: delay))
    }
}
