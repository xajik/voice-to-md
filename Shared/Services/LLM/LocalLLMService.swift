import Foundation

/// Client for an OpenAI-compatible local inference server (omlx, llama.cpp, LM Studio…).
/// Each transcript flush is one streaming chat-completions call.
final class LocalLLMService {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Models

    struct ModelList: Decodable {
        struct Model: Decodable { let id: String }
        let data: [Model]
    }

    func listModels() async throws -> [String] {
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.timeoutInterval = 5
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LocalLLMError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try JSONDecoder().decode(ModelList.self, from: data).data.map(\.id)
    }

    // MARK: - Formatting

    /// Streams the complete document as it is generated.
    /// Yields cumulative, cleaned output so callers can render partials directly.
    func formatTranscript(
        currentDocument: String, newTranscript: String, model: String, format: OutputFormat
    ) -> AsyncThrowingStream<String, Error> {
        streamCompletion(body: Self.buildRequestBody(
            model: model,
            currentDocument: currentDocument,
            newTranscript: newTranscript,
            format: format
        ))
    }

    /// Streams the complete document with a spoken edit instruction applied.
    func editDocument(
        currentDocument: String, instruction: String, userFocus: String?, model: String, format: OutputFormat
    ) -> AsyncThrowingStream<String, Error> {
        streamCompletion(body: Self.buildEditRequestBody(
            model: model,
            currentDocument: currentDocument,
            instruction: instruction,
            userFocus: userFocus,
            format: format
        ))
    }

    /// Static helper to build a non-streaming chat completion request for fixing raw dictation text.
    /// Returns the cleaned text directly rather than streaming it.
    static let fixTranscriptionSystemPrompt = """
    You are a dictation transcription cleaner. Clean the raw speech-to-text output: \
    remove filler words (um, uh, like, you know, etc.), fix grammar and typos, \
    remove STT noise annotations like (wind blowing) or [silence], \
    preserve the core content and meaning exactly. Maintain the original language. \
    Respond with ONLY the cleaned text — no explanations, no code fences, no thinking out loud. /no_think
    """

