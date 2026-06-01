import Foundation

/// Programs (a named multi-week plan of Workouts). `fetchProgram(id:)` is
/// hydrated — it returns the full nested graph ready to render.
protocol ProgramRepository {
    func fetchPrograms() async throws -> [Program]
    func fetchProgram(id: Program.ID) async throws -> Program?
    func activeProgram() async throws -> Program?
    func saveProgram(_ program: Program) async throws -> Program
    func deleteProgram(id: Program.ID) async throws
}
