//
//  SettingsButton.swift
//  KEXPPowerExampleSwiftUI
//

#if os(iOS)
import SwiftUI

/// The gear that opens Settings as a sheet, on the iPhone and iPad. The Mac has the Settings window.
struct SettingsButton: View {
    let model: ResultRetriever
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing = true
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
        .sheet(isPresented: $isShowing) { SettingsView(model: model) }
    }
}
#endif
