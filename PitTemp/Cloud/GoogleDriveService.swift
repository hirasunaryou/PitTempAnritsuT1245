import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@MainActor
final class GoogleDriveService: ObservableObject {
    enum SignInState { case signedOut, signingIn, signedIn }

    enum DriveError: LocalizedError {
        case parentFolderMissing
        case unauthenticated
        case unsupported
        case presenterUnavailable
        case invalidResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .parentFolderMissing:
                return "Parent folder ID is not configured."
            case .unauthenticated:
                return "Google Drive requires authentication."
            case .unsupported:
                return "Google Drive integration is not available on this platform."
            case .presenterUnavailable:
                return "Unable to determine topmost view controller for sign-in."
            case .invalidResponse:
                return "Google Drive returned an unexpected response."
            case .server(let message):
                return message
            }
        }
    }

    struct DriveCSVFile: Identifiable, Hashable {
        let id: String
        let name: String
        let dayFolder: String
        let createdTime: Date?
        let modifiedTime: Date?
        let size: Int64?
        let webViewLink: URL?
        let properties: [String: String]

        var sessionID: UUID? { properties["sessionID"].flatMap(UUID.init) }
        var driver: String { properties["driver"] ?? "" }
        var track: String { properties["track"] ?? "" }
        var car: String { properties["car"] ?? "" }
        var deviceID: String { properties["deviceID"] ?? "" }
        var deviceName: String { properties["deviceName"] ?? "" }
        var exportedISO: String { properties["exportedAtISO"] ?? "" }
        var sessionStartISO: String { properties["sessionStartedISO"] ?? "" }
    }

    @AppStorage("drive.parentFolderID") var parentFolderID: String = ""
    @AppStorage("drive.manualAccessToken") var manualAccessToken: String = ""

    @Published private(set) var signInState: SignInState = .signedOut
    @Published private(set) var uploadState: UploadUIState = .idle
    @Published private(set) var lastErrorMessage: String? = nil
    @Published private(set) var files: [DriveCSVFile] = []

    private var dayFolderCache: [String: String] = [:]
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let shortISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let driveScope = "https://www.googleapis.com/auth/drive.file"

    func isConfigured() -> Bool {
        !parentFolderID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func setParentFolder(id: String) {
        parentFolderID = id.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setManualAccessToken(_ token: String) {
        manualAccessToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func signOut() {
#if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
#endif
        signInState = .signedOut
    }

    func signIn() async throws {
#if canImport(GoogleSignIn)
#if canImport(UIKit)
        guard let presenter = topViewController() else { throw DriveError.presenterUnavailable }
        signInState = .signingIn
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            if result.user.grantedScopes?.contains(Self.driveScope) != true {
                _ = try await GIDSignIn.sharedInstance.addScopes([Self.driveScope], presenting: presenter)
            }
            signInState = .signedIn
        } catch {
            signInState = .signedOut
            throw error
        }
#else
        throw DriveError.unsupported
#endif
#else
        throw DriveError.unsupported
#endif
    }

    func upload(csvURL: URL, metadata: DriveCSVMetadata) async {
        guard isConfigured() else {
            uploadState = .failed(DriveError.parentFolderMissing.errorDescription ?? "")
            lastErrorMessage = DriveError.parentFolderMissing.errorDescription
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.uploadState = .idle }
            return
        }

        uploadState = .uploading
        do {
            let token = try await accessToken()
            let folderID = try await ensureDayFolder(named: metadata.dayFolderName, parentID: parentFolderID, accessToken: token)
            _ = try await uploadCSVFile(csvURL: csvURL, folderID: folderID, metadata: metadata, accessToken: token)
            uploadState = .done
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.uploadState = .idle }
            await refreshFileList()
        } catch {
            uploadState = .failed(error.localizedDescription)
            lastErrorMessage = error.localizedDescription
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.uploadState = .idle }
        }
    }

    func refreshFileList() async {
        guard isConfigured() else {
            files = []
            return
        }

        do {
            let token = try await accessToken()
            let dayFolders = try await fetchDayFolders(parentID: parentFolderID, accessToken: token)
            var collected: [DriveCSVFile] = []
            for folder in dayFolders {
                let csvs = try await fetchCSVFiles(in: folder, accessToken: token)
                collected.append(contentsOf: csvs)
            }
            files = collected.sorted(by: { lhs, rhs in
                let lhsDate = lhs.modifiedTime ?? lhs.createdTime ?? Date.distantPast
                let rhsDate = rhs.modifiedTime ?? rhs.createdTime ?? Date.distantPast
                return lhsDate > rhsDate
            })
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func download(file: DriveCSVFile) async throws -> URL {
        let token = try await accessToken()
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(file.id)?alt=media")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw DriveError.invalidResponse
        }

        let destinationDir = documentsBase().appendingPathComponent("DriveDownloads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: destinationDir.path) {
            try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        }

        let destination = destinationDir.appendingPathComponent(file.name)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    // MARK: - Helpers

    private func accessToken() async throws -> String {
#if canImport(GoogleSignIn)
        if let user = GIDSignIn.sharedInstance.currentUser {
            return try await withCheckedThrowingContinuation { continuation in
                user.refreshTokensIfNeeded { refreshedUser, error in
                    if let refreshedUser {
                        continuation.resume(returning: refreshedUser.accessToken.tokenString)
                    } else {
                        continuation.resume(throwing: error ?? DriveError.unauthenticated)
                    }
                }
            }
        }
#endif
        if !manualAccessToken.isEmpty {
            return manualAccessToken
        }
        throw DriveError.unauthenticated
    }

    private func ensureDayFolder(named name: String, parentID: String, accessToken: String) async throws -> String {
        if let cached = dayFolderCache[name] { return cached }

        if let existing = try await findFolder(named: name, parentID: parentID, accessToken: accessToken) {
            dayFolderCache[name] = existing
            return existing
        }

        let url = URL(string: "https://www.googleapis.com/drive/v3/files")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder",
            "parents": [parentID]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data = try await performJSONRequest(request)
        let folder = try JSONDecoder().decode(DriveFolderDTO.self, from: data)
        dayFolderCache[name] = folder.id
        return folder.id
    }

    private func findFolder(named name: String, parentID: String, accessToken: String) async throws -> String? {
        let encodedName = name.replacingOccurrences(of: "'", with: "\\'")
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "name = '\(encodedName)' and '\(parentID)' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false"),
            URLQueryItem(name: "fields", value: "files(id,name)"),
            URLQueryItem(name: "pageSize", value: "1")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw DriveError.invalidResponse
        }

        let list = try JSONDecoder().decode(FolderListDTO.self, from: data)
        return list.files.first?.id
    }

    private func uploadCSVFile(csvURL: URL, folderID: String, metadata: DriveCSVMetadata, accessToken: String) async throws -> DriveFileDTO {
        let uploadURL = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let fileData = try Data(contentsOf: csvURL)
        let metadataJSON: [String: Any] = [
            "name": csvURL.lastPathComponent,
            "mimeType": "text/csv",
            "parents": [folderID],
            "properties": [
                "sessionID": metadata.sessionID.uuidString,
                "driver": metadata.driver,
                "track": metadata.track,
                "car": metadata.car,
                "deviceID": metadata.deviceID,
                "deviceName": metadata.deviceName,
                "exportedAtISO": isoFormatter.string(from: metadata.exportedAt),
                "sessionStartedISO": isoFormatter.string(from: metadata.sessionStartedAt)
            ]
        ]

        let metaDataBody = try JSONSerialization.data(withJSONObject: metadataJSON)

        var body = Data()
        let boundaryLine = "--\(boundary)\r\n"
        body.append(Data(boundaryLine.utf8))
        body.append(Data("Content-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
        body.append(metaDataBody)
        body.append(Data("\r\n".utf8))
        body.append(Data(boundaryLine.utf8))
        body.append(Data("Content-Type: text/csv\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        request.httpBody = body

        let data = try await performJSONRequest(request)
        return try JSONDecoder().decode(DriveFileDTO.self, from: data)
    }

    private func fetchDayFolders(parentID: String, accessToken: String) async throws -> [DriveFolderDTO] {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "'\(parentID)' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false"),
            URLQueryItem(name: "fields", value: "files(id,name)"),
            URLQueryItem(name: "pageSize", value: "200"),
            URLQueryItem(name: "orderBy", value: "name desc")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw DriveError.invalidResponse
        }

        let list = try JSONDecoder().decode(FolderListDTO.self, from: data)
        return list.files
    }

    private func fetchCSVFiles(in folder: DriveFolderDTO, accessToken: String) async throws -> [DriveCSVFile] {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "'\(folder.id)' in parents and mimeType = 'text/csv' and trashed = false"),
            URLQueryItem(name: "fields", value: "files(id,name,createdTime,modifiedTime,size,properties,webViewLink)"),
            URLQueryItem(name: "pageSize", value: "200"),
            URLQueryItem(name: "orderBy", value: "modifiedTime desc")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw DriveError.invalidResponse
        }

        let list = try JSONDecoder().decode(FileListDTO.self, from: data)
        return list.files.map { dto in
            DriveCSVFile(
                id: dto.id,
                name: dto.name,
                dayFolder: folder.name,
                createdTime: parseDate(dto.createdTime),
                modifiedTime: parseDate(dto.modifiedTime),
                size: Int64(dto.size ?? "0"),
                webViewLink: dto.webViewLink.flatMap(URL.init(string:)),
                properties: dto.properties ?? [:]
            )
        }
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        if let date = isoFormatter.date(from: string) { return date }
        if let date = shortISOFormatter.date(from: string) { return date }
        return nil
    }

    private func performJSONRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DriveError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            if let message = String(data: data, encoding: .utf8), !message.isEmpty {
                throw DriveError.server(message)
            }
            throw DriveError.invalidResponse
        }
        return data
    }

    private func documentsBase() -> URL {
        if let ubiq = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents") {
            return ubiq
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

#if canImport(UIKit)
    private func topViewController(base: UIViewController? = UIApplication.shared.connectedScenes.compactMap { scene in
        guard let windowScene = scene as? UIWindowScene else { return nil }
        return windowScene.windows.first { $0.isKeyWindow }?.rootViewController
    }.first) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return tab.selectedViewController.flatMap { topViewController(base: $0) }
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
#endif
}

private struct DriveFolderDTO: Decodable {
    let id: String
    let name: String
}

private struct FolderListDTO: Decodable {
    let files: [DriveFolderDTO]
}

private struct DriveFileDTO: Decodable {
    let id: String
    let name: String
    let createdTime: String?
    let modifiedTime: String?
    let size: String?
    let properties: [String: String]?
    let webViewLink: String?
}

private struct FileListDTO: Decodable {
    let files: [DriveFileDTO]
}

