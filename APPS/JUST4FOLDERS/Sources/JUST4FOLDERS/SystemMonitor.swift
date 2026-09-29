import AppKit
import Darwin
import IOKit
import IOKit.ps

/// v2.3.6 — monitoreo ligero del sistema para la barra de herramientas.
/// Solo lectura y sin dependencias externas: ticks de CPU del kernel, `vm_statistics64`
/// para la memoria, IOKit (contadores de E/S de los discos reales) para el disco y
/// `IOKit.ps` para la batería.
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

    // MARK: - Actividad de disco (E/S)

    private var lastDiskIO: (timestamp: TimeInterval, readBytes: Int64, writeBytes: Int64, operations: Int64)?

    /// Rendimiento de E/S del intervalo (lectura/escritura en MB/s y operaciones/s),
    /// sumando los controladores de almacenamiento reales (se excluyen los «Disk Image»,
    /// cuya E/S ya contabiliza el disco físico que los respalda). La primera llamada solo
    /// fija la base y devuelve `nil`.
    ///
    /// El «% de trabajo» que muestra la barra se calcula en la vista: dirección más cargada
    /// (lectura o escritura, nunca sumadas — la suma puede superar el máximo real de una
    /// sola dirección) frente al máximo registrado por dirección. Ojo: el «% de ocupación»
    /// oficial de macOS **no existe** de forma fiable — los contadores «Total Time
    /// (Read/Write)» del driver acumulan tiempo POR OPERACIÓN sobre varias colas NVMe y
    /// superan el tiempo real (medido: >300 % mientras un `dd` escribía a 425 MB/s).
    func diskActivity() -> (readMBps: Double, writeMBps: Double, opsPerSecond: Double)? {
        guard let totals = diskIOTotals() else {
            lastDiskIO = nil
            return nil
        }
        let now = Date().timeIntervalSince1970
        defer {
            lastDiskIO = (now, totals.readBytes, totals.writeBytes, totals.operations)
        }
        guard let previous = lastDiskIO else { return nil }
        let interval = now - previous.timestamp
        guard interval > 0.1 else { return nil }
        let readDelta = max(0, totals.readBytes - previous.readBytes)
        let writeDelta = max(0, totals.writeBytes - previous.writeBytes)
        let opsDelta = max(0, totals.operations - previous.operations)
        return (
            Double(readDelta) / interval / 1_000_000,
            Double(writeDelta) / interval / 1_000_000,
            Double(opsDelta) / interval
        )
    }

    /// Suma acumulada de bytes/operaciones de los discos reales (excluye «Disk Image»).
    private func diskIOTotals() -> (readBytes: Int64, writeBytes: Int64, operations: Int64)? {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var readBytes: Int64 = 0
        var writeBytes: Int64 = 0
        var operations: Int64 = 0
        var found = false

        var service = IOIteratorNext(iterator)
        while service != 0 {
            if !isDiskImage(service), let stats = statistics(for: service) {
                readBytes += statValue(stats, "Bytes (Read)")
                writeBytes += statValue(stats, "Bytes (Write)")
                operations += statValue(stats, "Operations (Read)") + statValue(stats, "Operations (Write)")
                found = true
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return found ? (readBytes, writeBytes, operations) : nil
    }

    private func statistics(for service: io_registry_entry_t) -> [String: Any]? {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any],
              let stats = dictionary["Statistics"] as? [String: Any] else {
            return nil
        }
        return stats
    }

    private func statValue(_ stats: [String: Any], _ key: String) -> Int64 {
        (stats[key] as? NSNumber)?.int64Value ?? 0
    }

    /// «Disk Image» = DMG/imágenes montadas: no son discos físicos (su E/S ya la cuenta la SSD).
    private func isDiskImage(_ service: io_registry_entry_t) -> Bool {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS, parent != 0 else {
            return false
        }
        defer { IOObjectRelease(parent) }
        guard let characteristics = IORegistryEntryCreateCFProperty(
            parent, "Device Characteristics" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? [String: Any],
              let product = characteristics["Product Name"] as? String else {
            return false
        }
        return product.contains("Disk Image")
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
/// Disco 47% · I/O 34% · Batería 82%»), pensada para el final del toolbar. El segmento I/O
/// es el **% de trabajo**: la dirección más cargada (lectura o escritura, nunca sumadas)
/// frente al máximo registrado en este Mac (picos por dirección aprendidos y persistidos;
/// 100 % = su tope conocido). Clic: abre el Monitor de Actividad (el tooltip detalla GB de
/// memoria/disco, MB/s de lectura/escritura con ops/s, los máximos vistos y el estado de la
/// batería). Diseño: etiquetas en gris atenuado, separadores tenues, valores a color pleno y
/// **avisos por umbral** — naranja (atención) y rojo (crítico/saturado) con más peso.
/// Usa frame fijo (no Auto Layout) porque el toolbar solo mide la vista al insertarla;
/// con Auto Layout, el ancho se fijaba con el texto todavía vacío y el resumen se recortaba.
/// El timer solo vive mientras la vista está en una ventana (sin fugas al cerrarla).
final class SystemMonitorView: NSView {
    /// Ancho reservado para el peor caso («CPU 100% · RAM 100% · Disco 100% · I/O 100% ·
    /// Batería 100%» ≈ 339 pt medidos con la fuente real).
    static let preferredWidth: CGFloat = 344

    private let monitor = SystemMonitor()
    private let button = NSButton()
    private var timer: Timer?
    /// Picos de E/S por dirección (MB/s) vistos en este Mac: persisten entre sesiones y son
    /// la referencia del «% de trabajo» del segmento I/O.
    private var peakReadMBps = UserDefaults.standard.double(forKey: SystemMonitorView.peakReadKey)
    private var peakWriteMBps = UserDefaults.standard.double(forKey: SystemMonitorView.peakWriteKey)
    private static let peakReadKey = "j4f.monitor.diskPeakReadMBps"
    private static let peakWriteKey = "j4f.monitor.diskPeakWriteMBps"
    /// Referencia mínima (MB/s) antes de haber aprendido picos reales.
    private static let referenceFloorMBps: Double = 1000

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

    // MARK: - Diseño de la etiqueta

    /// Umbrales de aviso del monitor (naranja = atención; rojo = crítico/saturado).
    /// En I/O aplican a la dirección más cargada (lectura o escritura).
    private enum Thresholds {
        static let cpuWarn = 80.0, cpuCritical = 95.0
        static let ramWarn = 85.0, ramCritical = 95.0
        static let diskWarn = 85.0, diskCritical = 93.0
        static let ioWarnPercent = 60.0, ioCriticalPercent = 85.0
        static let batteryWarn = 25, batteryCritical = 15
    }

    /// Un segmento de la etiqueta: nombre en gris + valor que puede teñirse/engrosarse.
    private struct Metric {
        let label: String
        let value: String
        let color: NSColor
        let font: NSFont
    }

    private static let baseFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private static let warnFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    private static let criticalFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)

    /// Severidad: 0 normal · 1 aviso (naranja, seminegrita) · 2 crítico (rojo, negrita).
    private static func severity(for value: Double, warn: Double, critical: Double) -> Int {
        if value >= critical { return 2 }
        if value >= warn { return 1 }
        return 0
    }

    private static func style(for severity: Int) -> (color: NSColor, font: NSFont) {
        switch severity {
        case 2: return (.systemRed, criticalFont)
        case 1: return (.systemOrange, warnFont)
        default: return (.labelColor, baseFont)
        }
    }

    private func updateSnapshot() {
        let cpu = monitor.cpuUsagePercent()
        let memory = monitor.memoryUsage()
        let disk = monitor.diskUsage()
        let io = monitor.diskActivity()
        let battery = monitor.batteryStatus()

        var metrics: [Metric] = []
        var details: [String] = []

        if let cpu {
            let percent = Int(cpu.rounded())
            let style = Self.style(for: Self.severity(for: cpu, warn: Thresholds.cpuWarn, critical: Thresholds.cpuCritical))
            metrics.append(Metric(label: "CPU", value: "\(percent)%", color: style.color, font: style.font))
            details.append("CPU \(percent)%")
        }
        if let memory {
            let ratio = memory.totalBytes > 0
                ? Double(memory.usedBytes) / Double(memory.totalBytes) * 100
                : 0
            let percent = Int(ratio.rounded())
            let style = Self.style(for: Self.severity(for: ratio, warn: Thresholds.ramWarn, critical: Thresholds.ramCritical))
            metrics.append(Metric(label: "RAM", value: "\(percent)%", color: style.color, font: style.font))
            let used = ByteCountFormatter.string(fromByteCount: Int64(memory.usedBytes), countStyle: .memory)
            let total = ByteCountFormatter.string(fromByteCount: Int64(memory.totalBytes), countStyle: .memory)
            details.append("RAM \(used) de \(total) (\(percent)%)")
        }
        if let disk {
            let ratio = disk.totalBytes > 0
                ? Double(disk.usedBytes) / Double(disk.totalBytes) * 100
                : 0
            let percent = Int(ratio.rounded())
            let style = Self.style(for: Self.severity(for: ratio, warn: Thresholds.diskWarn, critical: Thresholds.diskCritical))
            metrics.append(Metric(label: "Disco", value: "\(percent)%", color: style.color, font: style.font))
            let used = ByteCountFormatter.string(fromByteCount: Int64(disk.usedBytes), countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: Int64(disk.totalBytes), countStyle: .file)
            let free = ByteCountFormatter.string(fromByteCount: Int64(disk.freeBytes), countStyle: .file)
            details.append("Disco: \(used) usados de \(total) · \(free) libres (\(percent)%)")
        }
        if let io {
            // El «% de trabajo» se calcula contra el máximo registrado en este Mac por
            // dirección (se aprende y persiste el pico; nunca se suman L+E). Así 100 % es
            // «su velocidad tope conocida», sin inventar constantes de fábrica.
            if io.readMBps > peakReadMBps {
                peakReadMBps = io.readMBps
                UserDefaults.standard.set(peakReadMBps, forKey: Self.peakReadKey)
            }
            if io.writeMBps > peakWriteMBps {
                peakWriteMBps = io.writeMBps
                UserDefaults.standard.set(peakWriteMBps, forKey: Self.peakWriteKey)
            }
            let readReference = max(peakReadMBps, Self.referenceFloorMBps)
            let writeReference = max(peakWriteMBps, Self.referenceFloorMBps)
            let readPercent = io.readMBps / readReference * 100
            let writePercent = io.writeMBps / writeReference * 100
            let percent = Int(min(100, max(readPercent, writePercent)).rounded())
            let style = Self.style(for: Self.severity(
                for: Double(percent),
                warn: Thresholds.ioWarnPercent,
                critical: Thresholds.ioCriticalPercent
            ))
            metrics.append(Metric(label: "I/O", value: "\(percent)%", color: style.color, font: style.font))
            let ops = NumberFormatter.localizedString(
                from: NSNumber(value: max(0, io.opsPerSecond.rounded())),
                number: .decimal
            )
            details.append(
                "Actividad de disco: \(percent)% (lectura \(Self.throughputText(io.readMBps)) · escritura \(Self.throughputText(io.writeMBps)) · \(ops) ops/s)"
                    + " · máximos vistos: L \(Self.throughputText(peakReadMBps)) / E \(Self.throughputText(peakWriteMBps))"
            )
        }
        if let battery {
            // Aviso solo cuando va con batería; cargando nunca es una alerta.
            var severity = 0
            if battery.onBattery && !battery.isCharging {
                if battery.percent <= Thresholds.batteryCritical { severity = 2 }
                else if battery.percent <= Thresholds.batteryWarn { severity = 1 }
            }
            let style = Self.style(for: severity)
            metrics.append(Metric(label: "Batería", value: "\(battery.percent)%", color: style.color, font: style.font))
            let stateText = battery.isCharging ? " (cargando)" : (battery.onBattery ? " (en batería)" : "")
            details.append("Batería \(battery.percent)%\(stateText)")
        }

        button.attributedTitle = Self.attributedSummary(metrics)
        let plain = metrics.map { "\($0.label) \($0.value)" }.joined(separator: " · ")
        button.setAccessibilityValue(plain.isEmpty ? "sin datos" : plain)
        let detailText = details.isEmpty ? "Sin datos disponibles." : details.joined(separator: " · ")
        button.toolTip = "\(detailText) · clic para abrir Monitor de Actividad"
    }

    /// Compone el resumen con jerarquía visual: etiquetas en gris atenuado, separadores
    /// tenues y valores a color pleno (o de aviso: naranja/rojo + peso mayor) según umbrales.
    private static func attributedSummary(_ metrics: [Metric]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let separator = NSAttributedString(
            string: " · ",
            attributes: [.font: baseFont, .foregroundColor: NSColor.tertiaryLabelColor]
        )
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        for (index, metric) in metrics.enumerated() {
            if index > 0 { result.append(separator) }
            result.append(NSAttributedString(string: "\(metric.label) ", attributes: labelAttributes))
            result.append(NSAttributedString(string: metric.value, attributes: [
                .font: metric.font,
                .foregroundColor: metric.color
            ]))
        }
        if metrics.isEmpty {
            result.append(NSAttributedString(string: "—", attributes: labelAttributes))
        }
        return result
    }

    /// «0 MB/s» · «425 MB/s» · «2.5 GB/s» (umbral 1000 MB/s, decimal con punto).
    private static func throughputText(_ mbPerSecond: Double) -> String {
        if mbPerSecond >= 1000 {
            return String(format: "%.1f GB/s", mbPerSecond / 1000)
        }
        return String(format: "%.0f MB/s", max(0, mbPerSecond))
    }

    @objc private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
    }
}
