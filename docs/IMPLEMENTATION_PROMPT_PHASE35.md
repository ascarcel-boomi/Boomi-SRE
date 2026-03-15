# Boomi SRE App — Phase 35: Auto-Check for Updates on About Page & Fix Download Progress Bar

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Views/Settings/AboutSettingsContent.swift` — About tab in Settings (needs auto-check on appear)
- `BoomiSRE/Sources/ViewModels/UpdateViewModel.swift` — `checkForUpdate()` and `downloadAndApply()` methods
- `BoomiSRE/Sources/Services/UpdateService.swift` — `downloadUpdate()` method (progress bar bug is here)

---

## Bug 1: About Page Doesn't Auto-Check for Updates

**Current behavior:** When the user opens Settings → About (or clicks "Check for Updates..." from the app menu), they see the About page but must manually click the "Check for Updates" button to check.

**Expected behavior:** The About page should automatically check for updates every time it appears.

**Fix:** In `AboutSettingsContent.swift`, add an auto-check in `.onAppear`:

```swift
.onAppear {
    currentMOTD = MOTDLibrary.messageOfTheMoment()
    // Auto-check for updates when the About page is opened
    Task { await updateVM.checkForUpdate() }
}
```

The `checkForUpdate()` method already has a `guard !isChecking` at the top to prevent duplicate checks, so this is safe to call every time the view appears.

---

## Bug 2: Download Progress Bar Stuck at 0%

**Current behavior:** When downloading an update, the progress bar stays at 0% the entire time, then the app quits and relaunches.

**Root cause:** In `UpdateService.downloadUpdate()` (line 73), the download uses `URLSession.shared.download(from: url)` which is a simple one-shot async call. It does NOT provide progress callbacks during the download. The `progressHandler` closure is only called ONCE at the very end with `1.0` (line 80), by which point the download is already complete and the progress bar immediately jumps to 100% before the app quits.

**Fix:** Replace the one-shot `URLSession.shared.download(from:)` with a `URLSessionDownloadTask` that uses a delegate to report progress.

Rewrite `downloadUpdate()` in `UpdateService.swift`:

```swift
func downloadUpdate(dmgURL: String, progressHandler: @escaping @Sendable (Double) -> Void) async throws -> URL {
    guard let url = URL(string: dmgURL) else {
        throw UpdateError.invalidURL
    }
    let localURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("BoomiSRE_update.dmg")

    // Remove any previous download
    try? FileManager.default.removeItem(at: localURL)

    // Use a delegate-based download task for real-time progress
    return try await withCheckedThrowingContinuation { continuation in
        let delegate = DownloadDelegate(
            destination: localURL,
            progressHandler: progressHandler,
            completion: continuation
        )
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        task.resume()
    }
}
```

Create a `DownloadDelegate` class (can be a private class inside UpdateService.swift or a nested type):

```swift
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    let destination: URL
    let progressHandler: @Sendable (Double) -> Void
    let completion: CheckedContinuation<URL, Error>
    private let completed = Mutex(false)  // prevent double-resume

    init(destination: URL, progressHandler: @escaping @Sendable (Double) -> Void,
         completion: CheckedContinuation<URL, Error>) {
        self.destination = destination
        self.progressHandler = progressHandler
        self.completion = completion
    }

    // Called periodically during download with progress
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler(progress)
    }

    // Called when download completes
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            progressHandler(1.0)
            completion.resume(returning: destination)
        } catch {
            completion.resume(throwing: error)
        }
    }

    // Called on error
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            completion.resume(throwing: error)
        }
    }
}
```

**Note on Sendable:** Since `UpdateService` is an `actor`, the delegate and its closures need to be `Sendable`. If the `Mutex` type isn't available, use `NSLock` or `os_unfair_lock` to protect against double-resume of the continuation. Or simpler: use an `UnsafeContinuation` and handle the threading manually.

**Alternative simpler approach** if the delegate pattern is too complex for the actor isolation:

Use `URLSession.shared.bytes(from:)` for streaming progress:

```swift
func downloadUpdate(dmgURL: String, progressHandler: @escaping @Sendable (Double) -> Void) async throws -> URL {
    guard let url = URL(string: dmgURL) else { throw UpdateError.invalidURL }
    let localURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BoomiSRE_update.dmg")
    try? FileManager.default.removeItem(at: localURL)

    let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        throw UpdateError.downloadFailed
    }

    let expectedLength = http.expectedContentLength
    var data = Data()
    data.reserveCapacity(expectedLength > 0 ? Int(expectedLength) : 50_000_000)

    for try await byte in asyncBytes {
        data.append(byte)
        if expectedLength > 0, data.count % 65536 == 0 {  // update progress every 64KB
            let progress = Double(data.count) / Double(expectedLength)
            progressHandler(progress)
        }
    }

    try data.write(to: localURL)
    progressHandler(1.0)
    return localURL
}
```

Use whichever approach compiles cleanly with Swift's actor isolation rules. The key requirement: **the progress handler must be called multiple times during the download, not just once at the end.**

---

## General Guidelines

- Run `swift build` to verify.
- Commit with descriptive message.
