import SwiftUI
import AppKit

@main
struct FigCNStudioSwiftApp: App {
    @StateObject private var controller = ServiceController()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .frame(minWidth: 980, minHeight: 660)
                .task {
                    appDelegate.controller = controller
                    await controller.recoverStaleSystemProxy()
                    try? await controller.refreshStatus()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var controller: ServiceController?
    private var isCleaningUp = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller, !isCleaningUp else { return .terminateNow }
        isCleaningUp = true
        Task { @MainActor in
            await controller.cleanupBeforeQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
