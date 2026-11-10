import Foundation
import XCTest
@testable import Dotphin

/// La app está en inglés y en español: las claves del catálogo son los textos
/// en español del código y cada una tiene valor en los dos idiomas.
final class LocalizationTests: XCTestCase {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func table(_ language: String) throws -> [String: String] {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language),
            "falta \(language).lproj/Localizable.strings"
        )
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    }

    private static func formatSpecifiers(in text: String) -> [String] {
        let regex = /%(?:\d+\$)?(?:lld|ld|d|@|lf|f|%)/
        return text.matches(of: regex).map { String($0.output) }
    }

    func test_bothLanguagesHaveEveryKey_withMatchingPlaceholders() throws {
        let english = try table("en")
        let spanish = try table("es")
        XCTAssertGreaterThan(english.count, 500)
        XCTAssertEqual(Set(english.keys), Set(spanish.keys))

        for (key, value) in english {
            XCTAssertEqual(Self.formatSpecifiers(in: value), Self.formatSpecifiers(in: key), "marcadores distintos en «\(key)»")
            XCTAssertEqual(spanish[key], key, "el español es la propia clave: «\(key)»")
        }
        XCTAssertEqual(english["Mover a la Papelera"], "Move to Trash")
        XCTAssertEqual(english["Mostrar en Finder"], "Show in Finder")
    }

    func test_englishIsTheFallbackLanguage() {
        XCTAssertEqual(Bundle.module.developmentLocalization, "en")
        XCTAssertEqual(Set(Bundle.module.localizations).intersection(["en", "es"]), ["en", "es"])
    }

    /// Sin estos idiomas declarados, el ejecutable suelto (Xcode, `swift run`)
    /// siempre elige el idioma de respaldo.
    func test_embeddedInfoPlist_declaresBothLanguages_withoutBundleIdentifier() throws {
        let url = Self.packageRoot.appendingPathComponent("Support/Info.plist")
        let plist = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: Any])
        XCTAssertEqual(plist["CFBundleDevelopmentRegion"] as? String, "en")
        XCTAssertEqual(Set(plist["CFBundleLocalizations"] as? [String] ?? []), ["en", "es"])
        XCTAssertNil(plist["CFBundleIdentifier"], "cambiaría el dominio de UserDefaults y se perderían los ajustes")
    }

    /// Un `String(localized:)` sin `bundle:` busca en el bundle principal, que
    /// al correr como ejecutable suelto no tiene traducciones: ese texto
    /// quedaría en español en silencio.
    func test_everyLocalizedStringInTheSourcesUsesThePackageBundle() throws {
        let sources = Self.packageRoot.appendingPathComponent("Sources/Dotphin")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        var offenders: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.contains("String(localized:") {
                let occurrences = line.components(separatedBy: "String(localized:").count - 1
                let bundled = line.components(separatedBy: "bundle: #bundle").count - 1
                if bundled < occurrences {
                    offenders.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
        }
        XCTAssertEqual(offenders, [], "String(localized:) sin bundle: #bundle")
    }
}
