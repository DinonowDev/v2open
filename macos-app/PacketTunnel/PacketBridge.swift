import Darwin
import Foundation
import Network
import NetworkExtension

final class PacketBridge {
    let socksPort: UInt16
    private let queue = DispatchQueue(label: "v2open.packet-bridge")
    private var flow: NEPacketTunnelFlow?
    private var running = true
    private var tcp: [String: TCPFlow] = [:]
    private var udpControl: Int32 = -1
    private var udpRelay: sockaddr_storage?
    private var udpMap: [String: UDPFlow] = [:]

    init(socksPort: UInt16) { self.socksPort = socksPort }

    func start(flow: NEPacketTunnelFlow?) {
        self.flow = flow
        readMore()
    }

    func stop() {
        running = false
        queue.sync {
            tcp.values.forEach { Darwin.close($0.socket) }
            tcp.removeAll()
            if udpControl >= 0 { Darwin.close(udpControl) }
            udpMap.values.forEach { Darwin.close($0.socket) }
            udpMap.removeAll()
        }
    }

    private func readMore() {
        flow?.readPackets { [weak self] packets, _ in
            guard let self, self.running else { return }
            self.queue.async {
                for packet in packets { self.ingest(packet) }
            }
            self.readMore()
        }
    }

    private func ingest(_ packet: Data) {
        guard packet.count >= 20 else { return }
        let version = packet[0] >> 4
        if version == 4 { ingest4(packet) }
        else if version == 6 { ingest6(packet) }
    }

    private func ingest4(_ packet: Data) {
        let ihl = Int(packet[0] & 0x0f) * 4
        guard packet.count >= ihl else { return }
        let proto = packet[9]
        let src = Data(packet[12..<16])
        let dst = Data(packet[16..<20])
        let payload = packet.subdata(in: ihl..<packet.count)
        if proto == 6 { handleTCP(src: src, dst: dst, segment: payload, v6: false) }
        else if proto == 17 { handleUDP(src: src, dst: dst, segment: payload, v6: false) }
    }

    private func ingest6(_ packet: Data) {
        guard packet.count >= 40 else { return }
        let proto = packet[6]
        let src = Data(packet[8..<24])
        let dst = Data(packet[24..<40])
        let payload = packet.subdata(in: 40..<packet.count)
        if proto == 6 { handleTCP(src: src, dst: dst, segment: payload, v6: true) }
        else if proto == 17 { handleUDP(src: src, dst: dst, segment: payload, v6: true) }
    }

    private func handleTCP(src: Data, dst: Data, segment: Data, v6: Bool) {
        guard segment.count >= 20 else { return }
        let sport = read16(segment, 0)
        let dport = read16(segment, 2)
        let seq = read32(segment, 4)
        let flags = segment[13]
        let offset = Int(segment[12] >> 4) * 4
        guard segment.count >= offset else { return }
        let data = segment.subdata(in: offset..<segment.count)
        let key = flowKey(src, sport, dst, dport)
        if flags & 0x02 != 0 && flags & 0x10 == 0 {
            guard tcp[key] == nil, let socket = socksConnect(host: addressString(dst, v6: v6), port: dport) else { return }
            var flow = TCPFlow(socket: socket, clientSeq: seq &+ 1, ourSeq: UInt32.random(in: 1...UInt32.max), src: src, dst: dst, sport: sport, dport: dport, v6: v6)
            sendTCP(&flow, flags: 0x12, payload: Data())
            tcp[key] = flow
            pump(key)
            return
        }
        guard var flow = tcp[key] else { return }
        if flags & 0x04 != 0 {
            Darwin.close(flow.socket)
            tcp[key] = nil
            return
        }
        if seq == flow.clientSeq && !data.isEmpty {
            _ = data.withUnsafeBytes { Darwin.write(flow.socket, $0.baseAddress, data.count) }
            flow.clientSeq = flow.clientSeq &+ UInt32(data.count)
            sendTCP(&flow, flags: 0x10, payload: Data())
        }
        if flags & 0x01 != 0 {
            flow.clientSeq = flow.clientSeq &+ 1
            sendTCP(&flow, flags: 0x11, payload: Data())
            Darwin.close(flow.socket)
            tcp[key] = nil
            return
        }
        tcp[key] = flow
    }

