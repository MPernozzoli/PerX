import SwiftUI

struct WhatsNewView: View {
    @StateObject private var whatsNewService = WhatsNewService.shared
    @Binding var isPresented: Bool
    @State private var currentFeatureIndex = 0
    @State private var animateFeatures = false
    @State private var showButton = false
    
    var body: some View {
        ZStack {
            // Background con gradiente
            LinearGradient(
                colors: [
                    Color.purple.opacity(0.3),
                    Color.blue.opacity(0.2),
                    Color.indigo.opacity(0.3)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    // Emoji animata
                    Text("🎉")
                        .font(.system(size: 80))
                        .scaleEffect(animateFeatures ? 1.0 : 0.5)
                        .rotationEffect(.degrees(animateFeatures ? 0 : -20))
                    
                    Text("Novità in PerX")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    
                    if let update = whatsNewService.latestUpdate {
                        Text("Versione \(update.version)")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 60)
                .padding(.bottom, 40)
                .opacity(animateFeatures ? 1 : 0)
                .offset(y: animateFeatures ? 0 : -20)
                
                // Features grid
                if let update = whatsNewService.latestUpdate {
                    ScrollView {
                        VStack(spacing: 40) {
                            // Features
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 20),
                                    GridItem(.flexible(), spacing: 20)
                                ],
                                spacing: 20
                            ) {
                                ForEach(Array(update.features.enumerated()), id: \.element.id) { index, feature in
                                    FeatureCard(feature: feature)
                                        .opacity(animateFeatures ? 1 : 0)
                                        .offset(y: animateFeatures ? 0 : 30)
                                        .animation(
                                            .spring(response: 0.6, dampingFraction: 0.8)
                                            .delay(Double(index) * 0.1),
                                            value: animateFeatures
                                        )
                                }
                            }
                            
                            // Known Problems
                            if let problems = update.knownProblems, !problems.isEmpty {
                                VStack(spacing: 16) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text("Problemi Noti")
                                            .font(.title2.bold())
                                        Spacer()
                                    }
                                    .opacity(animateFeatures ? 1 : 0)
                                    
                                    VStack(spacing: 12) {
                                        ForEach(Array(problems.enumerated()), id: \.element.id) { index, problem in
                                            KnownProblemRow(problem: problem)
                                                .opacity(animateFeatures ? 1 : 0)
                                                .offset(x: animateFeatures ? 0 : -20)
                                                .animation(
                                                    .spring(response: 0.5, dampingFraction: 0.8)
                                                    .delay(0.6 + Double(index) * 0.08),
                                                    value: animateFeatures
                                                )
                                        }
                                    }
                                }
                                .padding(.top, 20)
                            }
                            
                            // What's Next
                            if let whatsNext = update.whatsNext, !whatsNext.isEmpty {
                                VStack(spacing: 16) {
                                    HStack {
                                        Image(systemName: "sparkles")
                                            .foregroundColor(.purple)
                                        Text("In Arrivo")
                                            .font(.title2.bold())
                                        Spacer()
                                    }
                                    .opacity(animateFeatures ? 1 : 0)
                                    
                                    LazyVGrid(
                                        columns: [
                                            GridItem(.flexible(), spacing: 16),
                                            GridItem(.flexible(), spacing: 16),
                                            GridItem(.flexible(), spacing: 16)
                                        ],
                                        spacing: 16
                                    ) {
                                        ForEach(Array(whatsNext.enumerated()), id: \.element.id) { index, item in
                                            WhatsNextCard(item: item)
                                                .opacity(animateFeatures ? 1 : 0)
                                                .offset(y: animateFeatures ? 0 : 20)
                                                .animation(
                                                    .spring(response: 0.5, dampingFraction: 0.8)
                                                    .delay(0.8 + Double(index) * 0.08),
                                                    value: animateFeatures
                                                )
                                        }
                                    }
                                }
                                .padding(.top, 20)
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 20)
                    }
                }
                
                // Bottom button
                VStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            if let update = whatsNewService.latestUpdate {
                                whatsNewService.markUpdateAsSeen(update.id)
                            }
                            isPresented = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text("Iniziamo!")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: 300)
                        .frame(height: 50)
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(25)
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(showButton ? 1.0 : 0.8)
                    .opacity(showButton ? 1 : 0)
                    
                    Button("Ricordamelo dopo") {
                        isPresented = false
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .opacity(showButton ? 1 : 0)
                }
                .padding(.vertical, 30)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                animateFeatures = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    showButton = true
                }
            }
        }
    }
}

struct FeatureCard: View {
    let feature: AppUpdate.Feature
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Icon
            HStack {
                Image(systemName: feature.icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(feature.colorValue)
                    .frame(width: 50, height: 50)
                    .background(
                        Circle()
                            .fill(feature.colorValue.opacity(0.15))
                    )
                
                Spacer()
            }
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                Text(feature.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                
                Text(feature.description)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 200)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(
                    color: feature.colorValue.opacity(isHovered ? 0.3 : 0.1),
                    radius: isHovered ? 20 : 10,
                    x: 0,
                    y: isHovered ? 8 : 4
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }
}

struct KnownProblemRow: View {
    let problem: AppUpdate.KnownProblem
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: problem.icon)
                .font(.system(size: 16))
                .foregroundColor(.orange)
                .frame(width: 24)
            
            Text(problem.description)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.08))
        )
    }
}

struct WhatsNextCard: View {
    let item: AppUpdate.WhatsNext
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 28))
                .foregroundColor(.purple)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(item.description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 140)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(
                    color: Color.purple.opacity(isHovered ? 0.2 : 0.08),
                    radius: isHovered ? 12 : 6,
                    x: 0,
                    y: isHovered ? 4 : 2
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.purple.opacity(0.1), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }
}

// Preview
struct WhatsNewView_Previews: PreviewProvider {
    static var previews: some View {
        WhatsNewView(isPresented: .constant(true))
            .frame(width: 900, height: 700)
    }
}
