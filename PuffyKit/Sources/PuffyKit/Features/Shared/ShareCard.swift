import SwiftUI

/// Renders a shareable 1080 × 1350 progress card. No face photo by default.
@MainActor
public enum ShareCardRenderer {
    public static func render(stats: DayStats, streak: Int, calendar: Calendar) -> Image {
        let renderer = ImageRenderer(content: ShareCardView(stats: stats, streak: streak, calendar: calendar)
            .environment(\.colorScheme, .dark))
        renderer.scale = 3
        if let cgImage = renderer.cgImage {
            return Image(decorative: cgImage, scale: 1)
        }
        return Image(systemName: "circle.circle")
    }
}

struct ShareCardView: View {
    var stats: DayStats
    var streak: Int
    var calendar: Calendar

    var body: some View {
        VStack(spacing: 18) {
            Text(Format.longDay(stats.day, calendar: calendar)).eyebrowStyle(.pmScan)
            ActivityRings(stats.rings, size: .card, animateOnAppear: false)
            if let score = stats.score {
                Text("\(score)")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.pmRingDePuff)
                Text("Puffiness Score · Lower is better").font(.footnote).foregroundStyle(.white.opacity(0.6))
            }
            if streak > 0 {
                Label("\(streak)-day streak", systemImage: "flame").font(.headline).foregroundStyle(.white)
            }
            Text("PuffyMeter").font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
        }
        .padding(28)
        .frame(width: 360, height: 450)
        .background(Color.black)
    }
}
