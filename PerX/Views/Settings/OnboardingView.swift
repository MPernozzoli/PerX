import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentStep = 0
    @State private var animateIn = false
    
    let steps = OnboardingStep.allSteps
    
    var body: some View {
        ZStack {
            // Background blur
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            // Main content
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Guida Introduttiva")
                        .font(.title2.bold())
                    
                    Spacer()
                    
                    Button {
                        withAnimation {
                            closeOnboarding()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Chiudi")
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                
                Divider()
                
                // Content
                ZStack {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        OnboardingStepView(step: step)
                            .opacity(currentStep == index ? 1.0 : 0.0)
                            .offset(x: offsetForStep(index))
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentStep)
                    }
                }
                .clipped()
                
                Divider()
                
                // Footer
                HStack(spacing: 16) {
                    // Progress indicator
                    HStack(spacing: 6) {
                        ForEach(0..<steps.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                                .frame(width: 8, height: 8)
                                .scaleEffect(index == currentStep ? 1.2 : 1.0)
                                .animation(.spring(response: 0.3), value: currentStep)
                        }
                    }
                    
                    Spacer()
                    
                    // Navigation buttons
                    if currentStep > 0 {
                        Button("Indietro") {
                            withAnimation {
                                currentStep -= 1
                            }
                        }
                    }
                    
                    if currentStep < steps.count - 1 {
                        Button("Avanti") {
                            withAnimation {
                                currentStep += 1
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Inizia") {
                            withAnimation {
                                closeOnboarding()
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
            }
            .frame(width: 800, height: 600)
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            .scaleEffect(animateIn ? 1.0 : 0.95)
            .opacity(animateIn ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                animateIn = true
            }
        }
    }
    
    private func closeOnboarding() {
        OnboardingService.shared.completeOnboarding()
        animateIn = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }
    
    private func offsetForStep(_ index: Int) -> CGFloat {
        let distance = CGFloat(index - currentStep)
        return distance * 50
    }
}

// MARK: - Onboarding Step View

struct OnboardingStepView: View {
    let step: OnboardingStep
    @State private var featuresVisible = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer()
                    .frame(height: 20)
                
                // Icon
                Image(systemName: step.icon)
                    .font(.system(size: 72))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.top, 20)
                
                // Title & Description
                VStack(spacing: 12) {
                    Text(step.title)
                        .font(.system(size: 32, weight: .bold))
                        .multilineTextAlignment(.center)
                    
                    Text(step.description)
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                // Features
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(step.features.enumerated()), id: \.offset) { index, feature in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                            
                            Text(feature)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        .opacity(featuresVisible ? 1.0 : 0.0)
                        .offset(x: featuresVisible ? 0 : -20)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.8)
                                .delay(Double(index) * 0.1),
                            value: featuresVisible
                        )
                    }
                }
                .frame(maxWidth: 500)
                .padding(.horizontal, 40)
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            withAnimation {
                featuresVisible = true
            }
        }
        .onDisappear {
            featuresVisible = false
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(isPresented: .constant(true))
}
