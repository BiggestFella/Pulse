import Foundation

/// Navigation destinations the Library pushes. The destination *screens* are
/// separate features; here we only carry the routing intent (rendered as a
/// stub) so UI tests can assert the right push happened.
enum LibraryRoute: Hashable {
    case exerciseDetail(id: String)
    case programDetail(folderID: String)
    case folderDetail(folderID: UUID, name: String)
    case workoutBuilder
    case routineBuilder
    case folderCreate

    /// Stable marker for the stub destination + UI assertions.
    var marker: String {
        switch self {
        case .exerciseDetail(let id): return "exdetail:\(id)"
        case .programDetail(let id):  return "program:\(id)"
        case .folderDetail(let id, _): return "folder:\(id)"
        case .workoutBuilder:         return "builder:workout"
        case .routineBuilder:         return "builder:routine"
        case .folderCreate:           return "builder:folder"
        }
    }
}
