#!/usr/bin/env swift

import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 4 else {
    fail("Usage: verify_sparkle_ed_signature.swift PUBLIC_KEY_BASE64 SIGNATURE_BASE64 FILE")
}

guard let publicKeyData = Data(base64Encoded: CommandLine.arguments[1]) else {
    fail("Invalid Sparkle public key encoding.")
}
guard let signatureData = Data(base64Encoded: CommandLine.arguments[2]) else {
    fail("Invalid Sparkle signature encoding.")
}

let fileURL = URL(fileURLWithPath: CommandLine.arguments[3])
let archiveData: Data
do {
    archiveData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
} catch {
    fail("Unable to read update archive: \(error.localizedDescription)")
}

do {
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    guard publicKey.isValidSignature(signatureData, for: archiveData) else {
        fail("Sparkle update signature does not match the application's SUPublicEDKey.")
    }
} catch {
    fail("Unable to verify Sparkle update signature: \(error.localizedDescription)")
}
