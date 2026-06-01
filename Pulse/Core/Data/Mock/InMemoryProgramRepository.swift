import Foundation

@MainActor
struct InMemoryProgramRepository: ProgramRepository {
    let store: MockStore

    func fetchPrograms() async throws -> [Program] {
        try await store.gate(); return store.programs
    }
    func fetchProgram(id: Program.ID) async throws -> Program? {
        try await store.gate(); return store.programs.first { $0.id == id }
    }
    func activeProgram() async throws -> Program? {
        try await store.gate(); return store.programs.first { $0.isActive }
    }
    func saveProgram(_ program: Program) async throws -> Program {
        try await store.gate()
        if let i = store.programs.firstIndex(where: { $0.id == program.id }) {
            store.programs[i] = program
        } else {
            store.programs.append(program)
        }
        return program
    }
    func deleteProgram(id: Program.ID) async throws {
        try await store.gate(); store.programs.removeAll { $0.id == id }
    }
}
