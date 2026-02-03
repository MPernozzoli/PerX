//
//  ExpandablePills.swift
//  PerX per iPad
//
//  Componenti pill espandibili con popover per la lista sinistri
//  Stile identico alla versione Mac
//

import SwiftUI

// MARK: - Stato Pill

struct ExpandableStatoPill: View {
    let stato: String
    let onChangeStato: ((StatoSinistro) -> Void)?
    
    @State private var showPopover = false
    
    private var statoEnum: StatoSinistro? {
        StatoSinistro.from(descrizione: stato)
    }
    
    private var statoColor: Color {
        statoEnum?.color ?? .gray
    }
    
    private var statoIcon: String {
        statoEnum?.icon ?? "questionmark.circle"
    }
    
    private var validTransitions: [StatoSinistro] {
        statoEnum?.validTransitions ?? []
    }
    
    var body: some View {
        Button {
            showPopover = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: statoIcon)
                    .font(.system(size: 10))
                Text(stato)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(LinearGradient(colors: [statoColor, statoColor.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: statoColor.opacity(0.3), radius: 3, y: 2)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover) {
            statoPopoverContent
                .presentationCompactAdaptation(.popover)
        }
    }
    
    @ViewBuilder
    private var statoPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stato Sinistro")
                        .font(.system(size: 14, weight: .semibold))
                }
                Spacer()
                
                // Badge stato attuale
                HStack(spacing: 4) {
                    Image(systemName: statoIcon)
                        .font(.system(size: 10))
                    Text(stato)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(statoColor)
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(colors: [statoColor.opacity(0.15), Color.clear], startPoint: .top, endPoint: .bottom)
            )
            
            Divider()
            
            // Transizioni valide
            if !validTransitions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TRANSIZIONI VALIDE")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                    
                    ForEach(validTransitions) { newStato in
                        Button {
                            showPopover = false
                            onChangeStato?(newStato)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: newStato.icon)
                                    .foregroundColor(newStato.color)
                                    .frame(width: 20)
                                Text(newStato.descrizione)
                                    .font(.system(size: 12))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(Color.gray.opacity(0.001))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            
            Divider()
            
            // Altri stati
            DisclosureGroup("Altri stati") {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(StatoSinistro.allCases.filter { !validTransitions.contains($0) && $0 != statoEnum }) { newStato in
                        Button {
                            showPopover = false
                            onChangeStato?(newStato)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: newStato.icon)
                                    .foregroundColor(newStato.color.opacity(0.6))
                                    .frame(width: 20)
                                Text(newStato.descrizione)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .font(.system(size: 12))
            .padding(12)
        }
        .frame(width: 300)
    }
}

// MARK: - Priority Pill

struct ExpandablePriorityPill: View {
    let priorityValue: Double       // Priorità effettiva (0-100)
    let hasManualPriority: Bool     // True se è un override manuale
    let onChangePriority: ((PriorityLevel) -> Void)?
    
    @State private var showPopover = false
    
    /// Inizializzatore compatibile con SinistroMinimal
    init(priorityValue: Double?, hasManualPriority: Bool = false, onChangePriority: ((PriorityLevel) -> Void)? = nil) {
        self.priorityValue = priorityValue ?? 0
        self.hasManualPriority = hasManualPriority
        self.onChangePriority = onChangePriority
    }
    
    private var level: PriorityLevel {
        PriorityLevel.from(value: priorityValue)
    }
    
    private var priorityColor: Color {
        switch priorityValue {
        case 0..<20: return .green
        case 20..<40: return .yellow
        case 40..<60: return .orange
        case 60..<80: return .purple
        default: return .red
        }
    }
    
    private var fontWeight: Font.Weight {
        switch priorityValue {
        case ..<25: return .regular
        case 25..<60: return .medium
        case 60..<80: return .semibold
        default: return .bold
        }
    }
    
