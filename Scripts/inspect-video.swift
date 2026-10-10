// Prints the tracks, size, codec, duration, and per-second audio peak of a video, and optionally saves frames.
// Usage: swift Scripts/inspect-video.swift <file> [frameTimeSeconds ...]
// Frames are written next to the file as <file>-<time>.png.
import AVFoundation
import AppKit

func fourCC(_ code: FourCharCode) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
    return String(bytes: bytes, encoding: .ascii) ?? "\(code)"
}

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: inspect-video <file> [times...]"); exit(1) }
let url = URL(fileURLWithPath: args[1])
let asset = AVURLAsset(url: url)
let semaphore = DispatchSemaphore(value: 0)

Task {
    defer { semaphore.signal() }
    do {
        let duration = try await asset.load(.duration)
        print(String(format: "file=%@ duration=%.3f", url.lastPathComponent, duration.seconds))
        for track in try await asset.load(.tracks) {
            let formats = try await track.load(.formatDescriptions)
            let codec = formats.first.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) } ?? "?"
            let range = try await track.load(.timeRange)
            var line = String(format: "track id=%d type=%@ codec=%@ start=%.3f duration=%.3f",
                              track.trackID, track.mediaType.rawValue, codec, range.start.seconds, range.duration.seconds)
            if track.mediaType == .video {
                let size = try await track.load(.naturalSize)
                let fps = try await track.load(.nominalFrameRate)
                line += String(format: " size=%.0fx%.0f fps=%.1f", size.width, size.height, fps)
            }
            if track.mediaType == .audio, let format = formats.first,
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                line += String(format: " rate=%.0f channels=%d", asbd.mSampleRate, asbd.mChannelsPerFrame)
            }
            print(line)
        }

        // Per-second peak of the first audio track (linear 0...1).
        if let audio = try await asset.loadTracks(withMediaType: .audio).first {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: audio, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
            ])
            reader.add(output)
            reader.startReading()
            var peaks: [Int: Float] = [:]
            while let buffer = output.copyNextSampleBuffer() {
                let time = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
                var length = 0
                var pointer: UnsafeMutablePointer<CChar>?
                CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
                guard let pointer else { continue }
                let count = length / MemoryLayout<Float>.size
                pointer.withMemoryRebound(to: Float.self, capacity: count) { samples in
                    var peak: Float = 0
                    for i in 0..<count { peak = max(peak, abs(samples[i])) }
                    peaks[Int(time), default: 0] = max(peaks[Int(time), default: 0], peak)
                }
            }
            print("audioPeakPerSecond=" + peaks.keys.sorted().map { String(format: "%d:%.3f", $0, peaks[$0]!) }.joined(separator: " "))
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for text in args.dropFirst(2) {
            guard let seconds = Double(text) else { continue }
            let (image, actual) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
            let rep = NSBitmapImageRep(cgImage: image)
            let out = url.deletingPathExtension().appendingPathExtension("\(text).png")
            try rep.representation(using: .png, properties: [:])?.write(to: out)
            print(String(format: "frame t=%@ actual=%.3f -> %@ (%dx%d)", text, actual.seconds, out.lastPathComponent, image.width, image.height))
        }
    } catch {
        print("error: \(error)")
    }
}
semaphore.wait()
