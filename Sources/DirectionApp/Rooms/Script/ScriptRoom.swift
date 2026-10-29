import SwiftUI
import DirectionCore

// Owner: Script and Screening agent. Frames 10–12. Replace this stub.

struct ScriptRoom: View {
    @Bindable var model: FilmModel
    var body: some View { Text("Script").frame(maxWidth: .infinity, maxHeight: .infinity) }
}

extension FilmModel {
    var scriptPrimary: PrimaryAction? { notesPrimary }
}
