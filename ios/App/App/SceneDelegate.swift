import UIKit
import Capacitor

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = AppViewController()
        window?.makeKeyAndVisible()

        SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    // Cover the log while the app is in the app switcher, so a glance at the screenshot shows nothing.
    private var cover: UIView?

    func sceneWillResignActive(_ scene: UIScene) {
        guard cover == nil, let window = window else { return }
        let v = UIView(frame: window.bounds)
        v.backgroundColor = UIColor(red: 0x10/255.0, green: 0x15/255.0, blue: 0x1a/255.0, alpha: 1)
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(v)
        cover = v
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        cover?.removeFromSuperview()
        cover = nil
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
    }
}
