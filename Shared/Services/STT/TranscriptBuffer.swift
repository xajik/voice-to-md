import Foundation

actor TranscriptBuffer {
    private var accumulated: [String] = []
    private var pending: [String] = []
    private(set) var agentBusy = false

    let minWordsToFlush = 30

    func add(_ text: String) -> Bool {
        if agentBusy {
            pending.append(text)
        } else {
            accumulated.append(text)
        }
        return !agentBusy && wordCount(in: accumulated) > minWordsToFlush
    }

    func flush() -> String {
        guard !accumulated.isEmpty else { return "" }
        let result = accumulated.joined(separator: " ")
        accumulated = []
        agentBusy = true
        return result
    }

    func flushAll() -> String {
        let combined = (accumulated + pending).joined(separator: " ")
        guard !combined.isEmpty else { return "" }
        accumulated = []
        pending = []
        agentBusy = true
        return combined
    }

    func agentDone() -> Bool {
        agentBusy = false
        if !pending.isEmpty {
            accumulated.append(contentsOf: pending)
            pending = []
            return wordCount(in: accumulated) >= minWordsToFlush
        }
        return false
    }

    func hasPending() -> Bool {
        !pending.isEmpty || !accumulated.isEmpty
    }

    func clear() {
        accumulated = []
        pending = []
        agentBusy = false
    }

    // Single definition of "a word" — also used by the UI badge so the
    // displayed count matches the flush threshold.
    static func wordCount(in text: String) -> Int {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    private func wordCount(in chunks: [String]) -> Int {
        Self.wordCount(in: chunks.joined(separator: " "))
    }
}
