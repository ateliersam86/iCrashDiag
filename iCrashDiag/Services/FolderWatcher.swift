import Foundation

/// Watches a directory for new .ips files using GCD DispatchSource.
/// Calls the callback on the main actor whenever new files are detected.
final class FolderWatcher: @unchecked Sendable {

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var knownFiles: Set<String> = []
    private var onNewFiles: (@MainActor ([URL]) -> Void)?
    private var watchedURL: URL?

    func start(watching folder: URL, onNewFiles: @escaping @MainActor ([URL]) -> Void) {
        stop()
        watchedURL = folder
        self.onNewFiles = onNewFiles

        // Snapshot existing files so we only report truly new ones
        knownFiles = currentIPSFiles(in: folder)

        let fd = Darwin.open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .utility)
        )

        src.setEventHandler { [weak self] in
            self?.checkForNewFiles()
        }

        src.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                Darwin.close(fd)
                self?.fileDescriptor = -1
            }
        }

        source = src
        src.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        knownFiles = []
        watchedURL = nil
        onNewFiles = nil
    }

    private func checkForNewFiles() {
        guard let folder = watchedURL else { return }
        let current = currentIPSFiles(in: folder)
        let newFileNames = current.subtracting(knownFiles)
        knownFiles = current

        guard !newFileNames.isEmpty else { return }

        let newURLs = newFileNames.map { folder.appendingPathComponent($0) }
        let callback = onNewFiles

        Task { @MainActor in
            callback?(newURLs)
        }
    }

    private func currentIPSFiles(in folder: URL) -> Set<String> {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
        return Set(contents
            .filter { $0.pathExtension.lowercased() == "ips" }
            .map { $0.lastPathComponent }
        )
    }

    deinit {
        stop()
    }
}
