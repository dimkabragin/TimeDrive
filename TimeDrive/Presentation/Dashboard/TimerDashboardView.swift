import SwiftUI
import AppKit
import Combine

struct TimerDashboardView: View {
    @StateObject private var timerViewModel: TimerScreenViewModel
    @StateObject private var tasksViewModel: TasksViewModel
    @StateObject private var projectsViewModel: ProjectsViewModel
    @StateObject private var settingsViewModel: SettingsViewModel
    @State private var activePanel: DashboardPanel?
    private let onWindowReady: (NSWindow) -> Void

    init(appContainer: AppContainer, onWindowReady: @escaping (NSWindow) -> Void) {
        self.onWindowReady = onWindowReady
        _timerViewModel = StateObject(
            wrappedValue: TimerScreenViewModel(
                useCases: appContainer.timerUseCases,
                taskRepository: appContainer.taskRepository,
                settingsRepository: appContainer.settingsRepository
            )
        )
        _tasksViewModel = StateObject(
            wrappedValue: TasksViewModel(
                taskRepository: appContainer.taskRepository,
                projectRepository: appContainer.projectRepository,
                timerUseCases: appContainer.timerUseCases
            )
        )
        _projectsViewModel = StateObject(
            wrappedValue: ProjectsViewModel(
                projectRepository: appContainer.projectRepository,
                taskRepository: appContainer.taskRepository,
                timerRepository: appContainer.timerRepository
            )
        )
        _settingsViewModel = StateObject(
            wrappedValue: SettingsViewModel(
                settingsRepository: appContainer.settingsRepository,
                syncRepository: appContainer.syncRepository,
                timerUseCases: appContainer.timerUseCases,
                syncEngine: appContainer.syncEngine
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TimerHeaderContainerView(
                timerViewModel: timerViewModel,
                activePanel: $activePanel
            )

            if let activePanel {
                Divider()
                    .padding(.horizontal, 16)

                Group {
                    switch activePanel {
                    case .tasks:
                        CompactTasksPanel(viewModel: tasksViewModel)
                    case .projects:
                        CompactProjectsPanel(viewModel: projectsViewModel)
                    case .settings:
                        CompactSettingsPanel(
                            viewModel: settingsViewModel,
                            onSaveDurations: {
                                timerViewModel.safeReloadIdleDurations()
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(16)
            }
        }
        .frame(width: 384, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(.windowBackgroundColor))
        .background(WindowAccessor(onWindowReady: onWindowReady))
        .toolbar {
            ToolbarItem(placement: .principal) {
                titleBarModeSlider
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onChange(of: activePanel) { _, newValue in
            switch newValue {
            case .tasks:
                tasksViewModel.load()
            case .projects:
                projectsViewModel.load()
            case .settings:
                settingsViewModel.load()
            case nil:
                break
            }
        }
    }

    private var titleBarModeSlider: some View {
        HStack(spacing: 4) {
            titleBarModeItem(
                title: String(localized: "panel.work"),
                mode: .work,
                isActive: timerViewModel.displayedMode == .work,
                color: .blue
            )
            titleBarModeItem(
                title: String(localized: "panel.pause"),
                mode: .break,
                isActive: timerViewModel.displayedMode == .break,
                color: .green
            )
        }
        .padding(3)
        .background(Color.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func titleBarModeItem(title: String, mode: TimerMode, isActive: Bool, color: Color) -> some View {
        Button {
            timerViewModel.selectMode(mode)
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(width: 54)
                .padding(.vertical, 6)
                .foregroundStyle(isActive ? Color.white : Color.secondary)
                .background(isActive ? color : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct TimerHeaderContainerView: View {
    @ObservedObject var timerViewModel: TimerScreenViewModel
    @Binding var activePanel: DashboardPanel?

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        TimerHeaderView(
            snapshot: timerViewModel.snapshot,
            displayedMode: timerViewModel.displayedMode,
            idleWorkDurationSec: timerViewModel.idleWorkDurationSec,
            idleBreakDurationSec: timerViewModel.idleBreakDurationSec,
            currentTaskTitle: timerViewModel.currentTask?.title,
            activePanel: activePanel,
            errorMessage: timerViewModel.errorMessage,
            onToggleTimer: toggleTimer,
            onSelectPanel: togglePanel
        )
        .onAppear {
            timerViewModel.restore()
        }
        .onReceive(ticker) { now in
            timerViewModel.safeRefresh(now: now)
        }
    }

    private func toggleTimer() {
        if timerViewModel.snapshot == nil {
            timerViewModel.startSelectedMode()
        } else {
            timerViewModel.stopTimer()
        }
    }

    private func togglePanel(_ panel: DashboardPanel) {
        if activePanel == panel {
            activePanel = nil
        } else {
            activePanel = panel
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    let onWindowReady: (NSWindow) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onWindowReady: onWindowReady)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attachIfNeeded(from: nsView)
    }

    final class Coordinator {
        private weak var attachedWindow: NSWindow?
        private let onWindowReady: (NSWindow) -> Void

        init(onWindowReady: @escaping (NSWindow) -> Void) {
            self.onWindowReady = onWindowReady
        }

        func attachIfNeeded(from view: NSView) {
            guard let window = view.window else {
                #if DEBUG
                print("[TimeDrive][WindowDebug] WindowAccessor.attachIfNeeded: view.window is nil")
                #endif
                return
            }
            guard attachedWindow !== window else { return }
            attachedWindow = window

            #if DEBUG
            print("[TimeDrive][WindowDebug] WindowAccessor.attachIfNeeded: found window, attaching delegate")
            #endif
            onWindowReady(window)
        }
    }
}
