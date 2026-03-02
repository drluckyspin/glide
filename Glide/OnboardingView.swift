import SwiftUI

struct OnboardingView: View {
    var onOpenSettings: () -> Void
    var onQuit: () -> Void
    var debugText: String?

    @State private var hoveredButton: HoveredButton?

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // App icon
                Spacer(minLength: 18)
                Image("AppIcon-Purple")
                    .resizable()
                    .frame(width: 72, height: 72)
                    .shadow(color: accent.opacity(0.4), radius: 12, x: 0, y: 8)
                    .padding(.bottom, 14)

                // Title
                Text("Welcome to Glide")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 6)

                // Subtitle
                Text("Move and resize windows effortlessly with your mouse.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 22)

                // Permission steps
                VStack(alignment: .leading, spacing: 14) {
                    stepRow(
                        number: 1,
                        icon: "gearshape",
                        title: "Open System Settings",
                        description: "Go to Privacy & Security"
                    )
                    stepRow(
                        number: 2,
                        icon: "lock.shield",
                        title: "Select Accessibility",
                        description: "Find Glide in the list"
                    )
                    stepRow(
                        number: 3,
                        icon: "checkmark.circle",
                        title: "Enable Access",
                        description: "Toggle the switch on, then return here"
                    )
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)

                Spacer()

                // Debug line for troubleshooting accessibility state.
                // if let debugText {
                //     Text(debugText)
                //         .font(.system(size: 10))
                //         .foregroundStyle(.secondary)
                //         .multilineTextAlignment(.center)
                //         .padding(.horizontal, 24)
                //         .padding(.bottom, 8)
                // }

                // Buttons
                VStack(spacing: 10) {
                    Button(action: onOpenSettings) {
                        Text("Open System Settings")
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)
                    .background(primaryButtonBackground)
                    .onHover { isHovering in
                        hoveredButton = isHovering ? .openSettings : nil
                    }

                    Button(action: onQuit) {
                        Text("Quit")
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)
                    .background(secondaryButtonBackground)
                    .onHover { isHovering in
                        hoveredButton = isHovering ? .quit : nil
                    }
                }
                .tint(accent)
                .padding(.top, 14)
                .padding(.horizontal, 28)
                .padding(.bottom, 26)
            }
//            .background(cardBackground)
            .padding(18)
        }
        .frame(minWidth: 430, minHeight: 500)
    }

    private func stepRow(number: Int, icon: String, title: String, description: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(accent)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private var accent: Color {
        Color(red: 0.70, green: 0.52, blue: 1.0)
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.05, blue: 0.10),
                Color(red: 0.18, green: 0.10, blue: 0.28),
                Color(red: 0.07, green: 0.06, blue: 0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color(red: 123.0 / 255.0, green: 109.0 / 255.0, blue: 143.0 / 255.0))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(accent.opacity(0.2), lineWidth: 1)
            )
    }

    private var primaryButtonBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(buttonFillColor(for: .openSettings))
    }

    private var secondaryButtonBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(buttonFillColor(for: .quit))
    }

    private func buttonFillColor(for button: HoveredButton) -> Color {
        let base = Color(red: 123.0 / 255.0, green: 109.0 / 255.0, blue: 143.0 / 255.0)
        let hover = Color(red: 142.0 / 255.0, green: 126.0 / 255.0, blue: 168.0 / 255.0)
        return hoveredButton == button ? hover : base
    }

    private enum HoveredButton {
        case openSettings
        case quit
    }
}

#if DEBUG
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(
            onOpenSettings: {},
            onQuit: {},
            debugText: "AX trusted: false\nBundle: /path/to/app"
        )
    }
}
#endif
