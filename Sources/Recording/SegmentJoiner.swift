import AVFoundation
import Foundation

public enum SegmentJoinerError: Error, Equatable {
    case noSegments
    case exportUnavailable
}

/// Joins recorded segments back to back into one MP4 (design D11).
public enum SegmentJoiner {
    /// Presets tried in order: passthrough avoids re-encoding; the fallback re-encodes when passthrough cannot write MP4.
    static let presets = [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]

    /// Writes `segments` to `destination`. A single segment is moved; several are exported as one composition.
    /// The segment files are deleted only after success.
    public static func join(_ segments: [URL], to destination: URL) async throws {
        guard !segments.isEmpty else { throw SegmentJoinerError.noSegments }
        if segments.count == 1 {
            try FileManager.default.moveItem(at: segments[0], to: destination)
            return
        }
        let composition = try await composition(segments)
        var lastError: Error = SegmentJoinerError.exportUnavailable
        for preset in presets {
            guard let session = AVAssetExportSession(asset: composition, presetName: preset),
                  session.supportedFileTypes.contains(.mp4)
            else { continue }
            do {
                try await session.export(to: destination, as: .mp4)
                segments.forEach { try? FileManager.default.removeItem(at: $0) }
                return
            } catch {
                lastError = error
                try? FileManager.default.removeItem(at: destination)
            }
        }
        throw lastError
    }

    /// Appends each segment at the running end of the composition, using the video track's time range so audio and
    /// video of every segment start together.
    public static func composition(_ segments: [URL]) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        var audioTrack: AVMutableCompositionTrack?
        var cursor = CMTime.zero
        for url in segments {
            let asset = AVURLAsset(url: url)
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else { continue }
            let range = try await sourceVideo.load(.timeRange)
            try videoTrack?.insertTimeRange(range, of: sourceVideo, at: cursor)
            if videoTrack?.preferredTransform == .identity {
                videoTrack?.preferredTransform = try await sourceVideo.load(.preferredTransform)
            }
            if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                if audioTrack == nil {
                    audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                }
                let audioRange = try await sourceAudio.load(.timeRange).intersection(range)
                if audioRange.duration > .zero {
                    try audioTrack?.insertTimeRange(audioRange, of: sourceAudio, at: cursor + (audioRange.start - range.start))
                }
            }
            cursor = cursor + range.duration
        }
        return composition
    }
}
