import Foundation
import UIKit
import PuffyKit
import GoogleSignIn
import AuthenticationServices

/// Google Sign-In for identity plus the non-sensitive `drive.file` scope (requested
/// incrementally on the Connect Google Drive screen). Sign in with Apple is offered too;
/// Apple-only accounts still connect Google for Drive storage.
@MainActor
final class GoogleAuthService: NSObject, AuthService {
    static let driveScope = "https://www.googleapis.com/auth/drive.file"
    private static let appleUserKey = "puffymeter.appleUserID"

    private var appleContinuation: CheckedContinuation<UserProfile, Error>?

    static func handle(url: URL) {
        _ = GIDSignIn.sharedInstance.handle(url)
    }

    private static let notConfigured = AuthError.other(
        "Google sign-in isn't set up in this build yet. Choose \u{201C}Use without an account\u{201D} for now.")

    func restorePreviousSignIn() async -> UserProfile? {
        if AppConfiguration.googleConfigured, let user = try? await GIDSignIn.sharedInstance.restorePreviousSignIn() {
            return profile(from: user)
        }
        if let appleID = Keychain.read(Self.appleUserKey),
           (try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: appleID)) == .authorized {
            return UserProfile(displayName: "PuffyMeter user", email: nil, provider: .apple)
        }
        return nil
    }

    func signInWithGoogle() async throws -> UserProfile {
        guard AppConfiguration.googleConfigured else { throw Self.notConfigured }
        guard let presenter = UIApplication.topViewController else { throw AuthError.other("No window to present sign-in.") }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            return profile(from: result.user)
        } catch let error as NSError where error.code == GIDSignInError.canceled.rawValue {
            throw AuthError.cancelled
        } catch let error as NSError where error.domain == NSURLErrorDomain {
            throw AuthError.network
        }
    }

    func signInWithApple() async throws -> UserProfile {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            appleContinuation = continuation
            controller.performRequests()
        }
    }

    func requestDriveAccess() async throws -> String? {
        guard AppConfiguration.googleConfigured else { throw Self.notConfigured }
        guard let presenter = UIApplication.topViewController else { throw AuthError.other("No window to present sign-in.") }
        var user = GIDSignIn.sharedInstance.currentUser
        if user == nil {
            // Apple-only accounts sign in with Google here just for Drive.
            user = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil,
                                                             additionalScopes: [Self.driveScope]).user
        }
        guard let current = user else { throw AuthError.notSignedIn }
        if !(current.grantedScopes ?? []).contains(Self.driveScope) {
            do {
                let result = try await current.addScopes([Self.driveScope], presenting: presenter)
                guard (result.user.grantedScopes ?? []).contains(Self.driveScope) else { throw AuthError.driveScopeDenied }
            } catch let error as NSError where error.code == GIDSignInError.canceled.rawValue {
                throw AuthError.cancelled
            }
        }
        return current.profile?.email
    }

    func signOut() async {
        if AppConfiguration.googleConfigured { GIDSignIn.sharedInstance.signOut() }
        Keychain.delete(Self.appleUserKey)
    }

    func driveAccessToken() async throws -> String {
        guard AppConfiguration.googleConfigured else { throw AuthError.notSignedIn }
        guard let user = GIDSignIn.sharedInstance.currentUser else { throw AuthError.notSignedIn }
        let refreshed = try await user.refreshTokensIfNeeded()
        guard (refreshed.grantedScopes ?? []).contains(Self.driveScope) else { throw AuthError.driveScopeDenied }
        return refreshed.accessToken.tokenString
    }

    nonisolated func driveAccessTokenFromAnyContext() async throws -> String {
        try await driveAccessToken()
    }

    private func profile(from user: GIDGoogleUser) -> UserProfile {
        UserProfile(displayName: user.profile?.name ?? "PuffyMeter user", email: user.profile?.email, provider: .google)
    }
}

extension GoogleAuthService: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        let userID = credential?.user
        let name = credential?.fullName.flatMap { PersonNameComponentsFormatter().string(from: $0) }
        let email = credential?.email
        Task { @MainActor in
            if let userID { Keychain.write(userID, for: Self.appleUserKey) }
            let profile = UserProfile(displayName: (name?.isEmpty == false ? name : nil) ?? "PuffyMeter user",
                                      email: email, provider: .apple)
            appleContinuation?.resume(returning: profile)
            appleContinuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let cancelled = (error as? ASAuthorizationError)?.code == .canceled
        Task { @MainActor in
            appleContinuation?.resume(throwing: cancelled ? AuthError.cancelled : AuthError.other("Sign in with Apple didn't complete."))
            appleContinuation = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? UIWindow()
        }
    }
}

extension UIApplication {
    @MainActor static var topViewController: UIViewController? {
        let root = shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Minimal Keychain wrapper (this-device-only, after first unlock).
enum Keychain {
    static func write(_ value: String, for key: String) {
        delete(key)
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: key,
                                      kSecValueData: Data(value.utf8),
                                      kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: key,
                                      kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key] as CFDictionary)
    }
}
