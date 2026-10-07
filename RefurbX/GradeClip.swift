import Foundation

enum GradeClip {
    static func file(for id: String) -> URL? {
        let name: String
        switch id {
        case "A+": name = "grade-aplus"
        case "A": name = "grade-a"
        case "B": name = "grade-b"
        case "C": name = "grade-c"
        default: return nil
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "mp4") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "mp4", subdirectory: "Grades") {
            return url
        }
        return bundleFile(named: name + ".mp4")
    }

    private static func bundleFile(named wanted: String) -> URL? {
        guard let root = Bundle.main.resourceURL,
              let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let url as URL in enumerator where url.lastPathComponent == wanted {
            return url
        }
        return nil
    }
}
