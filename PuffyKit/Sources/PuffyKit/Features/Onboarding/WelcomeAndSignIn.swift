import SwiftUI

public struct WelcomeView: View {
    var onFinish: () -> Void
    @State private var page = 0

    public init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ActivityRings(RingProgress(dePuff: 1, scan: 1, habits: 0.75), size: .mini, animateOnAppear: false)
                    .frame(width: 26, height: 26)
                    .scaleEffect(26 / 32)
                Text("PuffyMeter").font(.title3.weight(.semibold))
                Spacer()
                Button("Skip", action: onFinish)
                    .font(.body)
                    .foregroundStyle(Color.pmAccent)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.top, 8)

            TabView(selection: $page) {
                welcomePage(0, eyebrow: "Meet PuffyMeter", headline: "A fresh perspective.\nEvery morning.",
                     body: "One quick scan. A clearer picture of your face's everyday changes.") {
                    WelcomeScoreArt()
                }
                welcomePage(1, eyebrow: "Make it a daily ritual", headline: "Small habits.\nVisible progress.",
                     body: "Scan, check in with your habits, and work toward your personal De-Puff goal.") {
                    ActivityRings(RingProgress(dePuff: 1, scan: 1, habits: 0.75), size: .hero)
                }
                welcomePage(2, eyebrow: "Private by design", headline: "Your face.\nYour folder.",
                     body: "Keep your daily photos in a Google Drive folder you choose. You stay in control.") {
                    WelcomePrivacyArt()
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif

            PageDots(count: 3, current: page).padding(.vertical, 16)

            Button(page < 2 ? "Continue" : "Get started") {
                if page < 2 { withAnimation { page += 1 } } else { onFinish() }
            }
            .buttonStyle(.pmPrimary)
            .padding(.horizontal, Spacing.margin)

            Disclaimer("Cosmetic wellness tracking. Not a medical diagnosis.", alignment: .center)
                .padding(.vertical, 12)
                .padding(.horizontal, Spacing.margin)
        }
        .background(Color.pmBackground.ignoresSafeArea())
    }

    private func welcomePage<Art: View>(_ index: Int, eyebrow: String, headline: String, body: String,
                                 @ViewBuilder art: () -> Art) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            art()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(eyebrow).eyebrowStyle()
            HeroHeadline(headline)
            Text(body).font(.title3).foregroundStyle(Color.pmLabelSecondary).wrapping()
        }
        .padding(.horizontal, Spacing.margin)
        .tag(index)
    }
}

struct PageDots: View {
    var count: Int
    var current: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.pmAccent : Color.pmLabelTertiary)
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

struct WelcomeScoreArt: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            SampleFaceIllustration(puffiness: 0.25)
                .aspectRatio(0.92, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.photoRadius, style: .continuous))
                .padding(.horizontal, 48)
                .padding(.bottom, 40)
            HStack(spacing: 14) {
                Text("32").metricFont(.hero).foregroundStyle(Color.pmAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Looking ahead").font(.headline)
                    MetricDelta(-8, suffix: "from yesterday", font: .footnote)
                    Text("Puffiness Score").font(.footnote).foregroundStyle(Color.pmLabelSecondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.pmCard, in: RoundedRectangle(cornerRadius: Spacing.cardRadius, style: .continuous))
            .padding(.leading, 64)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("Example: Puffiness Score 32, down 8 from yesterday")
    }
}

struct WelcomePrivacyArt: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.rectangle.stack")
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(Color.pmAccent)
            DriveFolderCard(name: DriveNaming.defaultFolderName, path: "My Drive / \(DriveNaming.defaultFolderName)",
                            status: "Only this folder is connected")
                .padding(.horizontal, 24)
        }
        .accessibilityElement(children: .combine)
    }
}

struct DriveFolderCard: View {
    var name: String
    var path: String
    var email: String? = nil
    var status: String
    var symbol: String? = nil

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    if let symbol { Image(systemName: symbol).foregroundStyle(Color.pmAccent) }
                    Text(name).font(.headline)
                }
                Text(path).font(.footnote).foregroundStyle(Color.pmLabelSecondary)
                if let email { Text(email).font(.footnote).foregroundStyle(Color.pmLabelSecondary) }
                Text(status).font(.footnote).foregroundStyle(Color.pmScan)
            }
        }
    }
}

