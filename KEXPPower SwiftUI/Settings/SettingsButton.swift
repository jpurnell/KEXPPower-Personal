//
//  SettingsButton.swift
//  KEXPPowerExampleSwiftUI
//

#if os(iOS)
import SwiftUI

/// The gear that asks for Settings, on the iPhone and iPad. The sheet itself is the root view's, so a link can ask for it too.
/// The Mac has the Settings window.
struct SettingsButton: View {
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Button {
            navigation.showingSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
    }
}
#endif
