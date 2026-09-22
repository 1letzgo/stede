import Foundation

extension KeyedDecodingContainer {
    public nonisolated func decodeFlexibleDouble(forKey key: Key) throws -> Double {
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return Double(value)
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Zahl erwartet"
        )
    }

    public nonisolated func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        guard contains(key) else { return nil }
        if try decodeNil(forKey: key) {
            return nil
        }
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return Double(value)
        }
        return nil
    }
}
