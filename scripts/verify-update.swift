// Verify the published archive against the app's public key; no private key is read.
import CryptoKit
import Foundation

do {
    guard CommandLine.arguments.count == 4,
          let publicData = Data(base64Encoded: CommandLine.arguments[2]), publicData.count == 32,
          let signature = Data(base64Encoded: CommandLine.arguments[3]), signature.count == 64 else {
        throw CocoaError(.fileReadCorruptFile)
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicData)
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    guard key.isValidSignature(signature, for: archive) else { throw CocoaError(.fileReadCorruptFile) }
    print("PASS: update archive EdDSA signature is valid.")
} catch {
    fputs("Update signature verification failed.\n", stderr)
    exit(1)
}
