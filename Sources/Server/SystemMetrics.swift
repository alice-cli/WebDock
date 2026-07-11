import Foundation
import Darwin

/// Periodic host resource snapshot for the web UI header.
enum SystemMetrics {
    struct Snapshot: Sendable {
        let cpuPercent: Double
        let ramPercent: Double
        let ramUsedGB: Double
        let ramTotalGB: Double
        let diskPercent: Double
        let diskUsedGB: Double
        let diskTotalGB: Double
    }

    private static var previousCPU: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private static let lock = NSLock()

    static func snapshot() -> Snapshot {
        let cpu = cpuUsagePercent()
        let (ramUsed, ramTotal, ramPct) = memoryUsage()
        let (diskUsed, diskTotal, diskPct) = diskUsage()

        return Snapshot(
            cpuPercent: cpu,
            ramPercent: ramPct,
            ramUsedGB: ramUsed,
            ramTotalGB: ramTotal,
            diskPercent: diskPct,
            diskUsedGB: diskUsed,
            diskTotalGB: diskTotal
        )
    }

    static func jsonMessage() -> String? {
        let s = snapshot()
        let dict: [String: Any] = [
            "type": "metrics",
            "cpu": round1(s.cpuPercent),
            "ram": round1(s.ramPercent),
            "ramUsedGB": round1(s.ramUsedGB),
            "ramTotalGB": round1(s.ramTotalGB),
            "disk": round1(s.diskPercent),
            "diskUsedGB": round1(s.diskUsedGB),
            "diskTotalGB": round1(s.diskTotalGB),
        ]
        return JSONMessage.encode(dict)
    }

    // MARK: - CPU

    private static func cpuUsagePercent() -> Double {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCpuInfo
        )
        guard result == KERN_SUCCESS, let info = cpuInfo else { return 0 }

        defer {
            let size = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        var user: UInt32 = 0, system: UInt32 = 0, idle: UInt32 = 0, nice: UInt32 = 0
        let load = UnsafeRawPointer(info).bindMemory(to: processor_cpu_load_info.self, capacity: Int(numCPUs))
        for i in 0..<Int(numCPUs) {
            user += load[i].cpu_ticks.0
            system += load[i].cpu_ticks.1
            idle += load[i].cpu_ticks.2
            nice += load[i].cpu_ticks.3
        }

        lock.lock()
        let prev = previousCPU
        previousCPU = (user, system, idle, nice)
        lock.unlock()

        guard let prev else { return 0 }
        let dUser = Double(user &- prev.user)
        let dSystem = Double(system &- prev.system)
        let dIdle = Double(idle &- prev.idle)
        let dNice = Double(nice &- prev.nice)
        let total = dUser + dSystem + dIdle + dNice
        guard total > 0 else { return 0 }
        return min(100, max(0, (dUser + dSystem + dNice) / total * 100))
    }

    // MARK: - Memory

    private static func memoryUsage() -> (usedGB: Double, totalGB: Double, percent: Double) {
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else {
            let tGB = total / 1_073_741_824
            return (0, tGB, 0)
        }
        let page = Double(vm_kernel_page_size)
        // Active + wired + compressed ≈ used by apps/system (approx).
        let usedPages = Double(stats.active_count + stats.wire_count + stats.compressor_page_count)
        let used = usedPages * page
        let tGB = total / 1_073_741_824
        let uGB = used / 1_073_741_824
        let pct = total > 0 ? min(100, used / total * 100) : 0
        return (uGB, tGB, pct)
    }

    // MARK: - Disk

    private static func diskUsage() -> (usedGB: Double, totalGB: Double, percent: Double) {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let total = attrs[.systemSize] as? NSNumber,
              let free = attrs[.systemFreeSize] as? NSNumber
        else { return (0, 0, 0) }
        let t = total.doubleValue
        let f = free.doubleValue
        let used = max(0, t - f)
        let tGB = t / 1_073_741_824
        let uGB = used / 1_073_741_824
        let pct = t > 0 ? used / t * 100 : 0
        return (uGB, tGB, pct)
    }

    private static func round1(_ v: Double) -> Double {
        (v * 10).rounded() / 10
    }
}
