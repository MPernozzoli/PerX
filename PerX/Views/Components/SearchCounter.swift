import SwiftUI

struct SearchCounter: View {
    @Binding var searchText: String
    @Binding var searchInFilteredOnly: Bool
    @Binding var isExpanded: Bool
    @FocusState var isFocused: Bool
    
    var body: some View {
        Button {
            withAnimation(.spring()) {
                isExpanded.toggle()
                if !isExpanded {
                    searchText = ""
                }
            }
        } label: {
            HStack(spacing: 8) {
                if isExpanded {
                    TextField("Cerca...", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .frame(width: 180)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    
                    Button {
                        searchInFilteredOnly.toggle()
                    } label: {
                        Image(systemName: searchInFilteredOnly ? "eye" : "eye.slash")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
                
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.blue)
            }
        }
        .buttonStyle(.plain)
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
        }
    }
} 