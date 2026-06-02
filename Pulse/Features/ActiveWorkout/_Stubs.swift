import SwiftUI
struct PreWorkoutView: View { let model: ActiveWorkoutModel; var body: some View { Text("pre") } }
struct ActiveSetView: View { let model: ActiveWorkoutModel; var body: some View { Text("active") } }
struct RestView: View { let model: ActiveWorkoutModel; var body: some View { Text("rest") } }
struct SummaryView: View { let model: ActiveWorkoutModel; var body: some View { Text("summary") } }
struct SwapSheet: View { let model: ActiveWorkoutModel; var body: some View { Text("swap") } }
struct HistorySheet: View { let model: ActiveWorkoutModel; var body: some View { Text("history") } }
struct JumpSheet: View { let model: ActiveWorkoutModel; var body: some View { Text("jump") } }
