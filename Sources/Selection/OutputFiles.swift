import Foundation

public enum OutputFilesError: Error, Equatable {
    /// The output folder could not be created or written; carries the folder path.
    case folderNotWritable(String)
}

/// Names and places recording files: `Recording yyyy-MM-dd HH.mm.ss.mp4`, never overwriting an existing file.
public enum OutputFiles {
    public static let fileExtension = "mp4"

    /// `Recording yyyy-MM-dd HH.mm.ss` for `date`.
    public static func baseName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Recording \(formatter.string(from: date))"
    }

    /// `folder/baseName.mp4`, or `folder/baseName 2.mp4`, `baseName 3.mp4`, ... when that name is taken.
    public static func uniqueURL(folder: URL, baseName: String, fileManager: FileManager = .default) -> URL {
        var candidate = folder.appendingPathComponent(baseName).appendingPathExtension(fileExtension)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(baseName) \(counter)").appendingPathExtension(fileExtension)
            counter += 1
        }
        return candidate
    }

    /// Creates `folder` when missing and checks that files can be created in it.
    public static func prepareFolder(_ folder: URL, fileManager: FileManager = .default) throws {
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw OutputFilesError.folderNotWritable(folder.path)
        }
        guard fileManager.isWritableFile(atPath: folder.path) else {
            throw OutputFilesError.folderNotWritable(folder.path)
        }
    }

    /// Hidden path prefix inside `folder` for the segments of one recording (see `RecordingEngine`).
    public static func segmentBase(folder: URL, baseName: String) -> URL {
        folder.appendingPathComponent(".\(baseName).segment")
    }
}