    private func pump(_ key: String) {
        guard let socket = tcp[key]?.socket else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 1400)
            while let self, self.running {
                let n = Darwin.read(socket, &buffer, buffer.count)
                if n <= 0 { break }
                let payload = Data(buffer.prefix(n))
                self.queue.async {
                    guard var flow = self.tcp[key] else { return }
                    self.sendTCP(&flow, flags: 0x18, payload: payload)
                    self.tcp[key] = flow
                }
            }
        }
    }

    private func sendTCP(_ flow: inout TCPFlow, flags: UInt8, payload: Data) {
        let packet = tcpPacket(flow: flow, flags: flags, payload: payload)
        flow.ourSeq = flow.ourSeq &+ UInt32(payload.count) &+ ((flags & 0x03) != 0 && flags != 0x10 ? 1 : 0)
        write(packet, v6: flow.v6)
    }

    private func handleUDP(src: Data, dst: Data, segment: Data, v6: Bool) {
        guard segment.count >= 8 else { return }
        let sport = read16(segment, 0)
        let dport = read16(segment, 2)
        let body = segment.subdata(in: 8..<segment.count)
        let key = flowKey(src, sport, dst, dport)
        if udpMap[key] == nil {
            guard let socket = udpAssociate() else { return }
            udpMap[key] = UDPFlow(socket: socket, src: src, dst: dst, sport: sport, dport: dport, v6: v6)
            pumpUDP(key)
        }
        guard let relay = udpRelay, let flow = udpMap[key] else { return }
        var packet = Data([0, 0, 0, v6 ? 4 : 1])
        packet.append(dst)
        packet.append(contentsOf: dport.bigEndianBytes)
        packet.append(body)
        _ = packet.withUnsafeBytes { raw in
            withUnsafePointer(to: relay) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.sendto(flow.socket, raw.baseAddress, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_storage>.size))
                }
            }
        }
    }

    private func pumpUDP(_ key: String) {
        guard let socket = udpMap[key]?.socket else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 2048)
            while let self, self.running {
                let n = Darwin.recv(socket, &buffer, buffer.count, 0)
                if n < 10 { if n <= 0 { break }; continue }
                let data = Data(buffer.prefix(n))
                guard data[2] == 0 else { continue }
                let atyp = data[3]
                var offset = 4
                if atyp == 1 { offset += 4 } else if atyp == 4 { offset += 16 } else if atyp == 3 { offset += 1 + Int(data[4]) }
                offset += 2
                guard offset <= data.count else { continue }
                let payload = data.subdata(in: offset..<data.count)
                self.queue.async {
                    guard let flow = self.udpMap[key] else { return }
                    self.write(self.udpPacket(flow: flow, payload: payload), v6: flow.v6)
                }
            }
        }
    }

    private func write(_ packet: Data, v6: Bool) {
        flow?.writePackets([packet], withProtocols: [NSNumber(value: v6 ? AF_INET6 : AF_INET)])
    }

    private func socksConnect(host: String, port: UInt16) -> Int32? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = socksPort.bigEndian
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard ok == 0 else { Darwin.close(fd); return nil }
        var hello: [UInt8] = [5, 1, 0]
        guard Darwin.send(fd, &hello, 3, 0) == 3, readFull(fd, 2)?[1] == 0 else { Darwin.close(fd); return nil }
        var request = Data([5, 1, 0])
        if let ipv4 = IPv4Address(host) {
            request.append(1)
            request.append(contentsOf: ipv4.rawValue)
        } else if let ipv6 = IPv6Address(host) {
            request.append(4)
            request.append(contentsOf: ipv6.rawValue)
        } else {
            let bytes = Array(host.utf8)
            request.append(3)
            request.append(UInt8(bytes.count))
            request.append(contentsOf: bytes)
        }
        request.append(contentsOf: port.bigEndianBytes)
        _ = request.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, request.count, 0) }
        guard let reply = readFull(fd, 4), reply[1] == 0 else { Darwin.close(fd); return nil }
        let skip: Int
        switch reply[3] {
        case 1: skip = 4
        case 4: skip = 16
        case 3: skip = Int(readFull(fd, 1)?[0] ?? 0)
        default: Darwin.close(fd); return nil
        }
        _ = readFull(fd, skip + 2)
        return fd
    }

    private func udpAssociate() -> Int32? {
        if udpControl >= 0, let existing = udpMap.values.first?.socket { return existing }
        guard let control = socksConnect(host: "0.0.0.0", port: 0) else { return nil }
        // socksConnect used CONNECT. Open a dedicated UDP ASSOCIATE instead.
        Darwin.close(control)
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = socksPort.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else { Darwin.close(fd); return nil }
        var hello: [UInt8] = [5, 1, 0]
        guard Darwin.send(fd, &hello, 3, 0) == 3, readFull(fd, 2)?[1] == 0 else { Darwin.close(fd); return nil }
        let request: [UInt8] = [5, 3, 0, 1, 0, 0, 0, 0, 0, 0]
        _ = Darwin.send(fd, request, request.count, 0)
        guard let head = readFull(fd, 4), head[1] == 0 else { Darwin.close(fd); return nil }
        var relay = sockaddr_storage()
        if head[3] == 1, let rest = readFull(fd, 6) {
            var v4 = sockaddr_in()
            v4.sin_family = sa_family_t(AF_INET)
            v4.sin_addr.s_addr = rest.withUnsafeBytes { $0.load(as: UInt32.self) }
            v4.sin_port = rest.subdata(in: 4..<6).withUnsafeBytes { $0.load(as: UInt16.self) }
            if v4.sin_addr.s_addr == 0 { v4.sin_addr.s_addr = inet_addr("127.0.0.1") }
            memcpy(&relay, &v4, MemoryLayout<sockaddr_in>.size)
        } else {
            Darwin.close(fd)
            return nil
        }
        let udp = socket(AF_INET, SOCK_DGRAM, 0)
        guard udp >= 0 else { Darwin.close(fd); return nil }
        udpControl = fd
        udpRelay = relay
        return udp
    }

    private func tcpPacket(flow: TCPFlow, flags: UInt8, payload: Data) -> Data {
        var tcp = Data(count: 20)
        write16(&tcp, 0, flow.dport)
        write16(&tcp, 2, flow.sport)
        write32(&tcp, 4, flow.ourSeq)
        write32(&tcp, 8, flow.clientSeq)
        tcp[12] = 5 << 4
        tcp[13] = flags
        write16(&tcp, 14, 65535)
        tcp.append(payload)
        var pseudo = Data()
        pseudo.append(flow.dst)
        pseudo.append(flow.src)
        pseudo.append(0)
        pseudo.append(6)
        pseudo.append(contentsOf: UInt16(tcp.count).bigEndianBytes)
        write16(&tcp, 16, checksum(pseudo + tcp))
        return ipPacket(src: flow.dst, dst: flow.src, proto: 6, payload: tcp, v6: flow.v6)
    }

    private func udpPacket(flow: UDPFlow, payload: Data) -> Data {
        var udp = Data(count: 8 + payload.count)
        write16(&udp, 0, flow.dport)
        write16(&udp, 2, flow.sport)
        write16(&udp, 4, UInt16(udp.count))
        udp.replaceSubrange(8..<udp.count, with: payload)
        var pseudo = Data()
        pseudo.append(flow.dst)
        pseudo.append(flow.src)
        pseudo.append(0)
        pseudo.append(17)
        pseudo.append(contentsOf: UInt16(udp.count).bigEndianBytes)
        write16(&udp, 6, checksum(pseudo + udp))
        return ipPacket(src: flow.dst, dst: flow.src, proto: 17, payload: udp, v6: flow.v6)
    }

    private func ipPacket(src: Data, dst: Data, proto: UInt8, payload: Data, v6: Bool) -> Data {
        if v6 {
            var header = Data(count: 40)
            header[0] = 0x60
            write16(&header, 4, UInt16(payload.count))
            header[6] = proto
            header[7] = 64
            header.replaceSubrange(8..<24, with: src)
            header.replaceSubrange(24..<40, with: dst)
            header.append(payload)
            return header
        }
        var header = Data(count: 20)
        header[0] = 0x45
        write16(&header, 2, UInt16(20 + payload.count))
        header[8] = 64
        header[9] = proto
        header.replaceSubrange(12..<16, with: src)
        header.replaceSubrange(16..<20, with: dst)
        write16(&header, 10, checksum(header))
        header.append(payload)
        return header
    }
}

