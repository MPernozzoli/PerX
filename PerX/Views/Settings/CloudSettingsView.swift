import SwiftUI

struct CloudSettingsView: View {
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Sincronizzazione gestita dal backend", systemImage: "server.rack")
                    .font(.headline)
                Text("CloudKit non e' piu' usato. Per la V1 i dati condivisi passano da Supabase tramite il backend.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}
