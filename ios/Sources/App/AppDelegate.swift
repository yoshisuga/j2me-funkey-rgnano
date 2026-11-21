import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // a crash from an exception says why on stderr (simctl launch --console / Xcode console)
        NSSetUncaughtExceptionHandler { e in
            fputs("uncaught exception: \(e.name.rawValue): \(e.reason ?? "")\n", stderr)
        }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: "Default", sessionRole: session.role)
        c.delegateClass = SceneDelegate.self
        return c
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var list: GameListViewController?

    /// Files opened from Files, AirDrop or the share sheet.
    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        list?.importURLs(contexts.map { $0.url })
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: ws)
        list = GameListViewController()
        w.rootViewController = UINavigationController(rootViewController: list!)
        w.makeKeyAndVisible()
        window = w
    }
}
