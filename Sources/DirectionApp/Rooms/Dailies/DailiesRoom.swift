import SwiftUI
import DirectionCore

// Owner: Start agent. Frames 07–09. Replace this stub.

struct DailiesRoom: View {
    @Bindable var model: FilmModel
    var body: some View { Text("Dailies").frame(maxWidth: .infinity, maxHeight: .infinity) }
}

extension FilmModel {
    var dailiesPrimary: PrimaryAction? { PrimaryAction(title: "Assemble from circles", count: String(circledCount), enabled: circledCount > 0) { self.assembleFromCircles() } }
}