// MARK: - Sign in

public struct SignInView: View {
    var onSignedIn: (UserProfile) -> Void
    var onUseLocally: () -> Void = {}
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var isWorking = false
    @State private var errorMessage: String?

    public init(onSignedIn: @escaping (UserProfile) -> Void, onUseLocally: @escaping () -> Void = {}) {
        self.onSignedIn = onSignedIn
        self.onUseLocally = onUseLocally
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ActivityRings(RingProgress(dePuff: 1, scan: 1, habits: 0.75), size: .card)
                    .padding(.top, 40)
                Text("PuffyMeter").font(.largeTitle.bold())
                Text("Your daily check-in,\nall in one place.").font(.title2.bold()).wrapping(.center)
                Text("Sign in to save your progress and connect your private photo folder.")
                    .font(.body).foregroundStyle(Color.pmLabelSecondary).wrapping(.center)

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(Color.pmAccent).wrapping(.center)
                }

                Button {
                    Task { await signIn(apple: false) }
                } label: {
                    HStack(spacing: 10) {
                        GoogleMark().frame(width: 22, height: 22)
                        Text("Continue with Google")
                    }
                }
                .buttonStyle(.pmPrimary)
                .padding(.top, 16)

                if AppConfiguration.appleSignInEnabled {
                Button {
                    Task { await signIn(apple: true) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "applelogo")
                        Text("Sign in with Apple")
                    }
                    .font(.headline)
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .frame(maxWidth: .infinity, minHeight: Spacing.buttonHeight)
                    .background(colorScheme == .dark ? Color.white : Color.black,
                                in: RoundedRectangle(cornerRadius: Spacing.buttonRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                }

                if showsLocalOption {
                    Button("Use without an account", action: onUseLocally)
                        .buttonStyle(.pmSecondary)
                    Text("Scans stay on this iPhone. You can connect Google Drive later in Profile.")
                        .font(.footnote).foregroundStyle(Color.pmLabelSecondary).wrapping(.center)
                }

                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.shield").foregroundStyle(Color.pmScan).font(.title3)
                            Text("Your privacy comes first").font(.headline)
                        }
                        Text("Photos stay in the Drive folder you choose. Your face is never used for advertising.")
                            .font(.footnote).foregroundStyle(Color.pmLabelSecondary).wrapping()
                    }
                }
                Text(termsText)
                    .font(.footnote).foregroundStyle(Color.pmLabelSecondary).multilineTextAlignment(.center)
                    .tint(Color.pmLabel)
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.bottom, 24)
        }
        .background(Color.pmBackground.ignoresSafeArea())
        .disabled(isWorking)
        .overlay { if isWorking { ProgressView().controlSize(.large) } }
    }

    /// Offered when Google sign-in isn't configured in this build (and in UI-test mode).
    private var showsLocalOption: Bool {
        !AppConfiguration.googleConfigured || ProcessInfo.processInfo.arguments.contains("-UITestMode")
    }

    private var termsText: AttributedString {
        (try? AttributedString(markdown: "By continuing, you agree to our [Terms of Service](https://puffymeter.app/terms)\nand [Privacy Policy](https://puffymeter.app/privacy).",
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString("By continuing, you agree to our Terms of Service and Privacy Policy.")
    }

    private func signIn(apple: Bool) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let profile = apple ? try await model.services.auth.signInWithApple()
                : try await model.services.auth.signInWithGoogle()
            onSignedIn(profile)
        } catch let error as AuthError {
            errorMessage = error.message
        } catch {
            errorMessage = "Sign-in didn't complete. Please try again."
        }
    }
}

/// Stand-in for Google's "G" mark. Replace with the official asset from Google's branding
/// guidelines before shipping.
struct GoogleMark: View {
    var body: some View {
        ZStack {
            Circle().fill(.white)
            Text("G")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AngularGradient(colors: [Color(light: 0x4285F4, dark: 0x4285F4),
                                                          Color(light: 0x34A853, dark: 0x34A853),
                                                          Color(light: 0xFBBC05, dark: 0xFBBC05),
                                                          Color(light: 0xEA4335, dark: 0xEA4335),
                                                          Color(light: 0x4285F4, dark: 0x4285F4)],
                                                 center: .center))
        }
        .accessibilityHidden(true)
    }
}
