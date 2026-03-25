import SwiftUI

@main
struct EscudoApp: App {
    @StateObject var dataController: DataController
    @StateObject var unlockManager: UnlockManager
    @StateObject var appLockVM = AppLockViewModel()
    @StateObject var tabBarManager = TabBarManager()

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, dataController.container.viewContext)
                .environmentObject(appLockVM)
                .environmentObject(dataController)
                .environmentObject(unlockManager)
                .environmentObject(tabBarManager)
                .onOpenURL { url in
                    if url.scheme == "escudo" {
                        Task { @MainActor in
                            EnableBankingService.handleCallback(url: url)
                        }
                    }
                }
        }
    }

    init() {
        let dataController = DataController.shared
        let unlockManager = UnlockManager(dataController: dataController)

        _dataController = StateObject(wrappedValue: dataController)
        _unlockManager = StateObject(wrappedValue: unlockManager)

        UITableView.appearance().backgroundColor = .clear
    }
}
