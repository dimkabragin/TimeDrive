//
//  TimeDriveApp.swift
//  TimeDrive
//
//  Created by Дмитрий Брагин on 27.03.2026.
//

import SwiftUI
import SwiftData

@main
struct TimeDriveApp: App {
    var sharedModelContainer: ModelContainer = {
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
    }()

    var body: some Scene {
        WindowGroup {
            let appContainer = AppContainer(modelContext: sharedModelContainer.mainContext)
            ContentView(appContainer: appContainer)
        }
        .modelContainer(sharedModelContainer)
    }
}
