import SwiftUI
import CoreData

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Sinistro.riferimento, ascending: true)],
        predicate: NSPredicate(format: "stato == %@", "Da Scaricare"),
        animation: .default
    ) private var nuoviSinistri: FetchedResults<Sinistro>
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    // Sezione principale in alto
                    Section {
                        ForEach([SidebarItem.dashboard, SidebarItem.sinistri, SidebarItem.comunicazioni]) { item in
                            sidebarRow(for: item)
                        }
                    }
                }
                .frame(height: 120)  // Altezza fissa per la sezione in alto
                
                Spacer(minLength: 200)  // Spazio minimo prima della sezione in basso
                
                // Consuntivo e Impostazioni in fondo
                List(selection: $selection) {
                    Section {
                        sidebarRow(for: .consuntivo)
                        sidebarRow(for: .impostazioni)
                    }
                }
                .frame(height: 100)  // Altezza fissa per la sezione in basso
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 200)
        }
    }
    
    private func sidebarRow(for item: SidebarItem) -> some View {
        NavigationLink(value: item) {
            HStack {
                Image(systemName: item.icon)
                Text(item.rawValue)
                if item == .sinistri && !nuoviSinistri.isEmpty {
                    Spacer()
                    Text("\(nuoviSinistri.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.gray.opacity(0.2))
                        )
                }
            }
        }
        .tag(item)
    }
}

struct SidebarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ?
                Color.gray.opacity(0.2) :
                Color.clear
            )
            .contentShape(Rectangle())
    }
}

#Preview {
    SidebarView(selection: .constant(.dashboard))
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
} 