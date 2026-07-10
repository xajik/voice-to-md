import Foundation

/// Format expectations + a short transcript→output example, appended to
/// every agent-mode system prompt (see `FormatPrompt`, `EditPrompt`, `AppendPrompt`).
extension OutputFormat {
    var promptExpectations: String {
        switch self {
        case .txt:
            return """
            Output MUST be plain text only — no markdown syntax (#, *, `), no HTML tags. \
            Separate paragraphs with blank lines; use '-' for simple lists. \
            Example — transcript: "\(Self.exampleTranscript)" → output:
            Plan

            - Login page
            - API
            - Testing
            """
        case .md:
            return """
            Output MUST be GitHub-flavored Markdown — use headings, lists, and emphasis where appropriate. \
            Example — transcript: "\(Self.exampleTranscript)" → output:
            ## Plan

            - Login page
            - API
            - Testing
            """
        case .html:
            return """
            Output MUST be a clean semantic HTML fragment — use <h2>, <p>, <ul>/<li>, <strong> etc.; \
            no <html>/<head>/<body> wrapper, no inline styles, no scripts. \
            Example — transcript: "\(Self.exampleTranscript)" → output:
            <h2>Plan</h2>
            <ul>
              <li>Login page</li>
              <li>API</li>
              <li>Testing</li>
            </ul>
            """
        }
    }

    private static let exampleTranscript =
        "um so we need three things uh first the login page then the API and (coughs) testing"
}
