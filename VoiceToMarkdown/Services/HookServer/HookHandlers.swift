import Foundation

final class HookHandlers {
    var onInit: (() -> Void)?
    var onResponse: ((String) -> Void)?
    var onNotification: ((Data) -> Void)?

    func handle(method: String, path: String, body: Data) -> (Int, [String: Any]) {
        switch (method, path) {
        case ("POST", "/hooks/voice-to-md/init"):
            return handleInit(body: body)
        case ("POST", "/hooks/voice-to-md/response"):
            return handleResponse(body: body)
        case ("POST", "/hooks/voice-to-md/notification"):
            return handleNotification(body: body)
        default:
            return (404, ["error": "not found"])
        }
    }

    private func handleInit(body: Data) -> (Int, [String: Any]) {
        DispatchQueue.main.async { self.onInit?() }
        return (200, ["status": "ok"])
    }

    private func handleResponse(body: Data) -> (Int, [String: Any]) {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let markdown = json["markdown"] as? String else {
            return (400, ["error": "missing markdown field"])
        }
        DispatchQueue.main.async { self.onResponse?(markdown) }
        return (200, ["status": "ok"])
    }

    private func handleNotification(body: Data) -> (Int, [String: Any]) {
        DispatchQueue.main.async { self.onNotification?(body) }
        return (200, ["status": "ok"])
    }
}
