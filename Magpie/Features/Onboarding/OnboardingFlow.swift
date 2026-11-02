import SwiftUI

/// The first-launch flow (04 · 07a, 07b): Welcome, then the engine picker. The picker's
/// last step marks onboarding done, which is what dismisses the flow.
struct OnboardingFlow: View {
    let preferences: Preferences
    @State private var showsPicker = false

    var body: some View {
        ZStack {
            MistBackground()
                .ignoresSafeArea()
            if showsPicker {
                EnginePickerScreen(preferences: preferences) {
                    preferences.hasCompletedOnboarding = true
                }
                .transition(.opacity)
                .backSwipe {
                    withAnimation(Springs.crossfade) { showsPicker = false }
                }
            } else {
                WelcomeScreen {
                    withAnimation(Springs.crossfade) { showsPicker = true }
                }
                .transition(.opacity)
            }
        }
    }
}

#Preview {
    OnboardingFlow(preferences: Preferences(defaults: UserDefaults(suiteName: "preview-onboarding") ?? .standard))
}