    var body: some View {
        Button {
            showPopover = true
        } label: {
            HStack(spacing: 4) {
                // Mostra la label della priorità effettiva, MAI "Auto"
                Text(level.rawValue)
                    .font(.system(size: 11, weight: fontWeight))
                
                // Icona manina se priorità manuale
                if hasManualPriority {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(priorityColor.opacity(0.15))
            )
            .overlay(Capsule().stroke(priorityColor.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover) {
            priorityPopoverContent
                .presentationCompactAdaptation(.popover)
        }
    }
    
    @ViewBuilder
    private var priorityPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                ZStack {
                    Circle()
                        .fill(priorityColor.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Circle()
                        .fill(priorityColor)
                        .frame(width: 12, height: 12)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Priorità")
                        .font(.system(size: 14, weight: .semibold))
                    HStack(spacing: 4) {
                        Text(level.rawValue)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("(\(Int(priorityValue))%)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        if hasManualPriority {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(14)
            .background(
                LinearGradient(colors: [priorityColor.opacity(0.1), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            
            Divider()
            
            // Selezione livello
            VStack(alignment: .leading, spacing: 4) {
                Text("IMPOSTA PRIORITÀ")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                ForEach(PriorityLevel.allCases, id: \.self) { lvl in
                    Button {
                        showPopover = false
                        onChangePriority?(lvl)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(lvl.color)
                                .frame(width: 12, height: 12)
                            
                            Text(lvl.rawValue)
                                .font(.system(size: 12))
                            
                            Spacer()
                            
                            if lvl == level {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                        .background(lvl == level ? Color.accentColor.opacity(0.1) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .frame(width: 220)
    }
}

// MARK: - Complessità Pill

struct ExpandableComplessitaPill: View {
    let complessita: String?
    let onChangeComplessita: ((GradoComplessita) -> Void)?
    
    @State private var showPopover = false
    
    private var grado: GradoComplessita {
        GradoComplessita.from(text: complessita)
    }
    
    var body: some View {
        if grado == .unknown {
            Text("-")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        } else {
            Button {
                showPopover = true
            } label: {
                Text(grado.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.gray.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover) {
                complessitaPopoverContent
                    .presentationCompactAdaptation(.popover)
            }
        }
    }
    
    @ViewBuilder
    private var complessitaPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Complessità")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(grado.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(grado.color)
            }
            .padding(14)
            .background(grado.color.opacity(0.1))
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(GradoComplessita.allCases.filter { $0 != .unknown }, id: \.self) { g in
                    Button {
                        showPopover = false
                        onChangeComplessita?(g)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(g.color)
                                .frame(width: 12, height: 12)
                            
                            Text(g.rawValue)
                                .font(.system(size: 12))
                            
                            Spacer()
                            
                            if g == grado {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                        .background(g == grado ? Color.accentColor.opacity(0.1) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .frame(width: 200)
    }
}

// MARK: - Beni Pill

struct ExpandableBeniPill: View {
    let beniCount: Int
    let beniList: [String]
    
    @State private var showPopover = false
    
    var body: some View {
        if beniCount == 0 {
            Text("-")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        } else {
            Button {
                showPopover = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cube.box.fill")
                        .font(.system(size: 9))
                    Text("\(beniCount)")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.gray.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover) {
                beniPopoverContent
                    .presentationCompactAdaptation(.popover)
            }
        }
    }
    
    @ViewBuilder
    private var beniPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Beni Coinvolti")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(beniCount)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blue)
            }
            .padding(14)
            .background(
                LinearGradient(colors: [Color.blue.opacity(0.1), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            
            Divider()
            
            if beniList.isEmpty {
                Text("Dettagli beni non disponibili")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(beniList.indices, id: \.self) { idx in
                            HStack(spacing: 8) {
                                Image(systemName: "cube.box")
                                    .font(.system(size: 10))
                                    .foregroundColor(.blue)
                                Text(beniList[idx])
                                    .font(.system(size: 12))
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 200)
            }
        }
        .frame(width: 280)
    }
}

// MARK: - Solleciti Pill

struct ExpandableSollecitiPill: View {
    let sollecitiCount: Int
    let sollecitiList: [SollecitoInfo]
    
    @State private var showPopover = false
    
    private var pillColor: Color {
        guard sollecitiCount > 0 else { return .secondary }
        if sollecitiCount >= 3 { return .red }
        if sollecitiCount >= 2 { return .orange }
        return .yellow
    }
    
    var body: some View {
        if sollecitiCount == 0 {
            Text("-")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        } else {
            Button {
                showPopover = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 9))
                    Text("\(sollecitiCount)")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(pillColor.opacity(0.15))
                )
                .overlay(Capsule().stroke(pillColor.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover) {
                sollecitiPopoverContent
                    .presentationCompactAdaptation(.popover)
            }
        }
    }
    
    @ViewBuilder
    private var sollecitiPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Solleciti Ricevuti")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(sollecitiCount)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.red)
            }
            .padding(14)
            .background(
                LinearGradient(colors: [Color.red.opacity(0.1), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            
            Divider()
            
            if sollecitiList.isEmpty {
                Text("Dettagli solleciti non disponibili")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(sollecitiList) { sollecito in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "bell.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.red)
                                    Text(sollecito.mittente)
                                        .font(.system(size: 12, weight: .medium))
                                    Spacer()
                                    Text(sollecito.data, style: .date)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                if let note = sollecito.note {
                                    Text(note)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                            
                            if sollecito.id != sollecitiList.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 200)
            }
        }
        .frame(width: 300)
    }
}

struct SollecitoInfo: Identifiable {
    let id = UUID()
    let data: Date
    let mittente: String
    let note: String?
}

// MARK: - Task Pill

struct ExpandableTaskPill: View {
    let taskCount: Int
    let taskList: [TaskInfo]
    
    @State private var showPopover = false
    
    var body: some View {
        if taskCount == 0 {
            Text("-")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        } else {
            Button {
                showPopover = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                        .font(.system(size: 9))
                    Text("\(taskCount)")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.purple)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.purple.opacity(0.15))
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover) {
                taskPopoverContent
                    .presentationCompactAdaptation(.popover)
            }
        }
    }
    
    @ViewBuilder
    private var taskPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Task Attive")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(taskCount)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.purple)
            }
            .padding(14)
            .background(
                LinearGradient(colors: [Color.purple.opacity(0.1), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            
            Divider()
            
            if taskList.isEmpty {
                Text("Dettagli task non disponibili")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(taskList) { task in
                            HStack(spacing: 8) {
                                Image(systemName: task.isInProgress ? "play.circle.fill" : "circle")
                                    .font(.system(size: 14))
                                    .foregroundColor(task.isInProgress ? .blue : .gray)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .font(.system(size: 12, weight: .medium))
                                    if let due = task.dueDate {
                                        Text("Scadenza: \(due, style: .date)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            
                            if task.id != taskList.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 200)
            }
        }
        .frame(width: 280)
    }
}

struct TaskInfo: Identifiable {
    let id = UUID()
    let title: String
    let dueDate: Date?
    let isInProgress: Bool
}
