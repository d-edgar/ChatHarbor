import Foundation

@main
struct GettingStartedRegression {
    static func main() {
        let domain = "ChatHarbor.TourTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        precondition(GettingStartedStep.restore(from: defaults) == .overview)
        for step in GettingStartedStep.allCases {
            defaults.set(step.rawValue, forKey: GettingStartedStep.storageKey)
            precondition(GettingStartedStep.restore(from: defaults) == step)
            if step != .overview { precondition(step.previous.next == step) }
            if step != .data { precondition(step.next.previous == step) }
        }
        defaults.set("old-invalid-step", forKey: GettingStartedStep.storageKey)
        precondition(GettingStartedStep.restore(from: defaults) == .overview)
        precondition(GettingStartedStep.overview.previous == .overview)
        precondition(GettingStartedStep.data.next == .data)
        precondition(!GettingStartedStep.connect.canContinue(modelAvailable: false, hasUserMessage: true))
        precondition(GettingStartedStep.connect.canContinue(modelAvailable: true, hasUserMessage: false))
        precondition(!GettingStartedStep.chat.canContinue(modelAvailable: true, hasUserMessage: false))
        precondition(GettingStartedStep.chat.canContinue(modelAvailable: false, hasUserMessage: true))
        for step in [GettingStartedStep.overview, .ships, .harbors, .data] {
            precondition(step.canContinue(modelAvailable: false, hasUserMessage: false))
        }
        print("PASS: tour resume, invalid-state fallback, Back/Continue bounds, model readiness and first-message gates")
    }
}
