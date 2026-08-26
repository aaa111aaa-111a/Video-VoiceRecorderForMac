import Foundation

/// Turns a template plus a capture source into a file name that is safe on APFS
/// and readable in Finder. Pure functions only, so it is fully unit tested.
public enum OutputFileNaming {
    public static let defaultTemplate = "{app}_{date}_{time}"

    public static let availableTokens: [(token: String, description: String)] = [
        ("{app}", "録画対象のアプリ / 画面名"),
        ("{date}", "日付（2026-08-26）"),
        ("{time}", "時刻（14-03-52）"),
        ("{datetime}", "日付と時刻"),
        ("{weekday}", "曜日（Wed）")
    ]

    /// Characters that break Finder, the shell, or both.
    private static let illegalCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|\r\n\t")

    public static func sanitize(_ raw: String, maximumLength: Int = 80) -> String {
        let replaced = String(raw.unicodeScalars.map { illegalCharacters.contains($0) ? "-" : Character($0) })
        let collapsed = replaced
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        var trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        if trimmed.count > maximumLength {
            trimmed = String(trimmed.prefix(maximumLength)).trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        }
        return trimmed.isEmpty ? "Recording" : trimmed
    }

    public static func fileName(
        template: String = defaultTemplate,
        sourceLabel: String?,
        date: Date,
        timeZone: TimeZone = .current,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> String {
        func formatted(_ format: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            return formatter.string(from: date)
        }

        // An empty label is as good as no label: fall back rather than emit "Recording".
        let label = (sourceLabel?.isEmpty == false) ? sourceLabel! : AppInfo.name
        let dateString = formatted("yyyy-MM-dd")
        let timeString = formatted("HH-mm-ss")
        let replacements: [String: String] = [
            "{app}": sanitize(label, maximumLength: 40),
            "{date}": dateString,
            "{time}": timeString,
            "{datetime}": "\(dateString)_\(timeString)",
            "{weekday}": formatted("EEE")
        ]

        var result = template.isEmpty ? defaultTemplate : template
        for (token, value) in replacements {
            result = result.replacingOccurrences(of: token, with: value)
        }
        return sanitize(result)
    }

    /// Appends ` 2`, ` 3`… until the name is free, the way Finder does.
    public static func uniqueURL(
        directory: URL,
        fileName: String,
        fileExtension: String,
        exists: (URL) -> Bool
    ) -> URL {
        let base = sanitize(fileName)
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(fileExtension)
        var suffix = 2
        while exists(candidate) {
            candidate = directory
                .appendingPathComponent("\(base) \(suffix)")
                .appendingPathExtension(fileExtension)
            suffix += 1
            if suffix > 9999 { break }
        }
        return candidate
    }

    /// Sidecar stems live next to the video: `Zoom_2026-08-26_14-03-52.microphone.m4a`.
    public static func sidecarURL(for videoURL: URL, source: AudioSource, fileExtension: String = "m4a") -> URL {
        let base = videoURL.deletingPathExtension().lastPathComponent
        return videoURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(base).\(source.rawValue)")
            .appendingPathExtension(fileExtension)
    }

    /// `~/Movies/OptiRecord`, created on demand by the recording layer.
    public static var defaultDirectory: URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        return movies.appendingPathComponent(AppInfo.name)
    }
}
