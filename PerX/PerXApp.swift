//
//  PerXApp.swift
//  PerX
//
//  Created by Massimo Pernozzoli on 13/11/24.
//

import SwiftUI

@main
struct PerXApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
