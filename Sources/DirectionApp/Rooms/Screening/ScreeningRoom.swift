import SwiftUI
import DirectionCore

// Owner: Script and Screening agent. Frames 13–16. Replace this stub.

struct ScreeningRoom: View {
    @Bindable var model: FilmModel
    var app: AppModel?
    var body: some View { ZStack(alignment: .top) { Gate.Surface.canvas; Titlebar(model: model, app: app, overPicture: true) }.ignoresSafeArea() }
}
