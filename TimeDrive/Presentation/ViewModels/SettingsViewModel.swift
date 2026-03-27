import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var workDurationMinutes: Int = 25
    @Published var breakDurationMinutes: Int = 5
    @Published var autoStartNext: Bool = false
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
        syncEngine: SyncEngine
    ) {
        self.settingsRepository = settingsRepository
        self.syncRepository = syncRepository
        self.timerUseCases = timerUseCases
        self.syncEngine = syncEngine
    }

    func load() {
        do {
            let settings = try settingsRepository.getOrCreate()
            workDurationMinutes = max(1, settings.workDurationSec / 60)
            breakDurationMinutes = max(1, settings.breakDurationSec / 60)
            autoStartNext = settings.autoStartNext

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

    func syncNow() {
        guard !isSyncingNow else { return }
        isSyncingNow = true
        errorMessage = nil

        Swift.Task { @MainActor in
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
}
