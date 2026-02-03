import Foundation
import SwiftUI
import AppKit

/// Service per la generazione del PDF del report annuale
@MainActor
class ConsuntivoPDFService {
    static let shared = ConsuntivoPDFService()
    
    private init() {}
    
    /// Genera il PDF del report annuale
    func generateYearlyReportPDF(
        year: Int,
        yearlyClosedClaims: [Sinistro],
        yearlySentReports: [Sinistro],
        yearlyAssignedClaims: [Sinistro],
        monthlyBreakdown: [MonthlyBreakdownData],
        companyBreakdown: [CompanyBreakdownData],
        averageLiquidation: Double,
        negativePercentage: Double,
        dailyAverage: Double,
        monthlyAverage: Double,
        totalWorkingHours: Double,
        dischargePercentage: Double
    ) -> Data {
        let pageWidth: CGFloat = 595.0  // A4
        let pageHeight: CGFloat = 842.0
        
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            return Data()
        }
        
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }
        
        // Pagina 1
        let page1View = PDFPage1View(
            year: year,
            yearlyClosedClaims: yearlyClosedClaims,
            yearlySentReports: yearlySentReports,
            yearlyAssignedClaims: yearlyAssignedClaims,
            monthlyBreakdown: monthlyBreakdown,
            averageLiquidation: averageLiquidation,
            negativePercentage: negativePercentage,
            dailyAverage: dailyAverage,
            totalWorkingHours: totalWorkingHours,
            dischargePercentage: dischargePercentage
        )
        
        renderSwiftUIViewToPDF(page1View, context: pdfContext, pageWidth: pageWidth, pageHeight: pageHeight)
        
        // Pagina 2
        let page2View = PDFPage2View(companyBreakdown: companyBreakdown)
        renderSwiftUIViewToPDF(page2View, context: pdfContext, pageWidth: pageWidth, pageHeight: pageHeight)
        
        pdfContext.closePDF()
        
        return pdfData as Data
    }
    
    private func renderSwiftUIViewToPDF<V: View>(_ view: V, context: CGContext, pageWidth: CGFloat, pageHeight: CGFloat) {
        context.beginPDFPage(nil)
        
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        hostingView.layout()
        
        // Forza il rendering del layer
        hostingView.wantsLayer = true
        hostingView.layer?.setNeedsDisplay()
        hostingView.layer?.displayIfNeeded()
        
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        
        context.translateBy(x: 0, y: pageHeight)
        context.scaleBy(x: 1, y: -1)
        
        if let layer = hostingView.layer {
            layer.render(in: context)
        }
        
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
    }
}

// MARK: - PDF Views (stesso design della vista principale)

struct PDFPage1View: View {
    let year: Int
    let yearlyClosedClaims: [Sinistro]
    let yearlySentReports: [Sinistro]
    let yearlyAssignedClaims: [Sinistro]
    let monthlyBreakdown: [MonthlyBreakdownData]
    let averageLiquidation: Double
    let negativePercentage: Double
    let dailyAverage: Double
    let totalWorkingHours: Double
    let dischargePercentage: Double
    
