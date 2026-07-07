import XCTest

/// Zero-network regression guard (§7.2) — the enforcement mechanism for the V1
/// privacy promise. Scans app sources and fails on any networking API outside
/// the allowlist (which ships empty). Substring match, deliberately strict.
final class NetworkAuditTests: XCTestCase {
    private static let forbidden = [
        "URLSession", "URLRequest", "NSURLConnection", "CFNetwork",
        "import Network", "NWConnection", "NWListener", "NWBrowser",
        "SCNetworkReachability", "MultipeerConnectivity",
    ]

    func testZeroNetworkAPIs() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)   // .../EchoMindTests/NetworkAuditTests.swift
            .deletingLastPathComponent()                  // EchoMindTests/
            .deletingLastPathComponent()                  // repo root
        let sourceRoot = repoRoot.appendingPathComponent("EchoMind")   // app target only
        let allowlist = Set(
            (try? String(contentsOf: repoRoot.appendingPathComponent("network-allowlist.txt"), encoding: .utf8))?
                .split(separator: "\n").map(String.init) ?? [])

        var violations: [String] = []
        for file in try swiftFiles(under: sourceRoot) {
            let relative = String(file.path.dropFirst(repoRoot.path.count + 1))
            guard !allowlist.contains(relative) else { continue }
            let lines = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                for token in Self.forbidden where line.contains(token) {
                    violations.append("\(relative):\(index + 1): '\(token)'")
                }
            }
        }
        XCTAssertTrue(violations.isEmpty,
                      "Zero-network promise violated:\n" + violations.joined(separator: "\n"))
    }

    private func swiftFiles(under root: URL) throws -> [URL] {
        var result: [URL] = []
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            result.append(url)
        }
        return result
    }
}
