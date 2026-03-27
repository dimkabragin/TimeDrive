//
//  ContentView.swift
//  TimeDrive
//
//  Created by Дмитрий Брагин on 27.03.2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    private let appContainer: AppContainer

    init(appContainer: AppContainer) {
        self.appContainer = appContainer
    }

    var body: some View {
        TimerDashboardView(appContainer: appContainer)
    }
}

#Preview {
    let previewContainer = try! ModelContainer(
        for: Project.self,
        Task.self,
        TimerSettings.self,
        TimerSession.self,
        TimerState.self,
        TimeEvent.self,
        SyncOperation.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let appContainer = AppContainer(modelContext: previewContainer.mainContext)
    return ContentView(appContainer: appContainer)
}
