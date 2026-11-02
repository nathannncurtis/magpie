import SwiftUI

/// The "Get" capsule on a directory row (03 · Get button): the primary action, compact.
struct GetButton: View {

    let action: () -> Void

    var body: some View {
        Button(String(localized: "Get"), action: action)
            .buttonStyle(.primary(.compact))
            .accessibilityIdentifier("mods.get")
    }
}

#Preview {
    GetButton {}
        .padding(20)
}
