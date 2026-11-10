import AppKit
import SwiftUI

/// Datos de "Acerca de Dotphin".
///
/// Versionado SemVer: `MAYOR.MENOR.PARCHE` más una etiqueta de prelanzamiento
/// mientras no sea estable (`0.1.0-beta.1`, `0.1.0-beta.2`, … `0.1.0`). El
/// `Info.plist` solo admite tres enteros en `CFBundleShortVersionString`, así
/// que ahí va `0.1.0` y la etiqueta vive acá. Al publicar: tag `v0.1.0-beta.1`.
enum AppInfo {
    static let name = "Dotphin"
    static let tagline = String(localized: "Gestor de archivos nativo para macOS, inspirado en Dolphin.", bundle: #bundle)
    static let authorSite = URL(string: "https://dotfn.dev")!
    static let copyright = "© 2026 ●fn"

    /// Mantener igual que `CFBundleShortVersionString` en `scripts/build_app_bundle.sh`.
    static let marketingVersion = "0.1.0"
    /// `nil` cuando la versión es estable.
    static let prerelease: String? = "beta.1"

    static var version: String {
        prerelease.map { "\(marketingVersion)-\($0)" } ?? marketingVersion
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}

/// Reemplaza "Acerca de…" por el panel estándar de AppKit con sus opciones:
/// ícono, versión, descripción con el sitio y una línea de copyright.
struct AboutCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(String(localized: "Acerca de \(AppInfo.name)", bundle: #bundle)) {
                AboutPanel.show()
            }
        }
    }
}

@MainActor
enum AboutPanel {
    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.name,
            .applicationIcon: NSApp.applicationIconImage as Any,
            .applicationVersion: AppInfo.version,
            .version: AppInfo.build,
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): AppInfo.copyright,
        ])
    }

    /// Descripción y, debajo, el sitio como enlace.
    static var credits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 6
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let credits = NSMutableAttributedString(string: "\(AppInfo.tagline)\n", attributes: base)
        var link = base
        link[.link] = AppInfo.authorSite
        credits.append(NSAttributedString(string: AppInfo.authorSite.host() ?? "dotfn.dev", attributes: link))
        return credits
    }
}
