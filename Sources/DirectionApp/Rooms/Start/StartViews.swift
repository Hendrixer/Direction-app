import SwiftUI
import DirectionCore

// Owner: Start agent. Frames 01–06. Replace these stubs.

struct FilmsView: View {
    @Bindable var app: AppModel
    var body: some View { Text("Films").frame(maxWidth: .infinity, maxHeight: .infinity).background(Gate.Surface.ground) }
}

struct OnboardingStepper: View {
    var step: OnboardingStep
    var body: some View { Text("Brief · Footage · First look").font(Gate.Font.small) }
}

struct OnboardingView: View {
    @Bindable var model: FilmModel
    var step: OnboardingStep
    var body: some View { Text("Onboarding").frame(maxWidth: .infinity, maxHeight: .infinity) }
}

struct BriefSheet: View {
    @Bindable var model: FilmModel
    var body: some View { AttachedSheet(onDismiss: { model.sheet = nil }) { SheetHeader(title: "The brief") } }
}

extension FilmModel {
    func onboardingPrimary(_ step: OnboardingStep) -> PrimaryAction? { nil }
}
