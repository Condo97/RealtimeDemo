//
//  RealtimeDemoApp.swift
//  RealtimeDemo
//
//  Created by Alex Coundouriotis on 11/8/24.
//

import SwiftUI

@main
struct RealtimeDemoApp: App {
//    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
//                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
