import Foundation

public enum DomainSanitizer {
    private static let commonTwoPartPublicSuffixes: Set<String> = [
        "ac.uk", "co.uk", "gov.uk", "ltd.uk", "me.uk", "net.uk",
        "org.uk", "plc.uk",
        "co.ie", "edu.ie", "gov.ie", "net.ie", "org.ie",
        "com.au", "edu.au", "gov.au", "net.au", "org.au", "asn.au",
        "id.au",
        "co.nz", "govt.nz", "net.nz", "org.nz", "ac.nz",
        "com.br", "com.cn", "com.hk", "com.mx", "com.my", "com.sg",
        "com.tr", "com.tw",
        "co.in", "co.jp", "co.kr", "co.za"
    ]

    public static func hostname(from rawValue: String) -> String? {
        var trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if trimmed.hasPrefix("*.") {
            trimmed.removeFirst(2)
        }
        trimmed = trimmed.trimmingCharacters(
            in: CharacterSet(charactersIn: ".")
        )

        guard !trimmed.isEmpty else {
            return nil
        }

        let candidate: String
        if trimmed.contains("://") {
            candidate = URLComponents(string: trimmed)?.host ?? ""
        } else {
            candidate = URLComponents(string: "https://\(trimmed)")?.host ?? ""
        }

        let normalized = candidate
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()

        guard !normalized.isEmpty,
              normalized.count <= 253,
              normalized.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              isValidHostname(normalized)
        else {
            return nil
        }

        return normalized
    }

    public static func registrableDomain(from rawValue: String) -> String? {
        guard let host = hostname(from: rawValue) else {
            return nil
        }

        if host == "localhost" || IPv4Address.isValid(host) || host.contains(":") {
            return host
        }

        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 2 else {
            return host
        }

        let lastTwo = labels.suffix(2).joined(separator: ".")
        if commonTwoPartPublicSuffixes.contains(lastTwo), labels.count >= 3 {
            return labels.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }

    public static func aggregateKey(from rawValue: String) -> String? {
        registrableDomain(from: rawValue)
    }

    private static func isValidHostname(_ value: String) -> Bool {
        if value == "localhost" || IPv4Address.isValid(value)
            || value.contains(":") {
            return true
        }

        return value.split(
            separator: ".",
            omittingEmptySubsequences: false
        ).allSatisfy { label in
            guard !label.isEmpty,
                  label.count <= 63,
                  label.first?.isASCIIAlphanumeric == true,
                  label.last?.isASCIIAlphanumeric == true
            else {
                return false
            }
            return label.allSatisfy {
                $0.isASCIIAlphanumeric || $0 == "-"
            }
        }
    }
}

private extension Character {
    var isASCIIAlphanumeric: Bool {
        unicodeScalars.count == 1
            && unicodeScalars.allSatisfy {
                (48...57).contains($0.value)
                    || (65...90).contains($0.value)
                    || (97...122).contains($0.value)
            }
    }
}

private enum IPv4Address {
    static func isValid(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            return false
        }

        return parts.allSatisfy { part in
            guard let number = Int(part), number >= 0, number <= 255 else {
                return false
            }
            return String(number) == part || part == "0"
        }
    }
}
