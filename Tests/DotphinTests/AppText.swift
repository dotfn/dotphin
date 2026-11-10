import Foundation
@testable import Dotphin

/// Texto de la app para la clave `key` (el texto en español del código) en el
/// idioma con el que corren los tests, que es el del sistema. Las aserciones
/// sobre textos visibles comparan contra esto para no depender de un idioma.
func appText(_ key: String, _ arguments: CVarArg...) -> String {
    let format = Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    return arguments.isEmpty ? format : String(format: format, arguments: arguments)
}
