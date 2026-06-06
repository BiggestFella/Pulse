import Foundation
import Supabase

/// Programs (named multi-week plans of workouts). Reads hydrate the full graph in
/// one round-trip via nested embeds; `saveProgram` replaces the workout graph.
/// User scoping is enforced by RLS once the dev user is signed in.
struct SupabaseProgramRepository: ProgramRepository {
    let client: SupabaseClient

    /// programs → workouts → workout_exercises → (parent exercise + variations) + set_specs.
    static let graphSelect =
        "*,workouts(*,workout_exercises(*,exercises(*,variations(*)),set_specs(*)))"

    func fetchPrograms() async throws -> [Program] {
        let rows: [ProgramRow] = try await client
            .from("programs").select(Self.graphSelect).order("created_at")
            .execute().value
        return rows.map { $0.toModel() }
    }

    func fetchProgram(id: Program.ID) async throws -> Program? {
        let rows: [ProgramRow] = try await client
            .from("programs").select(Self.graphSelect).eq("id", value: id.uuidString).limit(1)
            .execute().value
        return rows.first?.toModel()
    }

    func activeProgram() async throws -> Program? {
        let rows: [ProgramRow] = try await client
            .from("programs").select(Self.graphSelect).eq("is_active", value: true).limit(1)
            .execute().value
        return rows.first?.toModel()
    }

    func saveProgram(_ program: Program) async throws -> Program {
        let userID = try await client.auth.session.user.id
        // Upsert the program row, then rebuild its workout graph wholesale.
        // Deleting the program's workouts cascades to workout_exercises + set_specs.
        try await client.from("programs").upsert(ProgramWriteRow(
            id: program.id, userId: userID, name: program.name,
            weeks: program.weeks, isActive: program.isActive)).execute()

        try await client.from("workouts")
            .delete().eq("program_id", value: program.id.uuidString).execute()
        try await WorkoutGraphWriter(client: client).insert(program.workouts, programID: program.id)

        return try await fetchProgram(id: program.id) ?? program
    }

    func deleteProgram(id: Program.ID) async throws {
        try await client.from("programs").delete().eq("id", value: id.uuidString).execute()
    }
}