    func fixTranscription(transcript: String, model: String) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "stream": false,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": Self.fixTranscriptionSystemPrompt],
                ["role": "user", "content": transcript]
            ]
        ] as [String: Any])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LocalLLMError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return transcript
        }
        let cleaned = Self.cleanOutput(content)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Streams only the newly formatted content to append after `recentContext`.
    func appendTranscript(
        recentContext: String, newTranscript: String, model: String, format: OutputFormat
    ) -> AsyncThrowingStream<String, Error> {
        streamCompletion(body: Self.buildAppendRequestBody(
            model: model,
            recentContext: recentContext,
            newTranscript: newTranscript,
            format: format
        ))
    }

    private func streamCompletion(body: [String: Any]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 300
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await self.session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw LocalLLMError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
                    }

                    var raw = ""
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let delta = Self.parseSSELine(line) else { continue }
                        raw += delta
                        continuation.yield(Self.cleanOutput(raw))
                    }
                    continuation.yield(Self.cleanOutput(raw))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Pure helpers (unit-tested)

    /// `noThink` appends the Qwen-family `/no_think` control token; backends
    /// whose models don't understand it (e.g. Apple Foundation Models) pass false.
    static func systemPrompt(for format: OutputFormat, noThink: Bool = true) -> String {
        """
        You are a voice-to-\(format.languageName) formatting assistant. \
        Each user message is a JSON object with "current_document" and "new_transcript" (raw speech-to-text). \
        Clean the transcript: remove filler words and STT noise annotations like (soft music) or [silence]; \
        fix grammar and typos while preserving the core content and ideas. \
        Integrate the cleaned content into current_document, inferring the document's purpose and structuring it accordingly. \
        \(format.promptExpectations)
        Respond with ONLY the complete updated document — no explanations, no code fences, no thinking out loud.\(noThink ? " /no_think" : "")
        """
    }

    static func editSystemPrompt(for format: OutputFormat, noThink: Bool = true) -> String {
        """
        You are a voice-driven \(format.languageName) editing assistant. \
        Each user message is a JSON object with "current_document", "new_transcript" \
        (a spoken editing instruction, raw speech-to-text), and optionally "user_focus" \
        (text the user currently has selected in the editor). \
        The transcript is an INSTRUCTION to modify the document, not content to add. \
        Interpret the instruction, applying it to the user_focus selection when present, \
        otherwise to the most relevant part of the document. \
        Clean STT noise from the instruction before interpreting it. \
        Make only the requested change; leave the rest of the document untouched. \
        \(format.promptExpectations)
        Respond with ONLY the complete updated document — no explanations, \
        no code fences, no thinking out loud.\(noThink ? " /no_think" : "")
        """
    }

    static func appendSystemPrompt(for format: OutputFormat, noThink: Bool = true) -> String {
        """
        You are a voice-to-\(format.languageName) formatting assistant. \
        Each user message is a JSON object with "recent_context" (the last few sentences \
        of an existing \(format.languageName) document, for continuity only) and "new_transcript" (raw speech-to-text). \
        Clean the transcript: remove filler words and STT noise annotations like (soft music) or [silence]; \
        fix grammar and typos while preserving the core content and ideas. \
        Format it as \(format.languageName) that flows naturally after recent_context. \
        \(format.promptExpectations)
        Respond with ONLY the new content to append — do NOT repeat recent_context, \
        no explanations, no code fences, no thinking out loud.\(noThink ? " /no_think" : "")
        """
    }

    // The user message is the JSON payload the system prompts describe.
    // These builders are the single source of that JSON for every backend
    // (OpenAI-compatible HTTP here, Foundation Models on iOS).

    static func formatUserPayload(currentDocument: String, newTranscript: String) -> String {
        encodePayload([
            "current_document": currentDocument,
            "new_transcript": newTranscript
        ], fallback: newTranscript)
    }

    static func editUserPayload(currentDocument: String, instruction: String, userFocus: String?) -> String {
        var payload = [
            "current_document": currentDocument,
            "new_transcript": instruction
        ]
        if let focus = userFocus, !focus.isEmpty {
            payload["user_focus"] = focus
        }
        return encodePayload(payload, fallback: instruction)
    }

    static func appendUserPayload(recentContext: String, newTranscript: String) -> String {
        encodePayload([
            "recent_context": recentContext,
            "new_transcript": newTranscript
        ], fallback: newTranscript)
    }

    static func buildRequestBody(
        model: String, currentDocument: String, newTranscript: String, format: OutputFormat
    ) -> [String: Any] {
        chatBody(
            model: model,
            systemPrompt: systemPrompt(for: format),
            userContent: formatUserPayload(currentDocument: currentDocument, newTranscript: newTranscript)
        )
    }

    static func buildEditRequestBody(
        model: String, currentDocument: String, instruction: String, userFocus: String?, format: OutputFormat
    ) -> [String: Any] {
        chatBody(
            model: model,
            systemPrompt: editSystemPrompt(for: format),
            userContent: editUserPayload(currentDocument: currentDocument, instruction: instruction, userFocus: userFocus)
        )
    }

    static func buildAppendRequestBody(
        model: String, recentContext: String, newTranscript: String, format: OutputFormat
    ) -> [String: Any] {
        chatBody(
            model: model,
            systemPrompt: appendSystemPrompt(for: format),
            userContent: appendUserPayload(recentContext: recentContext, newTranscript: newTranscript)
        )
    }

    private static func encodePayload(_ payload: [String: String], fallback: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return fallback
    }

    private static func chatBody(
        model: String, systemPrompt: String, userContent: String
    ) -> [String: Any] {
        [
            "model": model,
            "stream": true,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ]
        ]
    }

    /// Last `count` sentences of `text`, for append-mode context. A sentence
    /// ends at `.` `!` `?` or a newline (so headings/list items count as their
    /// own units). Returns the whole text when it has fewer sentences.
    static func lastSentences(_ text: String, count: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard count > 0, !trimmed.isEmpty else { return "" }

        var sentencesFound = 0
        var sawContent = false
        var index = trimmed.endIndex
        while index > trimmed.startIndex {
            let prev = trimmed.index(before: index)
            let char = trimmed[prev]
            if char == "." || char == "!" || char == "?" || char == "\n" {
                if sawContent {
                    sentencesFound += 1
                    if sentencesFound == count {
                        return String(trimmed[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    sawContent = false
                }
            } else if !char.isWhitespace {
                sawContent = true
            }
            index = prev
        }
        return trimmed
    }

    /// Joins streamed append-mode output onto the existing document.
    /// `cleanOutput` trims the delta's edges, so the separator is decided here:
    /// block-level markdown starts a new paragraph; prose continues inline.
    static func joinAppended(base: String, delta: String) -> String {
        let delta = delta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !delta.isEmpty else { return base }
        var base = base
        while let last = base.last, last.isWhitespace { base.removeLast() }
        guard !base.isEmpty else { return delta }
        return base + (startsNewBlock(delta) ? "\n\n" : " ") + delta
    }

    private static func startsNewBlock(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        // "<" covers HTML-fragment output (block tags like <p>, <ul>); a leading
        // "<" in markdown is raw block HTML anyway.
        if "#->*`|<".contains(first) { return true }
        let digits = text.prefix(while: \.isNumber)
        return !digits.isEmpty && text.dropFirst(digits.count).first == "."
    }

    /// Extracts the content delta from one SSE line ("data: {...}"), nil for non-data lines and [DONE].
    static func parseSSELine(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]",
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String else { return nil }
        return content
    }

    /// Strips reasoning blocks and surrounding code fences from (possibly partial) model output.
    static func cleanOutput(_ text: String) -> String {
        var result = text

        // <think>…</think>; an unterminated <think> (mid-stream) hides everything after it
        while let start = result.range(of: "<think>") {
            if let end = result.range(of: "</think>", range: start.upperBound..<result.endIndex) {
                result.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                result.removeSubrange(start.lowerBound..<result.endIndex)
                break
            }
        }

        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        if result.hasPrefix("```") {
            if let firstNewline = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: firstNewline)...])
            } else {
                result = ""
            }
            if result.hasSuffix("```") {
                result = String(result.dropLast(3))
            }
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return result
    }
}

enum LocalLLMError: Error, LocalizedError {
    case badStatus(Int)
    case noModels

    var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            return "Local LLM API error (HTTP \(code)). Is the server running?"
        case .noModels:
            return "Local LLM API reports no available models."
        }
    }
}
