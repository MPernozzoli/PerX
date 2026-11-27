import AppKit
import Foundation

/// Worker della Regia sul Mac: prende un lavoro alla volta e lo riporta.
/// I livelli sopra L0 restano in coda finché il modello non è disponibile, senza aprire una Questione.
@MainActor
final class RegiaWorker {
    static let shared = RegiaWorker()

    private var task: Task<Void, Never>?
    private let workerId = "mac-\(Host.current().localizedName ?? "perx")"

    func start() {
        guard task == nil else { return }
        task = Task { await loop() }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func loop() async {
        while !Task.isCancelled {
            await tick()
            try? await Task.sleep(nanoseconds: 20_000_000_000)
        }
    }

    private func tick() async {
        struct Body: Encodable {
            let worker_id: String
            let mac_idle: Bool
        }
        struct Input: Decodable {
            let liquidabile: String?
            let classe: String?
            let iban: String?

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let text = try? container.decode(String.self, forKey: .liquidabile) {
                    liquidabile = text
                } else if let number = try? container.decode(Double.self, forKey: .liquidabile) {
                    liquidabile = String(number)
                } else {
                    liquidabile = nil
                }
                classe = try container.decodeIfPresent(String.self, forKey: .classe)
                iban = try container.decodeIfPresent(String.self, forKey: .iban)
            }

            enum CodingKeys: String, CodingKey {
                case liquidabile, classe, iban
            }
        }
        struct Job: Decodable {
            let id: String
            let job_type: String
            let model_level: String?
            let input_json: Input
        }
        struct Response: Decodable {
            let job: Job?
        }
        struct Esito: Encodable {
            let worker_id: String
            let ok: Bool
            let output: [String: String]
            let model_level: String?
            let duration_ms: Int
            let rinviato: Bool
            let error: String?
        }
        struct Done: Decodable { let id: String }

        let started = Date()
        let response: Response
        do {
            response = try await BackendAPIClient.shared.post(
                "regia/lavori/prendi",
                body: Body(worker_id: workerId, mac_idle: !NSApp.isActive)
            )
        } catch {
            return
        }
        guard let job = response.job else { return }
        let level = job.model_level ?? "L0"
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        let esito: Esito
        if level == "L0" {
            var output: [String: String] = [:]
            if let value = job.input_json.liquidabile { output["liquidabile"] = value }
            if let value = job.input_json.classe { output["classe"] = value }
            if let value = job.input_json.iban { output["iban"] = value }
            esito = Esito(
                worker_id: workerId,
                ok: !output.isEmpty,
                output: output,
                model_level: level,
                duration_ms: elapsed,
                rinviato: false,
                error: output.isEmpty ? "manca il risultato L0" : nil
            )
        } else {
            esito = Esito(
                worker_id: workerId,
                ok: false,
                output: [:],
                model_level: level,
                duration_ms: elapsed,
                rinviato: true,
                error: "modello non disponibile"
            )
        }
        _ = try? await BackendAPIClient.shared.post("regia/lavori/\(job.id)/esito", body: esito) as Done
    }
}
