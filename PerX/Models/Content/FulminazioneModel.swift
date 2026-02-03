import Foundation
import CoreLocation

struct FulminazioneModel {
    var coordinate: CLLocationCoordinate2D
    var indirizzo: String
    var dataSinistro: Date
    
    struct FulminazioneData: Identifiable {
        let id = UUID()
        let data: Date
        var entro1km: Bool = false
        var entro3km: Bool = false
        var entro5km: Bool = false
        var entro10km: Bool = false
    }
    
    var dateAnalisi: [FulminazioneData] {
        let calendar = Calendar.current
        let dataSinistro = calendar.startOfDay(for: self.dataSinistro)
        
        return (-5...5).map { offset in
            if let date = calendar.date(byAdding: .day, value: offset, to: dataSinistro) {
                return FulminazioneData(data: date)
            }
            return FulminazioneData(data: dataSinistro)
        }
    }
} 