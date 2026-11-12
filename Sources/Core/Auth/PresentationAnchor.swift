import AuthenticationServices
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The window `ASWebAuthenticationSession` anchors its sheet to, per platform.
enum PresentationAnchor {
    @MainActor
    static func current() -> ASPresentationAnchor {
        #if os(iOS)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.keyWindow ?? scene?.windows.first ?? ASPresentationAnchor()
        #else
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #endif
    }
}
