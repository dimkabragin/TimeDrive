import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var workDurationMinutes: Int = 25
    @Published var breakDurationMinutes: Int = 5
    @Published var autoStartNext: Bool = false
    @Published var autoUpdatesEnabled: Bool = false
    @Published var areAutoUpdatesAvailable: Bool = false
    @Published var isCheckingForUpdates: Bool = false
    @Published var updatesStatusMessage: String?
    @Published var syncStatus = SyncStatusSnapshot(
        isOnlinePlaceholder: false,
        pendingOperations: 0,
        lastSyncText: String(localized: "sync.notAvailable")
    )
    @Published var isSyncingNow: Bool = false
    @Published var errorMessage: String?

    private let settingsRepository: SettingsRepository
    private let syncRepository: SyncRepository
    private let timerUseCases: TimerUseCases
    private let syncEngine: SyncEngine
    private let updateService: UpdateService
    private var updateCheckEventsCancellable: AnyCancellable?
    private var isAwaitingManualUpdateResult: Bool = false
    private static let lastSyncFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    init(
        settingsRepository: SettingsRepository,
        syncRepository: SyncRepository,
        timerUseCases: TimerUseCases,
        syncEngine: SyncEngine,
        updateService: UpdateService
    ) {
        self.settingsRepository = settingsRepository
        self.syncRepository = syncRepository
        self.timerUseCases = timerUseCases
        self.syncEngine = syncEngine
        self.updateService = updateService
        bindUpdateCheckEvents()
    }

    func load() {
        do {
            let settings = try settingsRepository.getOrCreate()
            workDurationMinutes = max(1, settings.workDurationSec / 60)
            breakDurationMinutes = max(1, settings.breakDurationSec / 60)
            autoStartNext = settings.autoStartNext
            autoUpdatesEnabled = settings.autoUpdatesEnabled ?? false
            areAutoUpdatesAvailable = updateService.isAutoUpdateSupported
            updateService.setAutomaticChecksEnabled(autoUpdatesEnabled)
            if !areAutoUpdatesAvailable {
                updatesStatusMessage = String(localized: "settings.updates.notAvailable")
            } else if autoUpdatesEnabled {
                updatesStatusMessage = String(localized: "settings.updates.status.idle")
            } else {
                updatesStatusMessage = String(localized: "settings.updates.status.manualOnly")
            }

            let pending = try syncRepository.pendingOperations().count
            let lastSyncText = formatLastSync(syncEngine.lastSyncAt())
            syncStatus = SyncStatusSnapshot(
                isOnlinePlaceholder: false,
                pendingOperations: pending,
                lastSyncText: lastSyncText
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveDurations() {
        do {
            _ = try timerUseCases.updateDurations(
                workDurationSec: max(1, workDurationMinutes) * 60,
                breakDurationSec: max(1, breakDurationMinutes) * 60
            )
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveAutoStartNext() {
        do {
            _ = try timerUseCases.updateAutoStartNext(autoStartNext)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveAutoUpdatesEnabled() {
        do {
            _ = try timerUseCases.updateAutoUpdatesEnabled(autoUpdatesEnabled)
            updateService.setAutomaticChecksEnabled(autoUpdatesEnabled)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func checkForUpdatesNow() {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        isAwaitingManualUpdateResult = true
        updatesStatusMessage = String(localized: "settings.updates.checking")

        _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.updateService.checkForUpdates()
            self.handleInitialUpdateCheckResult(result)
        }
    }

    func syncNow() {
        guard !isSyncingNow else { return }
        isSyncingNow = true
        errorMessage = nil

        _Concurrency.Task { @MainActor in
            defer {
                isSyncingNow = false
            }
            do {
                try await syncEngine.syncNow()
                load()
            } catch {
                load()
                errorMessage = error.localizedDescription
            }
        }
    }

    private func formatLastSync(_ date: Date?) -> String {
        guard let date else { return String(localized: "sync.notSyncedYet") }
        return Self.lastSyncFormatter.string(from: date)
    }

    private func bindUpdateCheckEvents() {
        updateCheckEventsCancellable = updateService.checkForUpdatesEvents
            .sink { [weak self] result in
                _Concurrency.Task { @MainActor [weak self] in
                    self?.handleUpdateCheckEvent(result)
                }
            }
    }

    private func handleInitialUpdateCheckResult(_ result: UpdateCheckResult) {
        switch result {
        case .checking:
            updatesStatusMessage = String(localized: "settings.updates.checking")
        case .upToDate, .updateAvailable, .unavailable, .failed:
            applyFinalUpdateCheckResult(result)
        }
    }

    private func handleUpdateCheckEvent(_ result: UpdateCheckResult) {
        guard isAwaitingManualUpdateResult else { return }
        switch result {
        case .checking:
            updatesStatusMessage = String(localized: "settings.updates.checking")
        case .upToDate, .updateAvailable, .unavailable, .failed:
            applyFinalUpdateCheckResult(result)
        }
    }

    private func applyFinalUpdateCheckResult(_ result: UpdateCheckResult) {
        switch result {
        case .upToDate:
            updatesStatusMessage = String(localized: "settings.updates.status.upToDate")
        case .updateAvailable(let version):
            updatesStatusMessage = String(
                format: String(localized: "settings.updates.status.updateAvailableFormat"),
                version
            )
        case .unavailable:
            updatesStatusMessage = String(localized: "settings.updates.notAvailable")
        case .failed(let message):
            updatesStatusMessage = String(
                format: String(localized: "settings.updates.status.failedFormat"),
                message
            )
        case .checking:
            updatesStatusMessage = String(localized: "settings.updates.checking")
            return
        }

        isCheckingForUpdates = false
        isAwaitingManualUpdateResult = false
    }
}
