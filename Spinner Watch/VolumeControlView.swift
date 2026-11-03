//
//  VolumeControlView.swift
//  Spinner Watch
//

import SwiftUI
import WatchKit

/// The system volume control: showing it lets the Digital Crown change the listening volume.
struct VolumeControlView: WKInterfaceObjectRepresentable {
    func makeWKInterfaceObject(context: Context) -> WKInterfaceVolumeControl {
        WKInterfaceVolumeControl(origin: .local)
    }

    func updateWKInterfaceObject(_ object: WKInterfaceVolumeControl, context: Context) {}
}