private struct TCPFlow {
    var socket: Int32
    var clientSeq: UInt32
    var ourSeq: UInt32
    var src: Data
    var dst: Data
    var sport: UInt16
    var dport: UInt16
    var v6: Bool
}

private struct UDPFlow {
    var socket: Int32
    var src: Data
    var dst: Data
    var sport: UInt16
    var dport: UInt16
    var v6: Bool
}

private func flowKey(_ src: Data, _ sport: UInt16, _ dst: Data, _ dport: UInt16) -> String {
    src.map { String(format: "%02x", $0) }.joined() + ":\(sport)-" + dst.map { String(format: "%02x", $0) }.joined() + ":\(dport)"
}

private func addressString(_ raw: Data, v6: Bool) -> String {
    if v6, let ip = IPv6Address(raw) { return ip.debugDescription }
    if let ip = IPv4Address(raw) { return ip.debugDescription }
    return "0.0.0.0"
}

private func read16(_ data: Data, _ offset: Int) -> UInt16 {
    (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
}

private func read32(_ data: Data, _ offset: Int) -> UInt32 {
    (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16) | (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
}

private func write16(_ data: inout Data, _ offset: Int, _ value: UInt16) {
    data[offset] = UInt8(value >> 8)
    data[offset + 1] = UInt8(value & 0xff)
}

private func write32(_ data: inout Data, _ offset: Int, _ value: UInt32) {
    data[offset] = UInt8((value >> 24) & 0xff)
    data[offset + 1] = UInt8((value >> 16) & 0xff)
    data[offset + 2] = UInt8((value >> 8) & 0xff)
    data[offset + 3] = UInt8(value & 0xff)
}

private func checksum(_ data: Data) -> UInt16 {
    var sum: UInt32 = 0
    var index = 0
    while index + 1 < data.count {
        sum += (UInt32(data[index]) << 8) | UInt32(data[index + 1])
        index += 2
    }
    if index < data.count { sum += UInt32(data[index]) << 8 }
    while sum > 0xffff { sum = (sum & 0xffff) + (sum >> 16) }
    return ~UInt16(sum & 0xffff)
}

private func readFull(_ fd: Int32, _ count: Int) -> Data? {
    var out = Data()
    var buffer = [UInt8](repeating: 0, count: count)
    while out.count < count {
        let n = Darwin.read(fd, &buffer, count - out.count)
        if n <= 0 { return nil }
        out.append(buffer, count: n)
    }
    return out
}

private extension UInt16 {
    var bigEndianBytes: [UInt8] { [UInt8(self >> 8), UInt8(self & 0xff)] }
}
