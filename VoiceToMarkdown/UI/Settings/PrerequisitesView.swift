import SwiftUI

struct Prerequisite: Identifiable {
    let id = UUID()
    let name: String
    let installHint: String
    var isAvailable: Bool
}

struct PrerequisitesView: View {
    @State private var prerequisites: [Prerequisite] = [
        Prerequisite(name: "whisper-cli", installHint: "brew install whisper-cpp", isAvailable: false),
        Prerequisite(name: "ffmpeg", installHint: "brew install ffmpeg", isAvailable: false)
    ]

    var allMet: Bool { prerequisites.allSatisfy(\.isAvailable) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: allMet ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(allMet ? .green : .orange)
                Text(allMet ? "All dependencies ready" : "Missing dependencies")
                    .font(.headline)
            }

            ForEach($prerequisites) { $prereq in
                HStack {
                    Image(systemName: prereq.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(prereq.isAvailable ? .green : .red)
                    Text(prereq.name)
                        .font(.body.monospaced())
                    if !prereq.isAvailable {
                        Spacer()
                        Text(prereq.installHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button("Check Again") { Task { await check() } }
                .buttonStyle(.bordered)
        }
        .padding()
        .task { await check() }
    }

    private func check() async {
        for idx in prerequisites.indices {
            let name = prerequisites[idx].name
            let available = await isAvailable(name)
            prerequisites[idx].isAvailable = available
        }
    }

    private func isAvailable(_ name: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
