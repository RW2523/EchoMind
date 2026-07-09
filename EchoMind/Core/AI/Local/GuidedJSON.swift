import Foundation
import FoundationModels

/// Bridges a non-Apple LLM into Apple's `@Generable` world (V2 §B2). Apple's
/// `LanguageModelSession` does constrained decoding for us; a raw local model
/// does not — so we reuse the *same* `GenerationSchema` to (a) tell the model the
/// exact JSON shape to emit and (b) parse its reply back through
/// `GeneratedContent(json:)` into the very same `Generable` type the rest of the
/// app already consumes. No parallel DTOs, no schema drift.
nonisolated enum GuidedJSON {
    /// The type's generation schema, serialized as JSON for embedding in a prompt.
    static func schemaJSON<T: Generable>(for type: T.Type) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(type.generationSchema)
        return String(decoding: data, as: UTF8.self)
    }

    /// Parse a model completion into `T`: isolate the JSON object, then round-trip
    /// through `GeneratedContent`. Throws if no object is present or it doesn't
    /// satisfy the schema — the caller retries.
    static func decode<T: Generable>(_ raw: String, as type: T.Type) throws -> T {
        guard let json = extractJSONObject(raw) else {
            throw LocalLLMEngineError.generationFailed("no JSON object in model output")
        }
        let content = try GeneratedContent(json: json)
        return try T(content)
    }

    /// System-message suffix that instructs the model to emit schema-valid JSON.
    static func instruction<T: Generable>(for type: T.Type) throws -> String {
        let schema = try schemaJSON(for: type)
        return """
        You MUST reply with a single JSON object and nothing else — no prose, no \
        markdown fences. The object must validate against this JSON schema:
        \(schema)
        """
    }

    /// Extract the first balanced `{ … }` object from arbitrary text, ignoring
    /// braces inside string literals. Handles chatty models that wrap JSON in
    /// commentary or ``` fences.
    static func extractJSONObject(_ s: String) -> String? {
        guard let start = s.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var i = start
        while i < s.endIndex {
            let c = s[i]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else {
                switch c {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 { return String(s[start...i]) }
                default: break
                }
            }
            i = s.index(after: i)
        }
        return nil
    }
}
