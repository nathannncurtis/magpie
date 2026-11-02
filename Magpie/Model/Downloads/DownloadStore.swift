import Foundation
import Observation
import WebKit

/// One thing to download: the request a page made, and the name its response suggested.
struct DownloadJob: Sendable {
    var request: URLRequest
    var suggestedName: String?
}

/// The files in Documents/Downloads, and the downloads that add to them. The Files app
/// shows the folder, so what is listed here is read from disk, never kept apart from it.
@MainActor
@Observable
final class DownloadStore {

    /// One saved file.
    struct File: Identifiable, Equatable {
        let url: URL
        let size: Int64
        let date: Date
        var id: URL { url }
        var name: String { url.lastPathComponent }
    }

    /// What the toast says.
    enum Toast: Equatable {
        case running(name: String)
        case done(name: String, url: URL)
        case failed(name: String)
    }

    /// Where the toast stays, once a download is done.
    static let toastHold: Duration = .seconds(6)

    static var defaultDirectory: URL {
        URL.documentsDirectory.appending(path: "Downloads", directoryHint: .isDirectory)
    }

    let directory: URL
    /// The saved files, newest first.
    private(set) var files: [File] = []
    /// The progress or result line over the page, while there is one.
    private(set) var toast: Toast?
    /// The file QuickLook shows, when one is up.
    var preview: URL?

    @ObservationIgnored private var toastClear: Task<Void, Never>?
    @ObservationIgnored private var running = 0

    init(directory: URL = DownloadStore.defaultDirectory) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
    }

    /// Reads the folder again: a file the Files app removed is gone from the list too.
    func reload() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles])) ?? []
        files =
            urls.compactMap { url -> File? in
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isDirectory != true else { return nil }
                return File(
                    url: url, size: Int64(values?.fileSize ?? 0),
                    date: values?.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.date > $1.date }
    }

    func delete(_ file: File) {
        try? FileManager.default.removeItem(at: file.url)
        reload()
    }

    /// A file just deleted: set aside in the temporary folder, where the system sweeps it
    /// up in its own time, and put back by an undo.
    struct Trashed: Equatable, Sendable {
        let original: URL
        let held: URL
    }

    /// Takes a file out of the list and off the folder, keeping it for an undo. Nil when
    /// the file could not be moved.
    func trash(_ file: File) -> Trashed? {
        let holder = FileManager.default.temporaryDirectory
            .appending(path: "MagpieDownloadsTrash", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let held = holder.appending(path: file.url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: holder, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: file.url, to: held)
        } catch {
            return nil
        }
        reload()
        return Trashed(original: file.url, held: held)
    }

    /// Brings a trashed file back, under its own name or the next free one.
    func restore(_ trashed: Trashed) {
        guard FileManager.default.fileExists(atPath: trashed.held.path) else { return }
        _ = try? Self.place(trashed.held, named: trashed.original.lastPathComponent, in: directory)
        reload()
    }

    func dismissToast() {
        toastClear?.cancel()
        toast = nil
    }

    /// Opens a file in QuickLook.
    func open(_ url: URL) {
        preview = url
    }

    /// Starts a download. The page's cookies go along, so a file behind a sign-in still
    /// comes; the session is ephemeral, so nothing of the request lingers in the app's own.
    func start(_ job: DownloadJob, cookieStore: WKHTTPCookieStore?) {
        let shownName = DownloadNaming.name(
            suggested: job.suggestedName, url: job.request.url, mimeType: nil)
        running += 1
        show(.running(name: shownName))
        SnapshotLog.event("download start")
        Task {
            var request = job.request
            if let cookieStore, let url = request.url,
                request.value(forHTTPHeaderField: "Cookie") == nil
            {
                let jar = await cookieStore.allCookies()
                let fields = HTTPCookie.requestHeaderFields(
                    with: DownloadNaming.cookies(jar, for: url))
                for (key, value) in fields { request.setValue(value, forHTTPHeaderField: key) }
            }
            do {
                let saved = try await Self.fetch(
                    request, suggestedName: job.suggestedName, into: directory)
                running -= 1
                reload()
                SnapshotLog.event("download done")
                show(.done(name: saved.lastPathComponent, url: saved), hold: true)
            } catch {
                running -= 1
                SnapshotLog.event("download failed \(error.localizedDescription)")
                show(.failed(name: shownName), hold: true)
            }
        }
    }

    private func show(_ toast: Toast, hold: Bool = false) {
        toastClear?.cancel()
        self.toast = toast
        guard hold else { return }
        toastClear = Task {
            try? await Task.sleep(for: Self.toastHold)
            guard !Task.isCancelled, running == 0 else { return }
            self.toast = nil
        }
    }

    /// Fetches the request to a file in `directory`, named from the response.
    nonisolated private static func fetch(
        _ request: URLRequest, suggestedName: String?, into directory: URL
    ) async throws -> URL {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: request) { temporary, response, error in
                // The temporary file is the system's until this closure returns, so the
                // move happens here.
                do {
                    if let error { throw error }
                    guard let temporary, let response else { throw URLError(.badServerResponse) }
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw URLError(.badServerResponse)
                    }
                    let name = DownloadNaming.name(
                        suggested: response.suggestedFilename ?? suggestedName,
                        url: response.url, mimeType: response.mimeType)
                    continuation.resume(returning: try place(temporary, named: name, in: directory))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            task.resume()
        }
    }

    /// Moves a finished file into `directory` under a name nothing there has, trying again
    /// if another download takes the name first.
    nonisolated static func place(_ file: URL, named name: String, in directory: URL) throws -> URL {
        let manager = FileManager.default
        var lastError: Error = CocoaError(.fileWriteUnknown)
        for _ in 0..<5 {
            let existing = Set((try? manager.contentsOfDirectory(atPath: directory.path)) ?? [])
            let target = directory.appending(
                path: DownloadNaming.uniqueName(name, existing: existing), directoryHint: .notDirectory)
            do {
                try manager.moveItem(at: file, to: target)
                return target
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
