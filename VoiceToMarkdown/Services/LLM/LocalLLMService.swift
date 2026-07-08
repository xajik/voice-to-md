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

    /// Streams the complete markdown document as it is generated.
    /// Yields cumulative, cleaned output so callers can render partials directly.
    func formatTranscript(currentMarkdown: String, newTranscript: String, model: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 300
                    request.httpBody = try JSONSerialization.data(withJSONObject: Self.buildRequestBody(
                        model: model,
                        currentMarkdown: currentMarkdown,
                        newTranscript: newTranscript
                    ))

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

    static let systemPrompt = """
    You are a voice-to-markdown formatting assistant. \
    Each user message is a JSON object with "current_markdown" and "new_transcript" (raw speech-to-text). \
    Clean the transcript: remove filler words and STT noise annotations like (soft music) or [silence]; \
    fix grammar and typos while preserving the core content and ideas. \
    Integrate the cleaned content into current_markdown, inferring the document's purpose and structuring it accordingly. \
    Respond with ONLY the complete updated markdown document — no explanations, no code fences, no thinking out loud. /no_think
    """

    static func buildRequestBody(model: String, currentMarkdown: String, newTranscript: String) -> [String: Any] {
        let payload: [String: String] = [
            "current_markdown": currentMarkdown,
            "new_transcript": newTranscript
        ]
        let userContent: String
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let str = String(data: data, encoding: .utf8) {
            userContent = str
        } else {
            userContent = newTranscript
        }
        return [
            "model": model,
            "stream": true,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ]
        ]
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
