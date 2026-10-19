import Foundation
import CryptoKit

// Reject a missing or mismatched CI secret before publishing an unusable update.
do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard let encoded = String(data: input, encoding: .utf8),
          let seed = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
          seed.count == 32 else { throw CocoaError(.fileReadCorruptFile) }
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    guard plist?["SUPublicEDKey"] as? String == key.publicKey.rawRepresentation.base64EncodedString()
    else { throw CocoaError(.fileReadCorruptFile) }
    print("PASS: Sparkle private key matches the app public key")
} catch {
    fputs("Sparkle signing key is missing, malformed, or does not match SUPublicEDKey.\n", stderr)
    exit(1)
}
