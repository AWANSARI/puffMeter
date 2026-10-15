import Foundation

/// Google Drive REST v3 client using only `URLSession`. Works with the non-sensitive
/// `drive.file` scope: PuffyMeter only sees files and folders it created or that the user
/// opened with it through the Google Picker. See docs/adr/001-drive-scope.md.
public struct GoogleDriveClient: DriveService {
    public typealias TokenProvider = @Sendable () async throws -> String

    private let token: TokenProvider
    private let session: URLSession
    private let base = URL(string: "https://www.googleapis.com/drive/v3")!
    private let uploadBase = URL(string: "https://www.googleapis.com/upload/drive/v3/files")!
    static let folderMime = "application/vnd.google-apps.folder"

    public init(session: URLSession = .shared, token: @escaping TokenProvider) {
        self.session = session
        self.token = token
    }

    public func listFolders(parentID: String?, query: String?) async throws -> [DriveFolder] {
        var q = "'\(escape(parentID ?? "root"))' in parents and mimeType='\(Self.folderMime)' and trashed=false"
        if let query, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            q += " and name contains '\(escape(query))'"
        }
        return try await listFiles(q: q, orderBy: "name")
    }

    public func createFolder(name: String, parentID: String?) async throws -> DriveFolder {
        var request = try await authorized(URLRequest(url: base.appending(path: "files").appending(queryItems: [
            URLQueryItem(name: "fields", value: "id,name"),
        ])))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["name": name, "mimeType": Self.folderMime]
        if let parentID { body["parents"] = [parentID] }
        body["appProperties"] = [DriveNaming.appPropertyKey: "1", "kind": "folder"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let file: FileResource = try await send(request)
        return DriveFolder(id: file.id, name: file.name ?? name)
    }

    public func folderExists(id: String) async throws -> Bool {
        let request = try await authorized(URLRequest(url: base.appending(path: "files/\(id)").appending(queryItems: [
            URLQueryItem(name: "fields", value: "id,trashed"),
        ])))
        do {
            let file: FileResource = try await send(request)
            return !(file.trashed ?? false)
        } catch DriveError.failure(.folderMissing) {
            return false
        }
    }

    /// Resumable upload: start a session, then PUT the bytes, reporting progress.
    public func upload(data: Data, name: String, mimeType: String, parentID: String,
                       appProperties: [String: String], progress: @Sendable @escaping (Double) -> Void) async throws -> String {
        var start = try await authorized(URLRequest(url: uploadBase.appending(queryItems: [
            URLQueryItem(name: "uploadType", value: "resumable"),
            URLQueryItem(name: "fields", value: "id"),
        ])))
        start.httpMethod = "POST"
        start.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        start.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        start.setValue("\(data.count)", forHTTPHeaderField: "X-Upload-Content-Length")
        start.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": name, "parents": [parentID], "mimeType": mimeType,
            "appProperties": appProperties.merging([DriveNaming.appPropertyKey: "1"]) { a, _ in a },
        ])
        let (_, startResponse) = try await perform(start)
        guard let location = (startResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location"),
              let sessionURL = URL(string: location) else {
            throw DriveError.invalidResponse
        }

        var put = URLRequest(url: sessionURL)
        put.httpMethod = "PUT"
        put.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        let delegate = UploadProgressDelegate(onProgress: progress)
        let (body, response): (Data, URLResponse)
        do {
            (body, response) = try await session.upload(for: put, from: data, delegate: delegate)
        } catch {
            throw DriveError.failure(.network)
        }
        try Self.validate(response: response, body: body)
        progress(1)
        let file = try JSONDecoder().decode(FileResource.self, from: body)
        return file.id
    }

    public func fileCount(folderID: String) async throws -> Int {
        try await listFiles(q: "'\(escape(folderID))' in parents and trashed=false", orderBy: nil).count
    }

    public func listScoreFiles(folderID: String) async throws -> [DriveFolder] {
        let q = "'\(escape(folderID))' in parents and trashed=false and mimeType='application/json' and " +
            "appProperties has { key='\(DriveNaming.appPropertyKey)' and value='1' }"
        return try await listFiles(q: q, orderBy: "name")
    }

    public func download(fileID: String) async throws -> Data {
        let request = try await authorized(URLRequest(url: base.appending(path: "files/\(fileID)").appending(queryItems: [
            URLQueryItem(name: "alt", value: "media"),
        ])))
        let (data, response) = try await perform(request)
        try Self.validate(response: response, body: data)
        return data
    }

    // MARK: Helpers

    private struct FileResource: Decodable {
        var id: String
        var name: String?
        var trashed: Bool?
    }

    private struct FileList: Decodable {
        var files: [FileResource]
        var nextPageToken: String?
    }

    private func listFiles(q: String, orderBy: String?) async throws -> [DriveFolder] {
        var results: [DriveFolder] = []
        var pageToken: String?
        repeat {
            var items = [URLQueryItem(name: "q", value: q),
                         URLQueryItem(name: "fields", value: "nextPageToken,files(id,name)"),
                         URLQueryItem(name: "pageSize", value: "200"),
                         URLQueryItem(name: "spaces", value: "drive")]
            if let orderBy { items.append(URLQueryItem(name: "orderBy", value: orderBy)) }
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let request = try await authorized(URLRequest(url: base.appending(path: "files").appending(queryItems: items)))
            let page: FileList = try await send(request)
            results += page.files.map { DriveFolder(id: $0.id, name: $0.name ?? "Untitled") }
            pageToken = page.nextPageToken
        } while pageToken != nil
        return results
    }

    private func authorized(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        let accessToken: String
        do {
            accessToken = try await token()
        } catch {
            throw DriveError.failure(.authExpired)
        }
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            try Self.validate(response: response, body: data)
            return (data, response)
        } catch let error as DriveError {
            throw error
        } catch {
            throw DriveError.failure(.network)
        }
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, _) = try await perform(request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw DriveError.invalidResponse
        }
    }

    /// Maps HTTP failures to the user-facing categories the upload queue understands.
    static func validate(response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw DriveError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw DriveError.failure(.authExpired)
        case 403:
            let text = String(data: body, encoding: .utf8) ?? ""
            if text.contains("storageQuotaExceeded") { throw DriveError.failure(.quotaExceeded) }
            if text.contains("rateLimitExceeded") || text.contains("userRateLimitExceeded") {
                throw DriveError.failure(.server)
            }
            throw DriveError.failure(.authExpired)
        case 404:
            throw DriveError.failure(.folderMissing)
        case 429, 500..<600:
            throw DriveError.failure(.server)
        default:
            throw DriveError.failure(.unknown)
        }
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let onProgress: @Sendable (Double) -> Void

    init(onProgress: @Sendable @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(min(0.99, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
    }
}
