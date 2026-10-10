import CoreGraphics
import Foundation

/// Output resolution: the recorded area is scaled to fit inside `box` (never above its native size).
public enum Resolution: String, Codable, CaseIterable, Sendable {
    case p720, p1080, p2160

    public var box: CGSize {
        switch self {
        case .p720: CGSize(width: 1280, height: 720)
        case .p1080: CGSize(width: 1920, height: 1080)
        case .p2160: CGSize(width: 3840, height: 2160)
        }
    }

    public var title: String {
        switch self {
        case .p720: "720p"
        case .p1080: "1080p"
        case .p2160: "4K"
        }
    }
}

public struct SettingsValues: Codable, Equatable, Sendable {
    public var resolution: Resolution = .p1080
    public var systemAudio: Bool = true
    public var microphone: Bool = false
    /// Whether the mouse cursor appears in recordings; shared by the menu, Preferences, and the toolbox toggle.
    public var recordCursor: Bool = true
    public var outputFolder: String = SettingsValues.defaultOutputFolder

    public init() {}

    public static let defaultOutputFolder = (NSHomeDirectory() as NSString).appendingPathComponent("Movies/Recorder")

    // Decodes field by field so a value added in a later version falls back to its default.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = SettingsValues()
        resolution = (try? container.decode(Resolution.self, forKey: .resolution)) ?? fallback.resolution
        systemAudio = (try? container.decode(Bool.self, forKey: .systemAudio)) ?? fallback.systemAudio
        microphone = (try? container.decode(Bool.self, forKey: .microphone)) ?? fallback.microphone
        recordCursor = (try? container.decode(Bool.self, forKey: .recordCursor)) ?? fallback.recordCursor
        outputFolder = (try? container.decode(String.self, forKey: .outputFolder)) ?? fallback.outputFolder
    }
}

/// Persists user settings as JSON in `UserDefaults`; missing keys fall back to defaults.
public final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    private let storageKey: String

    @Published public var values: SettingsValues {
        didSet { persist() }
    }

    public init(defaults: UserDefaults = .standard, storageKey: String = "settingsValues") {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(SettingsValues.self, from: data) {
            values = decoded
        } else {
            values = SettingsValues()
        }
    }

    public var outputFolderURL: URL { URL(fileURLWithPath: values.outputFolder, isDirectory: true) }

    private func persist() {
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
