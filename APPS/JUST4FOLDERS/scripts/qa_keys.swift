#!/usr/bin/env swift
// QA de teclado para JUST4FOLDERS.
//
// Nació del caso v2.3.13–v2.3.15 («presiono Return y no hace nada»): para reproducirlo hacía
// falta (a) saber dónde está el foco de teclado de verdad y (b) enviar teclas CON modificadores
// (el Enter del teclado numérico llega con `.numericPad`, F1–F12 con `.function`, y el Bloqueo
// de mayúsculas añade `.capsLock`). Las capturas de pantalla no dicen ninguna de las dos cosas.
//
// Uso:
//   swift scripts/qa_keys.swift win [nombre]        → WID de la primera ventana (por defecto JUST4FOLDERS)
//   swift scripts/qa_keys.swift focus <pid>          → rol y descripción del elemento con foco (AX)
//   swift scripts/qa_keys.swift key <keyCode> [flags] → envía la tecla (flags: num,caps,fn,shift,cmd,opt,ctrl)
//
// Ejemplos:
//   PID=$(pgrep -x JUST4FOLDERS | head -1)
//   swift scripts/qa_keys.swift focus $PID           # «rol=AXTable desc=Contenido del panel Izquierdo»
//   swift scripts/qa_keys.swift key 36               # Return
//   swift scripts/qa_keys.swift key 36 num           # tecla grande «Enter» de un teclado Windows
//   swift scripts/qa_keys.swift key 76 num           # Enter del teclado numérico
//   swift scripts/qa_keys.swift key 51               # Retroceso (⌫)  → debe volver

import Cocoa

let arguments = CommandLine.arguments

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

/// WID de la primera ventana visible de la app.
///
/// Se prueban dos listados porque `.optionOnScreenOnly` **omite las ventanas que están en otro
/// escritorio/espacio** (caso real: la app se quedó en otro Space y la búsqueda no encontraba nada
/// aunque la app estaba viva con su ventana). El segundo listado (`.optionAll`) sí la encuentra;
/// se filtra por capa 0 para no confundirla con paneles/menús.
func windowID(owner: String) -> Int? {
    let attempts: [CGWindowListOption] = [
        [.optionOnScreenOnly, .excludeDesktopElements],
        .optionAll
    ]
    for options in attempts {
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            continue
        }
        for entry in list {
            guard let name = entry[kCGWindowOwnerName as String] as? String, name == owner,
                  let number = entry[kCGWindowNumber as String] as? Int else { continue }
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            return number
        }
    }
    return nil
}

func focusedElement(pid: Int32) -> String {
    let application = AXUIElementCreateApplication(pid)
    var focusedValue: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focusedValue)
    guard error == .success, let focusedValue else {
        switch error {
        case .apiDisabled:
            return "AXError -25211: falta el permiso de **Accesibilidad** para el terminal."
        case .noValue:
            return "AXError -25212: la ventana no está al frente o está en otro escritorio; "
                + "activa la app antes de preguntar por el foco."
        default:
            return "AXError \(error.rawValue): sin foco accesible."
        }
    }
    let element = focusedValue as! AXUIElement
    func attribute(_ name: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value else { return "-" }
        return String(describing: value)
    }
    return "rol=\(attribute(kAXRoleAttribute)) subrol=\(attribute(kAXSubroleAttribute)) "
        + "desc=\(attribute(kAXDescriptionAttribute)) titulo=\(attribute(kAXTitleAttribute))"
}

func postKey(keyCode: UInt16, flags: CGEventFlags) {
    let source = CGEventSource(stateID: .hidSystemState)
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false) else {
        fail("no se pudo crear el evento de teclado")
    }
    down.flags = flags
    up.flags = flags
    down.post(tap: .cghidEventTap)
    usleep(40_000)
    up.post(tap: .cghidEventTap)
}

func parseFlags(_ text: String) -> CGEventFlags {
    var flags: CGEventFlags = []
    for piece in text.split(separator: ",") {
        switch piece.trimmingCharacters(in: .whitespaces).lowercased() {
        case "num", "numericpad": flags.insert(.maskNumericPad)
        case "caps", "capslock": flags.insert(.maskAlphaShift)
        case "fn", "function": flags.insert(.maskSecondaryFn)
        case "shift": flags.insert(.maskShift)
        case "cmd", "command": flags.insert(.maskCommand)
        case "opt", "option", "alt": flags.insert(.maskAlternate)
        case "ctrl", "control": flags.insert(.maskControl)
        case "": break
        default: fail("bandera desconocida: \(piece)")
        }
    }
    return flags
}

guard arguments.count >= 2 else {
    fail("uso: qa_keys.swift win [nombre] | focus <pid> | key <keyCode> [flags]")
}

switch arguments[1] {
case "win":
    let owner = arguments.count > 2 ? arguments[2] : "JUST4FOLDERS"
    guard let identifier = windowID(owner: owner) else { fail("ventana no encontrada: \(owner)") }
    print("WID=\(identifier)")
case "focus":
    guard arguments.count > 2, let pid = Int32(arguments[2]) else { fail("falta el pid") }
    print(focusedElement(pid: pid))
case "key":
    guard arguments.count > 2, let keyCode = UInt16(arguments[2]) else { fail("falta el keyCode") }
    let flags = arguments.count > 3 ? parseFlags(arguments[3]) : []
    postKey(keyCode: keyCode, flags: flags)
    print("tecla enviada: keyCode \(keyCode) flags \(flags.rawValue)")
default:
    fail("subcomando desconocido: \(arguments[1])")
}
