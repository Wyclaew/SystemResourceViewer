import SwiftUI

/// Interactive author badge displaying "WycDev" and secret companion icons upon 7 clicks.
public struct AuthorBadgeView: View {
    @ObservedObject public var stateMachine: EasterEggStateMachine

    public init(stateMachine: EasterEggStateMachine = EasterEggStateMachine()) {
        self.stateMachine = stateMachine
    }

    public var body: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                stateMachine.registerClick()
            }
        } label: {
            HStack(spacing: 5) {
                Text("WycDev")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                if stateMachine.state.isUnlocked {
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.red)

                        Image(systemName: "cat.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(stateMachine.state.isUnlocked ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(stateMachine.state.isUnlocked ? "PulseCore by WycDev (Unlocked ❤️🐱)" : "PulseCore by WycDev")
        .overlay {
            if stateMachine.state.showConfetti {
                let sm = stateMachine
                ConfettiView {
                    sm.dismissConfetti()
                }
                .frame(width: 480, height: 320)
                .offset(y: -120)
                .allowsHitTesting(false)
            }
        }
    }
}
