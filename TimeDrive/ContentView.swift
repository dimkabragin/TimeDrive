//
//  ContentView.swift
//  TimeDrive
//
//  Created by Дмитрий Брагин on 27.03.2026.
//

import SwiftUI
import SwiftData
import AppKit

struct ContentView: View {
    private let appContainer: AppContainer
    private let onWindowReady: (NSWindow) -> Void

    init(appContainer: AppContainer, onWindowReady: @escaping (NSWindow) -> Void) {
        self.appContainer = appContainer
        self.onWindowReady = onWindowReady
    }

    var body: some View {
        TimerDashboardView(
            appContainer: appContainer,
            onWindowReady: onWindowReady
        )
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
    return ContentView(appContainer: appContainer, onWindowReady: { _ in })
}
