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
    private var controller: CarPlayController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController
    ) {
        guard let model = AppModelRegistry.model, let saving = AppModelRegistry.saving else {
            logger.error("CarPlay connected before the app's player was ready")
            return
        }
        let controller = CarPlayController(interfaceController: interfaceController, model: model, saving: saving)
        self.controller = controller
        controller.start()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
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
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .carTemplateApplication {
            configuration.delegateClass = CarPlaySceneDelegate.self
        }
        return configuration
    }
}
#endif
