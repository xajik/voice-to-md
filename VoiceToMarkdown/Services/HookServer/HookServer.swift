import Foundation
import Network

final class HookServer {
    private var listener: NWListener?
    let port: UInt16
    private weak var handlers: HookHandlers?
    private let queue = DispatchQueue(label: "com.vtmd.hookserver", qos: .utility)

    init(port: UInt16 = 7374, handlers: HookHandlers) {
        self.port = port
        self.handlers = handlers
    }

    func start() throws {
        vtmdLog("HOOK_SERVER", "Starting on port \(port)")
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw HookServerError.invalidPort(port)
        }
        listener = try NWListener(using: params, on: nwPort)
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener?.start(queue: queue)
    }

    func stop() {
        vtmdLog("HOOK_SERVER", "Stopped")
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveData(from: connection)
    }

    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 131_072) { [weak self] data, _, isComplete, error in
            guard let data, !data.isEmpty else {
                connection.cancel()
                return
            }
            self?.processRequest(data: data, connection: connection)
        }
    }

    private func processRequest(data: Data, connection: NWConnection) {
        guard let text = String(data: data, encoding: .utf8) else {
            respond(to: connection, status: 400, json: ["error": "invalid encoding"])
            return
        }

        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            respond(to: connection, status: 400, json: ["error": "bad request"])
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            respond(to: connection, status: 400, json: ["error": "bad request line"])
            return
        }

        let method = parts[0]
        let path = parts[1].components(separatedBy: "?").first ?? parts[1]

        let body: Data
        if let range = text.range(of: "\r\n\r\n") {
            body = String(text[range.upperBound...]).data(using: .utf8) ?? Data()
        } else {
            body = Data()
        }

        let result = handlers?.handle(method: method, path: path, body: body) ?? (404, ["error": "no handlers"])
        vtmdLog("HOOK_SERVER", "\(method) \(path) → \(result.0)")
        respond(to: connection, status: result.0, json: result.1)
    }

    private func respond(to connection: NWConnection, status: Int, json: [String: Any]) {
        let bodyData = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        let statusLine: String
        switch status {
        case 200: statusLine = "200 OK"
        case 400: statusLine = "400 Bad Request"
        case 404: statusLine = "404 Not Found"
        default: statusLine = "\(status)"
        }
        let header = "HTTP/1.1 \(statusLine)\r\nContent-Type: application/json\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var response = header.data(using: .utf8)!
        response.append(bodyData)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}

enum HookServerError: Error {
    case invalidPort(UInt16)
}
