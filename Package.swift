// swift-tools-version: 6.4
import Foundation
import PackageDescription

/// Info.plist que se incrusta en el ejecutable para declarar los idiomas
/// (ver el comentario en Support/Info.plist). Ruta absoluta: el linker no
/// siempre corre desde la raíz del paquete (p. ej. desde Xcode).
let embeddedInfoPlist = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Support/Info.plist")
    .path

let package = Package(
    name: "Dotphin",
    // Las claves del catálogo (Resources/Localizable.xcstrings) son los textos
    // en español del código; cada una tiene valor en inglés y en español.
    // Inglés es el idioma de respaldo para quien no tenga ninguno de los dos.
    defaultLocalization: "en",
    platforms: [.macOS(.v27)],
    targets: [
        .executableTarget(
            name: "Dotphin",
            path: "Sources/Dotphin",
            // AppIcon.icon (Icon Composer) lo compila actool en el .app; ver
            // scripts/build_app_bundle.sh. AppIcon.icns es su salida, para `swift run`.
            exclude: ["Resources/AppIcon.icon"],
            resources: [
                .copy("Resources/AppIcon.icns"),
                .process("Resources/Localizable.xcstrings"),
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", embeddedInfoPlist]),
            ]
        ),
        .testTarget(name: "DotphinTests", dependencies: ["Dotphin"], path: "Tests/DotphinTests"),
    ]
)
