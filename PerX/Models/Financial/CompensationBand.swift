import Foundation

struct CompensationBand: Codable, Identifiable {
    var id = UUID()
    var name: String
    var minSinistri: Int
    var incentivo: Double
    var compensoBase: Double
    var compensoOltre10: Double
}

struct ThresholdCompensation: Codable, Identifiable {
    var id = UUID()
    var threshold: Int  // es: 10000 per "Oltre i 10K"
    var amount: Double
}

class CompensationSettings: ObservableObject {
    @Published var bands: [CompensationBand] = []
    @Published var thresholds: [ThresholdCompensation] = []
    
    init() {
        loadSettings()
    }
    
    private func loadSettings() {
        if let savedBands = UserDefaults.standard.data(forKey: "compensationBands"),
           let decoded = try? JSONDecoder().decode([CompensationBand].self, from: savedBands) {
            bands = decoded
        } else {
            // Valori di default - compensoOltre10 è FISSO (non subisce il moltiplicatore della fascia)
            bands = [
                CompensationBand(name: "Base", minSinistri: 0, incentivo: 0.0, compensoBase: 25.00, compensoOltre10: 40.00),
                CompensationBand(name: "1", minSinistri: 50, incentivo: 0.10, compensoBase: 27.50, compensoOltre10: 40.00),
                CompensationBand(name: "2", minSinistri: 90, incentivo: 0.15, compensoBase: 28.75, compensoOltre10: 40.00),
                CompensationBand(name: "3", minSinistri: 100, incentivo: 0.20, compensoBase: 30.00, compensoOltre10: 40.00),
                CompensationBand(name: "4", minSinistri: 130, incentivo: 0.25, compensoBase: 31.25, compensoOltre10: 40.00)
            ]
        }
        
        if let savedThresholds = UserDefaults.standard.data(forKey: "compensationThresholds"),
           let decoded = try? JSONDecoder().decode([ThresholdCompensation].self, from: savedThresholds) {
            thresholds = decoded
        } else {
            // Valori di default come da screenshot
            thresholds = [
                ThresholdCompensation(threshold: 10000, amount: 100.00),
                ThresholdCompensation(threshold: 20000, amount: 200.00),
                ThresholdCompensation(threshold: 30000, amount: 300.00),
                ThresholdCompensation(threshold: 40000, amount: 400.00),
                ThresholdCompensation(threshold: 50000, amount: 500.00)
            ]
        }
    }
    
    func saveSettings() {
        if let encoded = try? JSONEncoder().encode(bands) {
            UserDefaults.standard.set(encoded, forKey: "compensationBands")
        }
        if let encoded = try? JSONEncoder().encode(thresholds) {
            UserDefaults.standard.set(encoded, forKey: "compensationThresholds")
        }
    }
    
    func addBand(_ band: CompensationBand) {
        bands.append(band)
        saveSettings()
    }
    
    func updateBand(_ band: CompensationBand) {
        if let index = bands.firstIndex(where: { $0.id == band.id }) {
            bands[index] = band
            saveSettings()
        }
    }
    
    func addThreshold(_ threshold: ThresholdCompensation) {
        thresholds.append(threshold)
        saveSettings()
    }
    
    func updateThreshold(_ threshold: ThresholdCompensation) {
        if let index = thresholds.firstIndex(where: { $0.id == threshold.id }) {
            thresholds[index] = threshold
            saveSettings()
        }
    }
    
    func removeBand(_ band: CompensationBand) {
        bands.removeAll { $0.id == band.id }
        saveSettings()
    }
    
    func removeThreshold(_ threshold: ThresholdCompensation) {
        thresholds.removeAll { $0.id == threshold.id }
        saveSettings()
    }
} 