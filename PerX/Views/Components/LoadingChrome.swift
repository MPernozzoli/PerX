import SwiftUI

struct GearCaption: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "gearshape.2")
                .symbolEffect(.rotate, options: .repeating)
            Text(text)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}

struct SkeletonBlock: View {
    var height: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }
}

struct SkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBlock(height: 18)
                .frame(width: 120)
            SkeletonBlock(height: 28)
                .frame(width: 72)
            SkeletonBlock()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}
