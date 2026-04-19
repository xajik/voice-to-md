import XCTest
@testable import VoiceToMarkdown

final class HookHandlersTests: XCTestCase {

    // MARK: - Routing

    func testUnknownRouteReturns404() {
        let handlers = HookHandlers()
        let (status, body) = handlers.handle(method: "GET", path: "/unknown", body: Data())
        XCTAssertEqual(status, 404)
        XCTAssertNotNil(body["error"])
    }

    func testWrongMethodReturns404() {
        let handlers = HookHandlers()
        let (status, _) = handlers.handle(method: "GET", path: "/hooks/voice-to-md/init", body: Data())
        XCTAssertEqual(status, 404)
    }

    // MARK: - /hooks/voice-to-md/init

    func testInitRouteReturns200() {
        let handlers = HookHandlers()
        let (status, body) = handlers.handle(method: "POST", path: "/hooks/voice-to-md/init", body: Data())
        XCTAssertEqual(status, 200)
        XCTAssertEqual(body["status"] as? String, "ok")
    }

    func testInitRouteFiresCallback() {
        let handlers = HookHandlers()
        let expectation = expectation(description: "onInit called")
        handlers.onInit = { expectation.fulfill() }
        _ = handlers.handle(method: "POST", path: "/hooks/voice-to-md/init", body: Data())
        waitForExpectations(timeout: 1)
    }

    func testInitRouteFiresCallbackOnce() {
        let handlers = HookHandlers()
        var callCount = 0
        handlers.onInit = { callCount += 1 }
        _ = handlers.handle(method: "POST", path: "/hooks/voice-to-md/init", body: Data())
        let expectation = expectation(description: "main queue flush")
        DispatchQueue.main.async { expectation.fulfill() }
        waitForExpectations(timeout: 1)
        XCTAssertEqual(callCount, 1)
    }

    // MARK: - /hooks/voice-to-md/response

    func testResponseRouteReturns200WithValidBody() {
        let handlers = HookHandlers()
        let body = try! JSONSerialization.data(withJSONObject: ["markdown": "# Hello"])
        let (status, resp) = handlers.handle(method: "POST", path: "/hooks/voice-to-md/response", body: body)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(resp["status"] as? String, "ok")
    }

    func testResponseRouteParsesMarkdown() {
        let handlers = HookHandlers()
        let expected = "# My Document\n\nContent here."
        let body = try! JSONSerialization.data(withJSONObject: ["markdown": expected])

        let expectation = expectation(description: "onResponse called")
        handlers.onResponse = { markdown in
            XCTAssertEqual(markdown, expected)
            expectation.fulfill()
        }

        _ = handlers.handle(method: "POST", path: "/hooks/voice-to-md/response", body: body)
        waitForExpectations(timeout: 1)
    }

    func testResponseRouteMissingMarkdownFieldReturns400() {
        let handlers = HookHandlers()
        let body = try! JSONSerialization.data(withJSONObject: ["other": "value"])
        let (status, resp) = handlers.handle(method: "POST", path: "/hooks/voice-to-md/response", body: body)
        XCTAssertEqual(status, 400)
        XCTAssertNotNil(resp["error"])
    }

    func testResponseRouteEmptyBodyReturns400() {
        let handlers = HookHandlers()
        let (status, _) = handlers.handle(method: "POST", path: "/hooks/voice-to-md/response", body: Data())
        XCTAssertEqual(status, 400)
    }

    func testResponseRouteMalformedJSONReturns400() {
        let handlers = HookHandlers()
        let body = "not json".data(using: .utf8)!
        let (status, _) = handlers.handle(method: "POST", path: "/hooks/voice-to-md/response", body: body)
        XCTAssertEqual(status, 400)
    }

    func testResponseRouteDoesNotFireCallbackOnBadBody() {
        let handlers = HookHandlers()
        var called = false
        handlers.onResponse = { _ in called = true }
        _ = handlers.handle(method: "POST", path: "/hooks/voice-to-md/response", body: Data())
        let expectation = expectation(description: "main queue flush")
        DispatchQueue.main.async { expectation.fulfill() }
        waitForExpectations(timeout: 1)
        XCTAssertFalse(called)
    }

    // MARK: - /hooks/voice-to-md/notification

    func testNotificationRouteReturns200() {
        let handlers = HookHandlers()
        let body = try! JSONSerialization.data(withJSONObject: ["event": "test"])
        let (status, resp) = handlers.handle(method: "POST", path: "/hooks/voice-to-md/notification", body: body)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(resp["status"] as? String, "ok")
    }

    func testNotificationRouteDeliversRawBody() {
        let handlers = HookHandlers()
        let payload = try! JSONSerialization.data(withJSONObject: ["event": "after_agent"])

        let expectation = expectation(description: "onNotification called")
        handlers.onNotification = { data in
            XCTAssertEqual(data, payload)
            expectation.fulfill()
        }

        _ = handlers.handle(method: "POST", path: "/hooks/voice-to-md/notification", body: payload)
        waitForExpectations(timeout: 1)
    }

    func testNotificationRouteAcceptsEmptyBody() {
        let handlers = HookHandlers()
        let (status, _) = handlers.handle(method: "POST", path: "/hooks/voice-to-md/notification", body: Data())
        XCTAssertEqual(status, 200)
    }

    // MARK: - No callback set

    func testInitRouteWithNoCallbackDoesNotCrash() {
        let handlers = HookHandlers()
        handlers.onInit = nil
        let (status, _) = handlers.handle(method: "POST", path: "/hooks/voice-to-md/init", body: Data())
        XCTAssertEqual(status, 200)
        let expectation = expectation(description: "main queue flush")
        DispatchQueue.main.async { expectation.fulfill() }
        waitForExpectations(timeout: 1)
    }
}
