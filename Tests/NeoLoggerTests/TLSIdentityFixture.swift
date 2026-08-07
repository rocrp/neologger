import Foundation
import Security

enum TLSFixtureError: Error {
  case opensslFailed(command: String, status: Int32, output: String)
  case importFailed(OSStatus)
  case noIdentityInBundle
}

/// True when `SecPKCS12Import` can keep the imported key in process memory
/// (`kSecImportToMemoryOnly`, macOS 15 / iOS 18). Below that every import
/// lands in the user's default keychain, so the TLS test opts out rather
/// than leaving a certificate and private key behind on each run.
var supportsKeychainFreePKCS12Import: Bool {
  if #available(macOS 15.0, iOS 18.0, *) { return true }
  return false
}

/// Builds a throwaway self-signed TLS identity for loopback tests.
///
/// NSLogger viewers serve a self-signed certificate, so the test far end has
/// to do the same for `NWTransport`'s TLS branch to mean anything. Generated
/// per call with the system `openssl` (no public API self-signs a
/// certificate) and imported memory-only, so nothing touches the keychain.
///
/// RSA rather than EC: an EC key survives the PKCS#12 round trip but its
/// private key comes back NULL under `kSecImportToMemoryOnly`, and the TLS
/// stack then traps in `SecKeyCopyExternalRepresentation`.
///
/// Synchronous, and briefly blocking — keygen plus two short-lived `openssl`
/// invocations run in well under a second, which beats hopping executors to
/// keep a test fixture off the cooperative pool.
@available(macOS 15.0, iOS 18.0, *)
func makeSelfSignedTLSIdentity(commonName: String = "neologger-tests") throws -> SecIdentity {
  let directory = URL.temporaryDirectory.appending(path: "neologger-tls-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }

  let key = directory.appending(path: "key.pem")
  let certificate = directory.appending(path: "cert.pem")
  let bundle = directory.appending(path: "identity.p12")
  let passphrase = "neologger"

  try openssl([
    "req", "-x509", "-newkey", "rsa:2048",
    "-keyout", key.path, "-out", certificate.path,
    "-days", "1", "-nodes", "-subj", "/CN=\(commonName)",
  ])
  try openssl([
    "pkcs12", "-export", "-out", bundle.path,
    "-inkey", key.path, "-in", certificate.path,
    "-passout", "pass:\(passphrase)",
  ])

  var items: CFArray?
  let status = SecPKCS12Import(
    try Data(contentsOf: bundle) as CFData,
    [
      kSecImportExportPassphrase as String: passphrase,
      kSecImportToMemoryOnly as String: kCFBooleanTrue as Any,
    ] as CFDictionary,
    &items
  )
  guard status == errSecSuccess else { throw TLSFixtureError.importFailed(status) }
  // `as?` is meaningless for a CoreFoundation type (it always succeeds), so
  // the type is checked by CFTypeID and only then cast.
  guard
    let entries = items as? [[String: Any]],
    let entry = entries.first?[kSecImportItemIdentity as String],
    CFGetTypeID(entry as CFTypeRef) == SecIdentityGetTypeID()
  else { throw TLSFixtureError.noIdentityInBundle }
  return entry as! SecIdentity
}

private func openssl(_ arguments: [String]) throws {
  let process = Process()
  process.executableURL = URL(filePath: "/usr/bin/openssl")
  process.arguments = arguments
  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = pipe
  try process.run()
  let output = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    throw TLSFixtureError.opensslFailed(
      command: arguments.joined(separator: " "),
      status: process.terminationStatus,
      output: String(decoding: output, as: UTF8.self)
    )
  }
}
