import SwiftUI
import AppKit

@main
struct MyRagAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = AppStore()
    @AppStorage(AppearanceMode.storageKey) private var appearance: AppearanceMode = .system
    var body: some Scene {
        WindowGroup {
            WorkspaceView().environmentObject(store)
                .frame(minWidth: 1020, minHeight: 700)
                .preferredColorScheme(appearance.colorScheme)
                .onChange(of: appearance, initial: true) { _, mode in
                    NSApp.appearance = mode.appKitAppearance
                }
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Conversation") { store.newConversation() }.keyboardShortcut("n")
                Button("Add Documents…") { store.chooseFiles(folder: false) }.keyboardShortcut("o")
                Button("Add Folder…") { store.chooseFiles(folder: true) }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Connections…") { store.page = .connections }.keyboardShortcut(",")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = AppBrand.image
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
