import Foundation
import CoreData

extension Sinistro {
    
    /// Valida se due date sono nello stesso giorno (ignorando l'ora)
    private func isSameDay(_ date1: Date?, _ date2: Date?) -> Bool {
        guard let date1 = date1, let date2 = date2 else { return false }
        let calendar = Calendar.current
        return calendar.isDate(date1, inSameDayAs: date2)
    }
    
    /// Verifica se una data è precedente a un'altra (escludendo lo stesso giorno)
    private func isBefore(_ date1: Date?, _ date2: Date?) -> Bool {
        guard let date1 = date1, let date2 = date2 else { return false }
        return date1 < date2 && !isSameDay(date1, date2)
    }
    
    /// Verifica se una data è successiva a un'altra (escludendo lo stesso giorno)
    private func isAfter(_ date1: Date?, _ date2: Date?) -> Bool {
        guard let date1 = date1, let date2 = date2 else { return false }
        return date1 > date2 && !isSameDay(date1, date2)
    }
    
    // MARK: - Validazione Data Denuncia
    
    /// Valida e imposta la data denuncia con vincoli di sicurezza
    /// - Data denuncia non può essere precedente a data sinistro (stesso giorno ok)
    func setDataDenuncia(_ newDate: Date?) {
        guard let newDate = newDate else {
            dataDenuncia = nil
            return
        }
        
        // Verifica: data denuncia non può essere precedente a data sinistro
        if let dataSinistro = dataSinistro, isBefore(newDate, dataSinistro) {
            print("[Sinistro] ⚠️ Data denuncia (\(newDate)) rifiutata: precedente a data sinistro (\(dataSinistro))")
            dataDenuncia = nil
            return
        }
        
        dataDenuncia = newDate
    }
    
    // MARK: - Validazione Data Sinistro
    
    /// Valida e imposta la data sinistro con vincoli di sicurezza
    /// - Data sinistro non può essere successiva a data denuncia (stesso giorno ok)
    func setDataSinistro(_ newDate: Date?) {
        guard let newDate = newDate else {
            dataSinistro = nil
            return
        }
        
        // Verifica: data sinistro non può essere successiva a data denuncia
        if let dataDenuncia = dataDenuncia, isAfter(newDate, dataDenuncia) {
            print("[Sinistro] ⚠️ Data sinistro (\(newDate)) rifiutata: successiva a data denuncia (\(dataDenuncia))")
            dataSinistro = nil
            return
        }
        
        dataSinistro = newDate
    }
    
    // MARK: - Validazione Data Assegnazione
    
    /// Valida e imposta la data assegnazione con vincoli di sicurezza
    /// - Data assegnazione non può essere precedente a data incarico (se presente)
    /// - Data assegnazione non può essere successiva a data invio atto o data chiusura (se presenti)
    func setDataAssegnazione(_ newDate: Date?) {
        guard let newDate = newDate else {
            dataAssegnazione = nil
            return
        }
        
        // Verifica: data assegnazione non può essere precedente a data incarico
        if let dataIncarico = dataIncarico, isBefore(newDate, dataIncarico) {
            print("[Sinistro] ⚠️ Data assegnazione (\(newDate)) rifiutata: precedente a data incarico (\(dataIncarico))")
            dataAssegnazione = nil
            return
        }
        
        // Verifica: data assegnazione non può essere successiva a data invio atto (se presente)
        if let dataInvioAtto = dataInvioAtto, isAfter(newDate, dataInvioAtto) {
            print("[Sinistro] ⚠️ Data assegnazione (\(newDate)) rifiutata: successiva a data invio atto (\(dataInvioAtto))")
            dataAssegnazione = nil
            return
        }
        
        // Verifica: data assegnazione non può essere successiva a data chiusura (se presente)
        if let dataChiusura = dataChiusura, isAfter(newDate, dataChiusura) {
            print("[Sinistro] ⚠️ Data assegnazione (\(newDate)) rifiutata: successiva a data chiusura (\(dataChiusura))")
            dataAssegnazione = nil
            return
        }
        
        dataAssegnazione = newDate
    }
    
    // MARK: - Validazione incrociata
    
    /// Valida tutte le date dopo una modifica per mantenere la coerenza
    /// Chiamare questo metodo dopo aver modificato una data per verificare che tutte le altre siano ancora valide
    func validateAllDates() {
        // Se data denuncia è stata modificata, verifica che sia ancora valida
        if let dataDenuncia = dataDenuncia {
            let temp = dataDenuncia
            self.dataDenuncia = nil
            setDataDenuncia(temp)
        }
        
        // Se data sinistro è stata modificata, verifica che sia ancora valida
        if let dataSinistro = dataSinistro {
            let temp = dataSinistro
            self.dataSinistro = nil
            setDataSinistro(temp)
        }
        
        // Se data assegnazione è stata modificata, verifica che sia ancora valida
        if let dataAssegnazione = dataAssegnazione {
            let temp = dataAssegnazione
            self.dataAssegnazione = nil
            setDataAssegnazione(temp)
        }
        
        // Se data incarico è stata modificata, potrebbe invalidare data assegnazione
        if let dataIncarico = dataIncarico, let dataAssegnazione = dataAssegnazione {
            if isBefore(dataAssegnazione, dataIncarico) {
                print("[Sinistro] ⚠️ Data assegnazione invalidata da modifica data incarico")
                self.dataAssegnazione = nil
            }
        }
        
        // Se data invio atto è stata modificata, potrebbe invalidare data assegnazione
        if let dataInvioAtto = dataInvioAtto, let dataAssegnazione = dataAssegnazione {
            if isAfter(dataAssegnazione, dataInvioAtto) {
                print("[Sinistro] ⚠️ Data assegnazione invalidata da modifica data invio atto")
                self.dataAssegnazione = nil
            }
        }
        
        // Se data chiusura è stata modificata, potrebbe invalidare data assegnazione
        if let dataChiusura = dataChiusura, let dataAssegnazione = dataAssegnazione {
            if isAfter(dataAssegnazione, dataChiusura) {
                print("[Sinistro] ⚠️ Data assegnazione invalidata da modifica data chiusura")
                self.dataAssegnazione = nil
            }
        }
    }
}
