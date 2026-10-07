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
        return Bundle.main.url(forResource: name, withExtension: "mp4", subdirectory: "Grades")
    }
}
