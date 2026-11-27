import SwiftUI

struct SalaRegiaView: View {
    @State private var questions: [RegiaQuestionDTO] = []
    @State private var jobs: [RegiaJobDTO] = []
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Sala regia")
                    .font(.largeTitle.weight(.semibold))
                Text("Gli agenti lavorano le pratiche. Qui restano le decisioni: questioni, approvazioni e lo stato scelto a mano.")
                    .foregroundStyle(.secondary)

                section(title: "In corso", isEmpty: jobs.isEmpty, empty: "Nessun lavoro aperto.") {
                    ForEach(jobs) { job in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(job.job_type)
                                .font(.headline)
                            Text([job.phase, job.resource, job.model_level].compactMap { $0 }.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                section(title: "Questioni", isEmpty: questions.isEmpty, empty: "Nessuna questione aperta.") {
                    ForEach(questions) { question in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(question.question_type.replacingOccurrences(of: "_", with: " "))
                                .font(.headline)
                            Text(question.description)
                            if let recommendation = question.recommendation, !recommendation.isEmpty {
                                Text(recommendation)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .task { await reload() }
    }

    @ViewBuilder
    private func section(title: String, isEmpty: Bool, empty: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
            if isEmpty {
                Text(empty)
                    .foregroundStyle(.secondary)
            } else {
                content()
            }
        }
    }

    private func reload() async {
        do {
            questions = try await BackendAPIClient.shared.get("regia/questioni", queryItems: [URLQueryItem(name: "stato", value: "aperta")])
            jobs = try await BackendAPIClient.shared.get("regia/lavori")
            message = nil
        } catch {
            message = "La sala regia si aggiorna quando il backend risponde."
        }
    }
}

private struct RegiaQuestionDTO: Decodable, Identifiable {
    let id: String
    let question_type: String
    let description: String
    let recommendation: String?
}

private struct RegiaJobDTO: Decodable, Identifiable {
    let id: String
    let job_type: String
    let phase: String?
    let resource: String?
    let model_level: String?
}
