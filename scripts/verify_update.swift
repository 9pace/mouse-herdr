// Independently verify that the archive is signed by the public key embedded in the app.
import CryptoKit
import Foundation

guard CommandLine.arguments.count == 4,
      let key = Data(base64Encoded: CommandLine.arguments[1]),
      let signature = Data(base64Encoded: CommandLine.arguments[3]) else {
    fputs("Usage: verify_update.swift <public-key> <archive> <signature>\n", stderr)
    exit(2)
}
do {
    let verifier = try Curve25519.Signing.PublicKey(rawRepresentation: key)
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
    guard verifier.isValidSignature(signature, for: data) else {
        fputs("Update signature does not match the app's public key.\n", stderr)
        exit(1)
    }
} catch {
    fputs("Could not verify update signature.\n", stderr)
    exit(1)
}