    var body: some View {
        VStack(spacing: 0) {
            // Header elegante
            HStack(spacing: 16) {
                // Logo placeholder
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "667EEA"), Color(hex: "764BA2")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text("P")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Report Annuale")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "2D3748"))
                    
                    Text("Riepilogo attività peritale")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(String(year))
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(hex: "2D3748"))
                    .frame(width: 100)
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: [Color(hex: "667EEA"), Color(hex: "764BA2")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            
            ScrollView {
                VStack(spacing: 20) {
                    // KPI Cards
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        PDFKPICard(
                            title: "Sinistri Chiusi",
                            value: "\(yearlyClosedClaims.count)",
                            subtitle: "Media \(String(format: "%.0f", Double(yearlyClosedClaims.count) / 12.0))/mese",
                            gradient: [Color(hex: "11998E"), Color(hex: "38EF7D")]
                        )
                        
                        PDFKPICard(
                            title: "Atti Inviati",
                            value: "\(yearlySentReports.count)",
                            subtitle: "Perizie completate",
                            gradient: [Color(hex: "667EEA"), Color(hex: "764BA2")]
                        )
                        
                        PDFKPICard(
                            title: "Media Liquidato",
                            value: CurrencyFormatter.shared.formatWithSymbol(averageLiquidation),
                            subtitle: "Su sinistri in PL",
                            gradient: [Color(hex: "F093FB"), Color(hex: "F5576C")]
                        )
                        
                        PDFKPICard(
                            title: "Negativi",
                            value: String(format: "%.1f%%", negativePercentage),
                            subtitle: "Senza liquidazione",
                            gradient: negativePercentage > 20 ? [Color(hex: "FF416C"), Color(hex: "FF4B2B")] : [Color(hex: "56AB2F"), Color(hex: "A8E063")]
                        )
                        
                        PDFKPICard(
                            title: "Media Giornaliera",
                            value: String(format: "%.1f", dailyAverage),
                            subtitle: "Chiusure/giorno",
                            gradient: [Color(hex: "4776E6"), Color(hex: "8E54E9")]
                        )
                        
                        PDFKPICard(
                            title: "Ore Lavorate",
                            value: String(format: "%.0f", totalWorkingHours),
                            subtitle: "Totale anno",
                            gradient: [Color(hex: "FF8008"), Color(hex: "FFC837")]
                        )
                        
                        PDFKPICard(
                            title: "% Scarico",
                            value: String(format: "%.1f%%", dischargePercentage),
                            subtitle: "\(yearlyClosedClaims.count) chiusi / \(yearlyAssignedClaims.count) assegnati",
                            gradient: dischargePercentage >= 80 ? [Color(hex: "56AB2F"), Color(hex: "A8E063")] : dischargePercentage >= 60 ? [Color(hex: "FFC837"), Color(hex: "FF8008")] : [Color(hex: "FF416C"), Color(hex: "FF4B2B")]
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    // Tabella mensile
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Andamento Mensile")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "2D3748"))
                            .padding(.horizontal, 20)
                        
                        VStack(spacing: 0) {
                            // Header
                            HStack(spacing: 0) {
                                Text("Mese")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Text("Chiusure")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                
                                Text("Atti Inviati")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color(hex: "F7FAFC"))
                            
                            Divider()
                            
                            // Righe
                            ForEach(monthlyBreakdown, id: \.month) { data in
                                HStack(spacing: 0) {
                                    Text(data.monthName)
                                        .font(.system(size: 10))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    Text("\(data.closures)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(Color(hex: "11998E"))
                                        .frame(maxWidth: .infinity, alignment: .center)
                                    
                                    Text("\(data.reports)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(Color(hex: "667EEA"))
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                
                                Divider()
                            }
                        }
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 10)
                    
                    // Footer
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            HStack(spacing: 6) {
                                Text("Generato da")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text("PerX")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color(hex: "667EEA"), Color(hex: "764BA2")],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            }
                            
                            Text(DateUtils.formatDate(Date()))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 30)
                }
            }
        }
        .background(Color.white)
    }
}

struct PDFPage2View: View {
    let companyBreakdown: [CompanyBreakdownData]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Dettaglio per Compagnia")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "2D3748"))
                
                Spacer()
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: [Color(hex: "667EEA"), Color(hex: "764BA2")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            
            ScrollView {
                VStack(spacing: 0) {
                    // Header tabella
                    HStack(spacing: 0) {
                        Text("Compagnia")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text("Tot. Chiusi")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .center)
                        
                        Text("In PL")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .center)
                        
                        Text("Media Liq.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 100, alignment: .center)
                        
                        Text("% Neg.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 70, alignment: .center)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(hex: "F7FAFC"))
                    
                    Divider()
                    
                    // Righe dati
                    ForEach(companyBreakdown, id: \.company) { data in
                        HStack(spacing: 0) {
                            Text(data.company)
                                .font(.system(size: 10, weight: .medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text("\(data.totalClaims)")
                                .font(.system(size: 10))
                                .frame(width: 80, alignment: .center)
                            
                            Text("\(data.inPLClaims)")
                                .font(.system(size: 10))
                                .frame(width: 60, alignment: .center)
                            
                            Text(CurrencyFormatter.shared.formatWithSymbol(data.averageLiquidation))
                                .font(.system(size: 10))
                                .foregroundColor(ColorUtils.getLiquidationColor(data.averageLiquidation))
                                .frame(width: 100, alignment: .center)
                            
                            Text(String(format: "%.1f%%", data.negativePercentage))
                                .font(.system(size: 10))
                                .foregroundColor(data.negativePercentage > 20 ? .red : .green)
                                .frame(width: 70, alignment: .center)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        
                        Divider()
                    }
                }
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                .padding(20)
                
                // Footer
                HStack {
                    Spacer()
                    Text("Pagina 2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.top, 20)
                .padding(.bottom, 30)
            }
        }
        .background(Color.white)
    }
}

struct PDFKPICard: View {
    let title: String
    let value: String
    let subtitle: String
    let gradient: [Color]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "2D3748"))
            
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(hex: "4A5568"))
            
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .shadow(color: gradient[0].opacity(0.15), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.5
                )
                .opacity(0.3)
        )
    }
}

