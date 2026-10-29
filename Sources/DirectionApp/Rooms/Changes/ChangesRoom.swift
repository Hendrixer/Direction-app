import SwiftUI
import DirectionCore

// Owner: Changes and Finish agent. Frames 29–33. Replace this stub.

struct ChangesRoom: View {
    @Bindable var model: FilmModel
    var body: some View { Text("Changes").frame(maxWidth: .infinity, maxHeight: .infinity) }
}

extension FilmModel {
    var changesPrimary: PrimaryAction? { PrimaryAction(title: "Play changes", icon: "play.fill", count: Timecode.duration(changesDuration(in: watchedCut))) { self.playChanges() } }
}
