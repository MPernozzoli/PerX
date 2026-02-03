//
//  PerX_LiteApp.swift
//  PerX Lite
//
//  Created by Massimo Pernozzoli on 21/01/26.
//

import SwiftUI
import CoreData

@main
struct PerX_LiteApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
