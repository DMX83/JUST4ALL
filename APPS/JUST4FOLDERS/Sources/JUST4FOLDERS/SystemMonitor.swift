import AppKit
import Darwin
import IOKit.ps

/// v2.3.6 — monitoreo ligero del sistema para la barra de herramientas.
/// Solo lectura y sin dependencias externas: ticks de CPU del kernel,
/// `vm_statistics64` para la memoria e IOKit para la batería.
final class SystemMonitor {
    private var lastCPUTicks: (busy: UInt32, idle: UInt32)?

    // MARK: - CPU

    private func cpuTicks() -> (busy: UInt32, idle: UInt32)? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = info.cpu_ticks.0
        let system = info.cpu_ticks.1
        let idle = info.cpu_ticks.2
        let nice = info.cpu_ticks.3
        return (user &+ system &+ nice, idle)
    }

    /// Uso de CPU 0…100. La primera llamada devuelve la media desde el arranque
    /// (todavía no hay delta) y deja la base para las siguientes.
    func cpuUsagePercent() -> Double? {
        guard let current = cpuTicks() else { return nil }
        defer { lastCPUTicks = current }
        if let previous = lastCPUTicks {
            let busyDelta = Double(current.busy &- previous.busy)
            let idleDelta = Double(current.idle &- previous.idle)
            let total = busyDelta + idleDelta
            guard total > 0 else { return nil }
            return min(100, max(0, busyDelta / total * 100))
        }
        let total = Double(current.busy) + Double(current.idle)
        guard total > 0 else { return nil }
        return min(100, max(0, Double(current.busy) / total * 100))
    }

    // MARK: - Memoria

    /// Memoria usada aproximada (activa + wired + comprimida), como el «Memory Used»
    /// del Monitor de Actividad, y el total físico del equipo.
    func memoryUsage() -> (usedBytes: UInt64, totalBytes: UInt64)? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(max(0, sysconf(_SC_PAGESIZE)))
        guard pageSize > 0 else { return nil }
        let active = UInt64(stats.active_count)
        let wired = UInt64(stats.wire_count)
        let compressed = UInt64(stats.compressor_page_count)
        let used = (active + wired + compressed) * pageSize
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return nil }
        return (min(used, total), total)
    }

    // MARK: - Disco

    /// Uso del volumen de arranque («/»): usado, total y libre en bytes.
    /// Libre = capacidad estándar (la que muestran Finder/`df`); si no está, se usa la de
    /// «uso importante» (incluye espacio purgable que macOS liberaría si hiciera falta).
    func diskUsage() -> (usedBytes: UInt64, totalBytes: UInt64, freeBytes: UInt64)? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0 else {
            return nil
        }
        let free: Int64
        if let regular = values.volumeAvailableCapacity {
            free = Int64(regular)
        } else if let important = values.volumeAvailableCapacityForImportantUsage {
            free = important
        } else {
            return nil
        }
        let totalBytes = UInt64(total)
        let freeBytes = UInt64(max(0, free))
        let usedBytes = totalBytes > freeBytes ? totalBytes - freeBytes : 0
        return (usedBytes, totalBytes, freeBytes)
    }

    // MARK: - Batería

    /// Batería interna (% y estado). Devuelve `nil` en equipos sin batería (Mac de escritorio).
    func batteryStatus() -> (percent: Int, isCharging: Bool, onBattery: Bool)? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let type = description[kIOPSTypeKey] as? String,
                  type == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let capacity = description[kIOPSMaxCapacityKey] as? Int,
                  capacity > 0 else {
                continue
            }
            let state = description[kIOPSPowerSourceStateKey] as? String ?? ""
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let percent = Int((Double(current) / Double(capacity) * 100).rounded())
            return (min(100, max(0, percent)), charging, state == kIOPSBatteryPowerValue)
        }
        return nil
    }
}

/// v2.3.6 — etiqueta compacta y clicable con el estado de la Mac («CPU 12% · RAM 63% ·
/// Disco 47% · Batería 82%»), pensada para el final del toolbar. Clic: abre el Monitor de
/// Actividad (el tooltip detalla GB de memoria/disco y el estado de la batería).
/// Usa frame fijo (no Auto Layout) porque el toolbar solo mide la vista al insertarla;
/// con Auto Layout, el ancho se fijaba con el texto todavía vacío y el resumen se recortaba.
/// El timer solo vive mientras la vista está en una ventana (sin fugas al cerrarla).
final class SystemMonitorView: NSView {
    /// Ancho reservado para el peor caso con 3 dígitos («CPU 100% · RAM 100% · Disco 100% ·
    /// Batería 100% ⚡» ≈ 300 pt medidos con la fuente real).
    static let preferredWidth: CGFloat = 306

    private let monitor = SystemMonitor()
    private let button = NSButton()
    private var timer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.preferredWidth, height: 24))
        button.frame = bounds
        button.autoresizingMask = [.width, .height]
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        button.alignment = .center
        button.target = self
        button.action = #selector(openActivityMonitor)
        button.setAccessibilityLabel("Monitoreo del sistema")
        button.toolTip = "Estado de la Mac · clic para abrir Monitor de Actividad"
        addSubview(button)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) no está soportado")
    }

    deinit {
        timer?.invalidate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopTimer()
        } else {
            startTimer()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        updateSnapshot()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateSnapshot()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateSnapshot() {
        let cpu = monitor.cpuUsagePercent()
        let memory = monitor.memoryUsage()
        let disk = monitor.diskUsage()
        let battery = monitor.batteryStatus()

        var parts: [String] = []
        var details: [String] = []

        if let cpu {
            let percent = Int(cpu.rounded())
            parts.append("CPU \(percent)%")
            details.append("CPU \(percent)%")
        }
        if let memory {
            let percent = memory.totalBytes > 0
                ? Int((Double(memory.usedBytes) / Double(memory.totalBytes) * 100).rounded())
                : 0
            parts.append("RAM \(percent)%")
            let used = ByteCountFormatter.string(fromByteCount: Int64(memory.usedBytes), countStyle: .memory)
            let total = ByteCountFormatter.string(fromByteCount: Int64(memory.totalBytes), countStyle: .memory)
            details.append("RAM \(used) de \(total) (\(percent)%)")
        }
        if let disk {
            let percent = disk.totalBytes > 0
                ? Int((Double(disk.usedBytes) / Double(disk.totalBytes) * 100).rounded())
                : 0
            parts.append("Disco \(percent)%")
            let used = ByteCountFormatter.string(fromByteCount: Int64(disk.usedBytes), countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: Int64(disk.totalBytes), countStyle: .file)
            let free = ByteCountFormatter.string(fromByteCount: Int64(disk.freeBytes), countStyle: .file)
            details.append("Disco: \(used) usados de \(total) · \(free) libres (\(percent)%)")
        }
        if let battery {
            parts.append(battery.isCharging ? "Batería \(battery.percent)% ⚡" : "Batería \(battery.percent)%")
            let stateText = battery.isCharging ? " (cargando)" : (battery.onBattery ? " (en batería)" : "")
            details.append("Batería \(battery.percent)%\(stateText)")
        }

        let title = parts.isEmpty ? "—" : parts.joined(separator: " · ")
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        let detailText = details.isEmpty ? "Sin datos disponibles." : details.joined(separator: " · ")
        button.toolTip = "\(detailText) · clic para abrir Monitor de Actividad"
    }

    @objc private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
    }
}
