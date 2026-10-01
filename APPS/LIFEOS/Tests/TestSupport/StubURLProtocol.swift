import Foundation

/// Intercepta las peticiones para poder comprobar qué manda el cliente y
/// devolver respuestas escritas a mano, sin servidor.
public final class StubURLProtocol: URLProtocol {
    public struct Stub {
        public var status: Int
        public var headers: [String: String]
        public var body: Data

        public init(
            status: Int = 200,
            headers: [String: String] = ["Content-Type": "application/json"],
            body: Data = Data()
        ) {
            self.status = status
            self.headers = headers
            self.body = body
        }
    }

    /// Recibe la petición y devuelve la respuesta que toca.
    public static var handler: ((URLRequest) throws -> Stub)?
    /// Última petición vista, para comprobarla desde el test.
    public static var lastRequest: URLRequest?
    public static var requests: [URLRequest] = []

    public static func reset() {
        handler = nil
        lastRequest = nil
        requests = []
    }

    /// Sesión aislada: sin caché, con su propio almacén de cookies.
    public static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpCookieStorage = HTTPCookieStorage()
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        return URLSession(configuration: configuration)
    }

    public static func json(_ object: [String: Any], status: Int = 200) -> Stub {
        let body = try? JSONSerialization.data(withJSONObject: object)
        return Stub(status: status, body: body ?? Data())
    }

    public static func jsonArray(_ array: [[String: Any]], status: Int = 200) -> Stub {
        let body = try? JSONSerialization.data(withJSONObject: array)
        return Stub(status: status, body: body ?? Data())
    }

    public static func text(_ string: String, status: Int) -> Stub {
        Stub(status: status, body: Data(string.utf8))
    }

    /// Cuerpo de la petición: `URLProtocol` lo entrega como `httpBodyStream`,
    /// así que hay que leerlo del stream.
    public static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    public static func bodyJSON(of request: URLRequest) -> [String: Any]? {
        guard let data = body(of: request) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - URLProtocol

    public override class func canInit(with request: URLRequest) -> Bool { true }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    public override func startLoading() {
        StubURLProtocol.lastRequest = request
        StubURLProtocol.requests.append(request)

        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let stub = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: stub.status,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !stub.body.isEmpty {
                client?.urlProtocol(self, didLoad: stub.body)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    public override func stopLoading() {}
}
