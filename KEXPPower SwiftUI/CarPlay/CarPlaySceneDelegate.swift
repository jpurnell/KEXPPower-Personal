//
//  CarPlaySceneDelegate.swift
//  KEXPPowerExampleSwiftUI
//

#if os(iOS)
import CarPlay
import OSLog
import UIKit

/// Receives CarPlay's connection and builds the car's screens from the app's shared player.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private let logger = Logger(subsystem: "com.JPEnterprises.Spinner", category: "CarPlay")
    private let diagnostics = DiagnosticLog.app
    private var controller: CarPlayController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController
    ) {
        diagnostics.record("CarPlay", "scene delegate: car connected")
        guard let model = AppModelRegistry.model, let saving = AppModelRegistry.saving else {
            logger.error("CarPlay connected before the app's player was ready")
            diagnostics.record("CarPlay", "scene delegate: connected before the player was ready")
            return
        }
        let controller = CarPlayController(interfaceController: interfaceController, model: model, saving: saving)
        self.controller = controller
        controller.start()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        diagnostics.record("CarPlay", "scene delegate: car disconnected")
        controller?.stop()
        controller = nil
    }
}

/// Gives the system the CarPlay scene configuration; every other scene is left to SwiftUI.
final class CarPlayAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // The CarPlay scene's delegate class comes from the Info.plist scene manifest, under this name.
        let isCar = connectingSceneSession.role == .carTemplateApplication
        DiagnosticLog.app.record("CarPlay", "app delegate: scene requested, role \(connectingSceneSession.role.rawValue), car \(isCar)")
        return UISceneConfiguration(name: isCar ? "CarPlay" : nil, sessionRole: connectingSceneSession.role)
    }
}
#endif
