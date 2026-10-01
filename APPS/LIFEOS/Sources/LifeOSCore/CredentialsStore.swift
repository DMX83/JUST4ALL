import Foundation
import Security

public enum KeychainError: Error, LocalizedError {
    case status(OSStatus)
    case unexpectedData

    public var errorDescription: String? {
        switch self {
        case .status(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "código \(status)"
            return "El llavero rechazó la operación: \(message)"
        case .unexpectedData:
            return "El llavero devolvió un valor que no se puede leer"
        }
    }
}

/// Guarda el token de sesión en el llavero del sistema.
///
/// El token vale siete días y da acceso completo a la cuenta, así que no vive en
/// `UserDefaults` ni en un fichero: en el llavero, y accesible sólo con el
/// usuario desbloqueado.
public struct CredentialsStore {
    private let service: String
    private let account: String

    public init(service: String = "com.dmx83.lifeos", account: String = "session-token") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    public func save(token: String) throws {
        try delete()
        var query = baseQuery
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    public func token() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return value
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}
