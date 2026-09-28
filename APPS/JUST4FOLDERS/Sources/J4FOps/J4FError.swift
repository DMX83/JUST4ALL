import Darwin
import Foundation

/// Modelo central de errores de JUST4FOLDERS (MVP-0): separa el **dato técnico** del **mensaje UX**.
///
/// Uso en presentación (barra de estado, alertas): `J4FError.from(error).userMessage`.
/// El detalle técnico queda en `technicalDescription` (para el registro/diagnóstico del módulo).
public enum J4FError: Error, Equatable, LocalizedError {
    case permissionDenied(path: String?)
    case notFound(path: String?)
    case destinationReadOnly(path: String?)
    case conflict(path: String?)
    case diskFull(path: String?)
    case cancelled
    case bookmark(name: String, reason: String)
    case aiUnavailable(reason: String)
    case io(message: String)
    case unknown(message: String)

    public var errorDescription: String? { userMessage }

    /// Mensaje para el usuario (español, sin jerga técnica).
    public var userMessage: String {
        switch self {
        case .permissionDenied(let path):
            return path.map {
                "No hay permisos para «\($0)»: autoriza la ubicación o revisa los permisos en Ajustes del Sistema."
            } ?? "No hay permisos suficientes para completar la operación."
        case .notFound(let path):
            return path.map { "No se encontró «\($0)»: puede haberse movido o borrado." }
                ?? "El elemento ya no existe."
        case .destinationReadOnly(let path):
            return path.map { "El destino «\($0)» es de solo lectura (¿NTFS o disco protegido?)." }
                ?? "El destino es de solo lectura."
        case .conflict(let path):
            return path.map { "Conflicto de nombre en «\($0)»: se renombrará para no sobrescribir." }
                ?? "Conflicto de nombres: se renombrará para no sobrescribir."
        case .diskFull(let path):
            return path.map { "No queda espacio en «\($0)»." }
                ?? "No queda espacio en el disco de destino."
        case .cancelled:
            return "Operación cancelada."
        case .bookmark(let name, let reason):
            return "La ubicación autorizada «\(name)» necesita reautorizarse (\(reason))."
        case .aiUnavailable(let reason):
            return "La IA no está disponible ahora mismo (\(reason)); se usaron solo las reglas locales."
        case .io(let message):
            return "Error de entrada/salida: \(message)"
        case .unknown(let message):
            return message.isEmpty ? "Ocurrió un error inesperado." : message
        }
    }

    /// Detalle técnico (registro/diagnóstico).
    public var technicalDescription: String {
        switch self {
        case .permissionDenied(let path): return "permissionDenied path=\(path ?? "-")"
        case .notFound(let path): return "notFound path=\(path ?? "-")"
        case .destinationReadOnly(let path): return "destinationReadOnly path=\(path ?? "-")"
        case .conflict(let path): return "conflict path=\(path ?? "-")"
        case .diskFull(let path): return "diskFull path=\(path ?? "-")"
        case .cancelled: return "cancelled"
        case .bookmark(let name, let reason): return "bookmark name=\(name) reason=\(reason)"
        case .aiUnavailable(let reason): return "aiUnavailable reason=\(reason)"
        case .io(let message): return "io \(message)"
        case .unknown(let message): return "unknown \(message)"
        }
    }

    /// Traduce cualquier error (dominio propio, Cocoa, POSIX) al modelo central.
    public static func from(_ error: Error) -> J4FError {
        if let known = error as? J4FError { return known }
        let ns = error as NSError

        switch (ns.domain, ns.code) {
        case ("J4FOps", 2099):
            return .cancelled
        case ("J4FOps", 2020):
            return .conflict(path: nil)
        case ("J4FOps", 2001), ("J4FOps", 2002), ("J4FOps", 2004):
            return .io(message: ns.localizedDescription)
        default:
            break
        }

        if ns.domain == NSCocoaErrorDomain {
            switch CocoaError.Code(rawValue: ns.code) {
            case .fileReadNoPermission, .fileWriteNoPermission:
                return .permissionDenied(path: affectedPath(ns))
            case .fileNoSuchFile, .fileReadNoSuchFile:
                return .notFound(path: affectedPath(ns))
            case .fileWriteVolumeReadOnly:
                return .destinationReadOnly(path: affectedPath(ns))
            case .fileWriteOutOfSpace:
                return .diskFull(path: affectedPath(ns))
            case .userCancelled:
                return .cancelled
            default:
                break
            }
        }

        if ns.domain == NSPOSIXErrorDomain {
            switch Int32(ns.code) {
            case EACCES, EPERM:
                return .permissionDenied(path: affectedPath(ns))
            case EROFS:
                return .destinationReadOnly(path: affectedPath(ns))
            case ENOSPC:
                return .diskFull(path: affectedPath(ns))
            default:
                break
            }
        }

        let message = ns.localizedDescription
        return .unknown(message: message)
    }

    private static func affectedPath(_ ns: NSError) -> String? {
        if let url = ns.userInfo[NSURLErrorKey] as? URL { return url.path }
        if let path = ns.userInfo[NSFilePathErrorKey] as? String { return path }
        return nil
    }
}
