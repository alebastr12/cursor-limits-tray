import Foundation
import Security
import CryptoKit

/// Stable identifier of the current signing identity.
///
/// Uses the **designated requirement** rather than the per-build cdhash: with a
/// stable certificate the ID survives rebuilds, while an ad-hoc signature (which
/// changes every build) is treated as a new identity.
enum CodeSignature {
    static func stableID() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode
        else { return nil }

        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
              let requirement
        else { return nil }

        var data: CFData?
        guard SecRequirementCopyData(requirement, [], &data) == errSecSuccess,
              let data
        else { return nil }

        return SHA256.hash(data: data as Data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
