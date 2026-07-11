import Foundation
import Darwin

enum NetworkInfo {
    /// Non-loopback IPv4 addresses for LAN URL display.
    static func lanIPv4Addresses() -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let iface = ptr {
            defer { ptr = iface.pointee.ifa_next }
            let flags = Int32(iface.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let addr = iface.pointee.ifa_addr else { continue }
            guard addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                let ip = String(cString: hostname)
                if !ip.isEmpty, !addresses.contains(ip) {
                    addresses.append(ip)
                }
            }
        }
        return addresses
    }
}
