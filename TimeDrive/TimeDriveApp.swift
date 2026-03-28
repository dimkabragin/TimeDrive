//
//  TimeDriveApp.swift
//  TimeDrive
//
//  Created by Дмитрий Брагин on 27.03.2026.
//

import SwiftUI
import SwiftData
import AppKit

@main
struct TimeDriveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    let sharedModelContainer: ModelContainer
    let appContainer: AppContainer

    init() {
        let modelContainer = Self.makeSharedModelContainer()
        self.sharedModelContainer = modelContainer
        self.appContainer = AppContainer(modelContext: modelContainer.mainContext)
        appDelegate.configure(appContainer: appContainer)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                appContainer: appContainer,
                onWindowReady: appDelegate.attach(window:)
            )
        }
        .windowResizability(.contentSize)
        .modelContainer(sharedModelContainer)
    }

    private static func makeSharedModelContainer() -> ModelContainer {
        let schema = Schema([
            Project.self,
            Task.self,
            TimerSettings.self,
            TimerSession.self,
            TimerState.self,
            TimeEvent.self,
            SyncOperation.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private weak var window: NSWindow?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var refreshTimer: Timer?
    private var appContainer: AppContainer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyMenuBarOnlyActivationPolicy()
    }

    func configure(appContainer: AppContainer) {
        guard self.appContainer == nil else { return }
        self.appContainer = appContainer
        applyMenuBarOnlyActivationPolicy()
        configureStatusItem()
        startRefreshingStatusItem()
    }

    func attach(window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.delegate = self
        applyMenuBarOnlyActivationPolicy()

        debugLog("attach(window:) called. styleMask before=\(window.styleMask)")

        // Keep only close affordance for menu bar style workflow.
        window.styleMask.remove([.miniaturizable, .resizable])
        window.collectionBehavior.remove(.fullScreenPrimary)

        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.closeButton)?.isHidden = false

        let miniButton = window.standardWindowButton(.miniaturizeButton)
        let zoomButton = window.standardWindowButton(.zoomButton)
        debugLog(
            "attach(window:) applied. styleMask after=\(window.styleMask), " +
            "mini(hidden=\(miniButton?.isHidden ?? false), enabled=\(miniButton?.isEnabled ?? true)), " +
            "zoom(hidden=\(zoomButton?.isHidden ?? false), enabled=\(zoomButton?.isEnabled ?? true))"
        )
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        debugLog("windowShouldClose(_:): hide window instead of terminating")
        sender.orderOut(nil)
        return false
    }

    @objc private func toggleWindowVisibility() {
        guard let window else { return }
        applyMenuBarOnlyActivationPolicy()
        debugLog("toggleWindowVisibility() called. isVisible=\(window.isVisible)")
        if window.isVisible {
            window.orderOut(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[TimeDrive][WindowDebug] \(message)")
        #endif
    }

    @objc private func terminateApp() {
        NSApp.terminate(nil)
    }

    private func applyMenuBarOnlyActivationPolicy() {
        if NSApp.activationPolicy() != .accessory {
            let success = NSApp.setActivationPolicy(.accessory)
            debugLog("applyMenuBarOnlyActivationPolicy(): success=\(success)")
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(toggleWindowVisibility)
        button.sendAction(on: [.leftMouseUp])
        updateStatusItemTitle()

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Open TimeDrive",
            action: #selector(toggleWindowVisibility),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit TimeDrive",
            action: #selector(terminateApp),
            keyEquivalent: "q"
        )
        menu.items.forEach { $0.target = self }
        statusItem.menu = nil
    }

    private func startRefreshingStatusItem() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusItemTitle()
            }
        }
    }

    private func updateStatusItemTitle() {
        guard let button = statusItem.button else { return }
        let title = statusItemText()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        button.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        button.image = nil
        button.toolTip = "TimeDrive"
    }

    private func statusItemText(now: Date = .now) -> String {
        guard let appContainer else { return "25:00" }

        if let snapshot = try? appContainer.timerUseCases.activeSnapshot(now: now) {
            if snapshot.isInExtraTime {
                return "00:00"
            }
            return formatClock(max(0, snapshot.remainingSec))
        }

        let workDuration = (try? appContainer.settingsRepository.getOrCreate().workDurationSec) ?? 25 * 60
        return formatClock(workDuration)
    }

    private func formatClock(_ totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
