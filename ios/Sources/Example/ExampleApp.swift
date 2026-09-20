import SwiftUI

#if os(macOS)
    import AppKit
#endif

@main
struct ExampleApp: App {
    #if os(macOS)
        @NSApplicationDelegateAdaptor(ExampleMacOSAppDelegate.self) private var appDelegate
    #else
        @StateObject private var session = ExampleSessionController()
    #endif

    @SceneBuilder
    var body: some Scene {
        #if os(macOS)
            Settings {
                EmptyView()
            }
        #else
            WindowGroup {
                ExampleScene(session: session)
                    .onAppear {
                        session.handleSceneAppear()
                    }
                    .onDisappear {
                        session.handleSceneDisappear()
                    }
            }
        #endif
    }
}

#if os(macOS)
    @MainActor
    private final class ExampleMacOSAppState {
        static let shared = ExampleMacOSAppState()

        let session = ExampleSessionController()

        private init() {}
    }

    @MainActor
    private final class ExampleMacOSAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
        private var window: NSWindow?

        func applicationDidFinishLaunching(_ notification: Notification) {
            NSApplication.shared.setActivationPolicy(.regular)
            UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
            ensureWindow()
        }

        func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
            -> Bool
        {
            if !flag {
                ensureWindow()
            }
            return true
        }

        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
            true
        }

        func windowWillClose(_ notification: Notification) {
            ExampleMacOSAppState.shared.session.handleSceneDisappear()
            window = nil
        }

        private func ensureWindow() {
            if let window {
                ExampleMacOSWindowLayout.apply(to: window)
                NSApplication.shared.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.makeMain()
                return
            }

            let session = ExampleMacOSAppState.shared.session
            let rootView = ExampleScene(session: session)
                .onAppear {
                    session.handleSceneAppear()
                }
                .onDisappear {
                    session.handleSceneDisappear()
                }
            let window = NSWindow(
                contentRect: ExampleMacOSWindowLayout.initialContentRect,
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Example"
            window.contentView = NSHostingView(rootView: rootView)
            window.delegate = self
            ExampleMacOSWindowLayout.apply(to: window)
            window.center()
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeMain()
            self.window = window
        }
    }

    private enum ExampleMacOSWindowLayout {
        private static let defaultContentSize = NSSize(width: 1024, height: 700)
        private static let minimumWindowSize = NSSize(width: 360, height: 560)
        private static let screenMargin: CGFloat = 48

        @MainActor
        static var initialContentRect: NSRect {
            guard let screen = NSScreen.main else {
                return NSRect(origin: .zero, size: defaultContentSize)
            }
            let available = screen.visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
            return NSRect(
                origin: .zero,
                size: NSSize(
                    width: min(defaultContentSize.width, available.width),
                    height: min(defaultContentSize.height, available.height)
                )
            )
        }

        @MainActor
        static func apply(to window: NSWindow) {
            window.minSize = minimumWindowSize
            window.backgroundColor = NSColor(
                calibratedRed: 1.0,
                green: 0.9725,
                blue: 0.9098,
                alpha: 1.0
            )
            window.isOpaque = true
            window.standardWindowButton(.zoomButton)?.isEnabled = true
            window.isRestorable = false
        }
    }
#endif
