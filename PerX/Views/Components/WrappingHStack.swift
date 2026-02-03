import SwiftUI

struct WrappingHStack<Content: View>: View {
    let alignment: HorizontalAlignment
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let content: () -> Content
    
    init(alignment: HorizontalAlignment = .leading,
         horizontalSpacing: CGFloat = 8,
         verticalSpacing: CGFloat = 8,
         @ViewBuilder content: @escaping () -> Content) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.content = content
    }
    
    var body: some View {
        GeometryReader { geometry in
            self.generateContent(in: geometry)
        }
    }
    
    private func generateContent(in g: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        
        return ZStack(alignment: Alignment(horizontal: alignment, vertical: .top)) {
            content()
                .padding(.horizontal, horizontalSpacing / 2)
                .padding(.vertical, verticalSpacing / 2)
                .alignmentGuide(self.alignment, computeValue: { d in
                    if (abs(width - d.width) > g.size.width) {
                        width = 0
                        height -= d.height + verticalSpacing
                    }
                    let result = width
                    width -= d.width + horizontalSpacing
                    return result
                })
                .alignmentGuide(.top, computeValue: { _ in
                    return height
                })
        }
    }
} 