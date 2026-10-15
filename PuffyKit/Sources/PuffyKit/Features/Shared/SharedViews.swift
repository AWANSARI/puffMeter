import SwiftUI

/// Standard scrolling screen: large title, optional subtitle, 16 pt margins, grouped background.
public struct ScreenScaffold<Content: View>: View {
    var title: String
    var subtitle: String?
    var spacing: CGFloat
    var content: Content

    public init(_ title: String, subtitle: String? = nil, spacing: CGFloat = Spacing.cardGap,
                @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                if let subtitle { ScreenSubtitle(subtitle) }
                content
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.bottom, 24)
        }
        .background(Color.pmBackground.ignoresSafeArea())
        .navigationTitle(title)
        .pmLargeTitleDisplay()
    }
}

/// Loads a scan photo (or thumbnail) from the photo store; shows a soft placeholder otherwise.
public struct ScanPhotoView: View {
    var fileName: String?
    var cornerRadius: CGFloat

    @Environment(AppModel.self) private var model
    @State private var image: PlatformImage?

    public init(fileName: String?, cornerRadius: CGFloat = 12) {
        self.fileName = fileName
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        // Color.clear takes the parent's proposed size; the photo fills it and is clipped.
        Color.clear
            .overlay {
                if let image {
                    Image(platformImage: image).resizable().scaledToFill()
                } else {
                    PhotoPlaceholder()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: "\(fileName ?? "")#\(model.photosRevision)") {
            guard let fileName else { image = nil; return }
            image = await model.services.photos.image(named: fileName)
        }
        .accessibilityLabel("Scan photo")
    }
}

public struct PhotoPlaceholder: View {
    public init() {}
    public var body: some View {
        ZStack {
            LinearGradient(colors: [Color(light: 0xE7E4DF, dark: 0x3A3836), Color(light: 0xCFCAC3, dark: 0x2A2826)],
                           startPoint: .top, endPoint: .bottom)
            Image(systemName: "person.crop.square")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.pmLabelTertiary)
        }
    }
}

/// Inline banner used for "Google Drive needs to reconnect" and similar states.
public struct BannerView: View {
    var symbol: String
    var message: String
    var actionTitle: String
    var tint: Color
    var action: () -> Void

    public init(symbol: String, message: String, actionTitle: String, tint: Color = .pmAccent, action: @escaping () -> Void) {
        self.symbol = symbol
        self.message = message
        self.actionTitle = actionTitle
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(tint).font(.title3)
            Text(message).font(.subheadline).foregroundStyle(Color.pmLabel).wrapping()
            Spacer(minLength: 8)
            Button(actionTitle, action: action)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.pmCard, in: RoundedRectangle(cornerRadius: Spacing.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Spacing.cardRadius, style: .continuous).stroke(tint.opacity(0.35)))
    }
}

/// Big headline used on onboarding and celebration screens ("All rings.\nAll you.").
public struct HeroHeadline: View {
    var text: String
    var alignment: TextAlignment
    public init(_ text: String, alignment: TextAlignment = .leading) {
        self.text = text
        self.alignment = alignment
    }
    public var body: some View {
        Text(text)
            .font(.largeTitle.bold())
            .foregroundStyle(Color.pmLabel)
            .wrapping(alignment)
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }
}
