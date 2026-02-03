import SwiftUI

struct MonthPickerView: View {
    @Binding var selectedMonth: Date
    @Binding var isPresented: Bool
    let onConfirm: () -> Void
    
    @State private var selectedYear: Int
    @State private var selectedMonthIndex: Int
    
    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }
    
    private var years: [Int] {
        Array(2020...currentYear + 1)
    }
    
    private let months = ["Gennaio", "Febbraio", "Marzo", "Aprile", "Maggio", "Giugno",
                         "Luglio", "Agosto", "Settembre", "Ottobre", "Novembre", "Dicembre"]
    
    init(selectedMonth: Binding<Date>, isPresented: Binding<Bool>, onConfirm: @escaping () -> Void) {
        self._selectedMonth = selectedMonth
        self._isPresented = isPresented
        self.onConfirm = onConfirm
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: selectedMonth.wrappedValue)
        let currentYear = calendar.component(.year, from: Date())
        self._selectedYear = State(initialValue: components.year ?? currentYear)
        self._selectedMonthIndex = State(initialValue: (components.month ?? 1) - 1)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Seleziona il mese da cui importare i bonus")
                    .font(.headline)
                    .padding()
                
                HStack(spacing: 30) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Anno")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Picker("Anno", selection: $selectedYear) {
                            ForEach(years, id: \.self) { year in
                                Text("\(year)").tag(year)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Mese")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Picker("Mese", selection: $selectedMonthIndex) {
                            ForEach(0..<months.count, id: \.self) { index in
                                Text(months[index]).tag(index)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }
                }
                .padding()
                
                Spacer()
            }
            .navigationTitle("Seleziona Mese")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importa") {
                        updateSelectedMonth()
                        onConfirm()
                    }
                }
            }
        }
        .frame(width: 400, height: 300)
    }
    
    private func updateSelectedMonth() {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = selectedYear
        components.month = selectedMonthIndex + 1
        components.day = 1
        if let date = calendar.date(from: components) {
            selectedMonth = date
        }
    }
}

