import AuthenticationServices
import CryptoKit
import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct WorkspaceSessionTokens: Decodable {
    let access_token: String
    let refresh_token: String
    let token_type: String?
}

enum GoogleWorkspaceSignInError: LocalizedError {
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Accesso annullato."
        case .failed(let message):
            return message
        }
    }
}

/// Apre Safari, torna con la sessione Supabase e non tiene il token Google della casella.
@MainActor
final class GoogleWorkspaceSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleWorkspaceSignIn()

    static let redirectURL = URL(string: "com.pernozzoli.perx://login-callback")!
    static let callbackScheme = "com.pernozzoli.perx"
    static let supabaseAuthorizeURL = URL(string: "https://wqcqiaojdflbmqyamndt.supabase.co/auth/v1/authorize")!

    /// Gli stessi ambiti da abilitare nel consenso Google del Workspace Chiari.
    static let scopes = [
        "openid",
        "email",
        "profile",
        "https://www.googleapis.com/auth/gmail.modify",
        "https://www.googleapis.com/auth/gmail.settings.basic",
        "https://www.googleapis.com/auth/calendar.events",
    ].joined(separator: " ")

    private var session: ASWebAuthenticationSession?
    private var finished = false

    func signIn(apiBaseURL: String) async throws -> WorkspaceSessionTokens {
        let verifier = Self.makeVerifier()
        let callback = try await authenticate(verifier: verifier)
        return try await exchange(callback: callback, verifier: verifier, apiBaseURL: apiBaseURL)
    }

    private func authenticate(verifier: String) async throws -> URL {
        var components = URLComponents(url: Self.supabaseAuthorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: Self.redirectURL.absoluteString),
            URLQueryItem(name: "scopes", value: Self.scopes),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        guard let url = components?.url else {
            throw GoogleWorkspaceSignInError.failed("URL di accesso non valido.")
        }

        finished = false
        return try await withCheckedThrowingContinuation { continuation in
            let authSession = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.callbackScheme) { callback, error in
                guard !self.finished else { return }
                self.finished = true
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: GoogleWorkspaceSignInError.cancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: GoogleWorkspaceSignInError.failed(error.localizedDescription))
                    return
                }
                guard let callback else {
                    continuation.resume(throwing: GoogleWorkspaceSignInError.failed("Google non ha completato l'accesso."))
                    return
                }
                continuation.resume(returning: callback)
            }
            authSession.presentationContextProvider = self
            authSession.prefersEphemeralWebBrowserSession = false
            session = authSession
            if !authSession.start() {
                guard !finished else { return }
                finished = true
                continuation.resume(throwing: GoogleWorkspaceSignInError.failed("Impossibile aprire Safari."))
            }
        }
    }

    private func exchange(callback: URL, verifier: String, apiBaseURL: String) async throws -> WorkspaceSessionTokens {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let description = items.first(where: { $0.name == "error_description" })?.value, !description.isEmpty {
            throw GoogleWorkspaceSignInError.failed(description)
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw GoogleWorkspaceSignInError.failed("Manca il codice di accesso.")
        }
        let base = apiBaseURL.hasSuffix("/") ? String(apiBaseURL.dropLast()) : apiBaseURL
        guard let url = URL(string: "\(base)/api/v1/auth/google/session") else {
            throw GoogleWorkspaceSignInError.failed("Server non configurato.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(GoogleSessionExchange(code: code, code_verifier: verifier))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleWorkspaceSignInError.failed("Risposta non valida.")
        }
        guard 200...299 ~= http.statusCode else {
            throw GoogleWorkspaceSignInError.failed(Self.message(from: data, status: http.statusCode))
        }
        return try JSONDecoder().decode(WorkspaceSessionTokens.self, from: data)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApplication.shared.keyWindow ?? ASPresentationAnchor()
        #else
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.keyWindow ?? scene?.windows.first ?? ASPresentationAnchor()
        #endif
    }

    private static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }

    private static func message(from data: Data, status: Int) -> String {
        if let body = try? JSONDecoder().decode(GoogleSessionErrorBody.self, from: data) {
            if let detail = body.detail, !detail.isEmpty { return detail }
        }
        return "Accesso non riuscito (\(status))."
    }
}

private struct GoogleSessionExchange: Encodable {
    let code: String
    let code_verifier: String
}

private struct GoogleSessionErrorBody: Decodable {
    let detail: String?
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
