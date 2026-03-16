import Foundation
import SwiftData

// MARK: - Brainstorm Session
//
// A structured multi-model brainstorm supporting multiple methods:
// Osborn, Six Thinking Hats, Reverse Brainstorm, Round Robin, or Custom.
// Models take on assigned roles and collaborate through sequential rounds
// with user checkpoints between phases.

@Model
final class BrainstormSession {
    var id: UUID = UUID()
    var title: String = "New Brainstorm"
    var topic: String = ""
    var problemStatement: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// Which brainstorming method this session uses
    var methodRaw: String = "osborn"

    /// Current phase
    var phaseRaw: String = "setup"

    /// Current round within the ideation phase
    var currentRound: Int = 0

    /// Max rounds for ideation before auto-advancing to evaluation
    var maxRounds: Int = 3

    /// Serialized participant data (role + model assignments)
    var participantsData: Data?

    @Relationship(deleteRule: .cascade, inverse: \BrainstormEntry.session)
    var entries: [BrainstormEntry] = []

    /// Whether the session has been completed / archived
    var isComplete: Bool = false

    init(
        title: String = "New Brainstorm",
        topic: String = "",
        method: BrainstormMethod = .osborn,
        maxRounds: Int = 3
    ) {
        self.id = UUID()
        self.title = title
        self.topic = topic
        self.problemStatement = ""
        self.createdAt = Date()
        self.updatedAt = Date()
        self.methodRaw = method.rawValue
        self.phaseRaw = BrainstormPhase.setup.rawValue
        self.currentRound = 0
        self.maxRounds = maxRounds
        self.entries = []
        self.isComplete = false
    }

    // MARK: - Computed Properties

    var method: BrainstormMethod {
        get { BrainstormMethod(rawValue: methodRaw) ?? .osborn }
        set { methodRaw = newValue.rawValue }
    }

    var phase: BrainstormPhase {
        get { BrainstormPhase(rawValue: phaseRaw) ?? .setup }
        set { phaseRaw = newValue.rawValue }
    }

    var participants: [BrainstormParticipant] {
        get {
            guard let data = participantsData else { return [] }
            return (try? JSONDecoder().decode([BrainstormParticipant].self, from: data)) ?? []
        }
        set {
            participantsData = try? JSONEncoder().encode(newValue)
        }
    }

    var sortedEntries: [BrainstormEntry] {
        entries.sorted { $0.createdAt < $1.createdAt }
    }

    /// Entries for a specific phase and round
    func entries(for phase: BrainstormPhase, round: Int? = nil) -> [BrainstormEntry] {
        sortedEntries.filter { entry in
            entry.phase == phase && (round == nil || entry.round == round)
        }
    }

    /// All ideas extracted across all entries
    var allIdeas: [String] {
        sortedEntries.compactMap { $0.ideas }.flatMap { $0 }
    }

    /// Auto-generate title from the topic
    var autoTitle: String {
        let trimmed = topic.prefix(50)
        return trimmed.count < topic.count ? "\(trimmed)…" : String(trimmed)
    }
}

// MARK: - Brainstorm Entry
//
// A single contribution from a model (or the user) within a brainstorm round.

@Model
final class BrainstormEntry {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    /// Which phase this entry belongs to
    var phaseRaw: String = "ideation"

    /// Which round (within ideation/evaluation)
    var round: Int = 0

    /// The role that produced this entry
    var roleRaw: String = "wildCard"

    /// Which model generated this (qualified ID like "anthropic:claude-opus-4")
    var qualifiedModelId: String?

    /// The full response content
    var content: String = ""

    /// Whether this entry is still streaming
    var isStreaming: Bool = false

    /// Discrete ideas extracted from this entry (for tracking through phases)
    var ideasData: Data?

    /// If this is a user interjection
    var isUserInput: Bool = false

    /// Token metrics
    var tokenCount: Int?
    var inputTokenCount: Int?
    var durationMs: Double?
    var error: String?

    var session: BrainstormSession?

    init(
        phase: BrainstormPhase,
        round: Int,
        role: BrainstormRole,
        qualifiedModelId: String? = nil,
        content: String = "",
        isStreaming: Bool = false,
        isUserInput: Bool = false
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.phaseRaw = phase.rawValue
        self.round = round
        self.roleRaw = role.rawValue
        self.qualifiedModelId = qualifiedModelId
        self.content = content
        self.isStreaming = isStreaming
        self.isUserInput = isUserInput
    }

    var phase: BrainstormPhase {
        get { BrainstormPhase(rawValue: phaseRaw) ?? .ideation }
        set { phaseRaw = newValue.rawValue }
    }

    var role: BrainstormRole {
        get { BrainstormRole(rawValue: roleRaw) ?? .wildCard }
        set { roleRaw = newValue.rawValue }
    }

    var ideas: [String]? {
        get {
            guard let data = ideasData else { return nil }
            return try? JSONDecoder().decode([String].self, from: data)
        }
        set {
            ideasData = try? JSONEncoder().encode(newValue)
        }
    }
}

// MARK: - Brainstorm Method
//
// Different brainstorming frameworks. Each method defines its own
// set of roles, phase flow, and system prompts.

enum BrainstormMethod: String, Codable, CaseIterable, Identifiable {
    /// Classic Osborn: divergent ideation → convergent evaluation → synthesis
    case osborn

    /// de Bono's Six Thinking Hats: parallel thinking from 6 perspectives
    case sixHats

    /// Reverse Brainstorm: "How could we make this worse?" then invert
    case reverse

    /// Structured Round Robin: equal turns, build on previous ideas
    case roundRobin

    /// Fully customizable: you define the roles, prompts, and flow
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .osborn: return "Osborn Method"
        case .sixHats: return "Six Thinking Hats"
        case .reverse: return "Reverse Brainstorm"
        case .roundRobin: return "Round Robin"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .osborn: return "lightbulb.max"
        case .sixHats: return "person.3"
        case .reverse: return "arrow.uturn.backward"
        case .roundRobin: return "arrow.triangle.2.circlepath"
        case .custom: return "slider.horizontal.3"
        }
    }

    var description: String {
        switch self {
        case .osborn:
            return "Classic brainstorming: generate ideas freely (no criticism), then evaluate and refine. Best for open-ended problem solving."
        case .sixHats:
            return "Each model wears a different \"thinking hat\" — facts, emotions, caution, optimism, creativity, process. Best for well-rounded analysis."
        case .reverse:
            return "Ask \"How could we make this problem worse?\" then invert the answers into solutions. Best for breaking through mental blocks."
        case .roundRobin:
            return "Each model takes equal turns building on the previous idea. Structured and democratic. Best for inclusive idea development."
        case .custom:
            return "Define your own roles, system prompts, and phase flow. Full control over the brainstorm process."
        }
    }

    /// The default roles for this method
    var defaultRoles: [BrainstormRole] {
        switch self {
        case .osborn:
            return [.facilitator, .wildCard, .pragmatist, .devilsAdvocate, .scribe]
        case .sixHats:
            return [.facilitator, .whitHat, .redHat, .blackHat, .yellowHat, .greenHat]
        case .reverse:
            return [.facilitator, .saboteur, .inverter, .scribe]
        case .roundRobin:
            return [.facilitator, .contributor, .contributor, .scribe]
        case .custom:
            return BrainstormRole.allCases
        }
    }

    /// Which roles are required (can't be disabled)
    var requiredRoles: [BrainstormRole] {
        switch self {
        case .osborn: return [.facilitator]
        case .sixHats: return [.facilitator]
        case .reverse: return [.facilitator, .saboteur, .inverter]
        case .roundRobin: return [.facilitator]
        case .custom: return []
        }
    }

    /// Phases used by this method
    var phases: [BrainstormPhase] {
        switch self {
        case .osborn:
            return [.framing, .ideation, .evaluation, .synthesis]
        case .sixHats:
            return [.framing, .ideation, .synthesis]
        case .reverse:
            return [.framing, .ideation, .evaluation, .synthesis]
        case .roundRobin:
            return [.framing, .ideation, .synthesis]
        case .custom:
            return [.framing, .ideation, .evaluation, .synthesis]
        }
    }
}

// MARK: - Brainstorm Phase

enum BrainstormPhase: String, Codable, CaseIterable {
    /// Configuration: pick topic, assign roles, select models
    case setup

    /// Facilitator reframes the problem; user approves
    case framing

    /// Divergent thinking: all models generate ideas freely, no criticism
    case ideation

    /// Convergent thinking: critique, combine, refine the best ideas
    case evaluation

    /// Facilitator + scribe produce actionable output
    case synthesis

    /// Session complete
    case complete

    var displayName: String {
        switch self {
        case .setup: return "Setup"
        case .framing: return "Problem Framing"
        case .ideation: return "Idea Generation"
        case .evaluation: return "Evaluation"
        case .synthesis: return "Synthesis"
        case .complete: return "Complete"
        }
    }

    /// Short label for badge pills (fits in tight spaces)
    var badgeName: String {
        switch self {
        case .setup: return "Setup"
        case .framing: return "Frame"
        case .ideation: return "Ideate"
        case .evaluation: return "Eval"
        case .synthesis: return "Synth"
        case .complete: return "Done"
        }
    }

    var icon: String {
        switch self {
        case .setup: return "gearshape"
        case .framing: return "scope"
        case .ideation: return "lightbulb.max"
        case .evaluation: return "checkmark.seal"
        case .synthesis: return "doc.text"
        case .complete: return "flag.checkered"
        }
    }

    var description: String {
        switch self {
        case .setup:
            return "Configure your brainstorm session"
        case .framing:
            return "The facilitator reframes your topic into a clear problem statement"
        case .ideation:
            return "Models generate ideas freely — no criticism, quantity over quality"
        case .evaluation:
            return "Models critique, combine, and refine the strongest ideas"
        case .synthesis:
            return "Final summary with actionable next steps"
        case .complete:
            return "Brainstorm complete"
        }
    }
}

// MARK: - Brainstorm Roles

enum BrainstormRole: String, Codable, CaseIterable, Identifiable {
    // MARK: Osborn roles
    /// Runs the session, reframes the problem, synthesizes themes
    case facilitator
    /// Lateral thinker — big ideas, unconventional angles
    case wildCard
    /// Grounds ideas in feasibility, cost, and timeline
    case pragmatist
    /// Finds flaws, stress-tests ideas (active in evaluation phase)
    case devilsAdvocate
    /// Captures decisions, produces clean output (active in synthesis)
    case scribe

    // MARK: Six Thinking Hats roles
    /// White Hat: facts, data, information
    case whitHat
    /// Red Hat: emotions, intuition, gut feeling
    case redHat
    /// Black Hat: caution, risks, critical judgment
    case blackHat
    /// Yellow Hat: optimism, benefits, value
    case yellowHat
    /// Green Hat: creativity, alternatives, new ideas
    case greenHat

    // MARK: Reverse Brainstorm roles
    /// Saboteur: intentionally makes the problem worse
    case saboteur
    /// Inverter: flips saboteur ideas into real solutions
    case inverter

    // MARK: Round Robin roles
    /// General contributor in a round-robin session
    case contributor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .facilitator: return "Facilitator"
        case .wildCard: return "Wild Card"
        case .pragmatist: return "Pragmatist"
        case .devilsAdvocate: return "Devil's Advocate"
        case .scribe: return "Scribe"
        case .whitHat: return "White Hat"
        case .redHat: return "Red Hat"
        case .blackHat: return "Black Hat"
        case .yellowHat: return "Yellow Hat"
        case .greenHat: return "Green Hat"
        case .saboteur: return "Saboteur"
        case .inverter: return "Inverter"
        case .contributor: return "Contributor"
        }
    }

    var icon: String {
        switch self {
        case .facilitator: return "person.crop.circle.badge.checkmark"
        case .wildCard: return "sparkles"
        case .pragmatist: return "hammer"
        case .devilsAdvocate: return "exclamationmark.triangle"
        case .scribe: return "pencil.and.outline"
        case .whitHat: return "doc.text.magnifyingglass"
        case .redHat: return "heart.fill"
        case .blackHat: return "shield.lefthalf.filled"
        case .yellowHat: return "sun.max"
        case .greenHat: return "leaf"
        case .saboteur: return "flame"
        case .inverter: return "arrow.uturn.up"
        case .contributor: return "person.fill"
        }
    }

    var shortDescription: String {
        switch self {
        case .facilitator: return "Runs the session, frames the problem, synthesizes themes"
        case .wildCard: return "Big ideas, lateral thinking, unconventional angles"
        case .pragmatist: return "Feasibility, cost, timeline, real-world constraints"
        case .devilsAdvocate: return "Finds flaws, asks \"what if this fails?\""
        case .scribe: return "Captures decisions, produces clean summary"
        case .whitHat: return "Facts, data, and objective information only"
        case .redHat: return "Emotions, intuition, and gut reactions"
        case .blackHat: return "Risks, dangers, and critical judgment"
        case .yellowHat: return "Benefits, optimism, and best-case scenarios"
        case .greenHat: return "Creative alternatives and new possibilities"
        case .saboteur: return "Intentionally makes the problem worse"
        case .inverter: return "Flips bad ideas into genuine solutions"
        case .contributor: return "Equal-turn idea generation and building"
        }
    }

    var color: String {
        switch self {
        case .facilitator: return "blue"
        case .wildCard: return "purple"
        case .pragmatist: return "green"
        case .devilsAdvocate: return "orange"
        case .scribe: return "teal"
        case .whitHat: return "gray"
        case .redHat: return "red"
        case .blackHat: return "black"
        case .yellowHat: return "yellow"
        case .greenHat: return "green"
        case .saboteur: return "red"
        case .inverter: return "blue"
        case .contributor: return "indigo"
        }
    }

    /// Which phases this role is active in (Osborn default — methods can override)
    var activePhases: [BrainstormPhase] {
        switch self {
        case .facilitator: return [.framing, .ideation, .evaluation, .synthesis]
        case .wildCard: return [.ideation, .evaluation]
        case .pragmatist: return [.ideation, .evaluation]
        case .devilsAdvocate: return [.evaluation]
        case .scribe: return [.synthesis]
        case .whitHat, .redHat, .blackHat, .yellowHat, .greenHat:
            return [.ideation]
        case .saboteur: return [.ideation]
        case .inverter: return [.evaluation]
        case .contributor: return [.ideation]
        }
    }

    /// System prompt for the ideation phase
    var ideationPrompt: String {
        switch self {
        case .facilitator:
            return "You are the Facilitator of this brainstorm session. Your job is to keep the discussion productive and on-track. After other participants share ideas, identify emerging themes, suggest combinations, and propose new angles to explore. Do NOT criticize or evaluate ideas — this is the divergent thinking phase. Be encouraging. Build on what others have said. Ask \"what if?\" and \"how might we?\" questions."
        case .wildCard:
            return "You are the Wild Card in this brainstorm. Your job is to think big, weird, and lateral. Generate bold, unconventional ideas. Make unexpected connections. Challenge obvious approaches. Don't worry about feasibility — that's someone else's job. Aim for quantity and creativity. List your ideas clearly, numbered. Build on previous ideas but push them further than anyone expects."
        case .pragmatist:
            return "You are the Pragmatist in this brainstorm. Your job is to generate ideas grounded in reality. Think about feasibility, timelines, budgets, existing resources, and practical implementation. You can build on others' wild ideas by asking \"how could we actually do a version of this?\" Do NOT shoot down ideas — instead, find the kernel of practicality in each one. List your ideas clearly, numbered."
        case .devilsAdvocate:
            return "You are observing the ideation phase. Take notes on ideas being generated, but do not contribute yet. Your turn comes during the evaluation phase."
        case .scribe:
            return "You are observing the ideation phase. Track all ideas being generated and which participant proposed them. Your turn comes during the synthesis phase."
        // Six Thinking Hats
        case .whitHat:
            return "You are the White Hat thinker. Focus ONLY on facts, data, and objective information. What do we know? What data is available? What information is missing? No opinions, no feelings — just the facts. Be thorough and precise."
        case .redHat:
            return "You are the Red Hat thinker. Share your gut feelings, emotions, and intuitions about this topic. What excites you? What worries you? What feels right or wrong? No need to justify — just express honest reactions and hunches."
        case .blackHat:
            return "You are the Black Hat thinker. Identify risks, dangers, and weaknesses. What could go wrong? Why might this fail? What are the downsides? Be cautious and critical but constructive — you're protecting the group from bad decisions."
        case .yellowHat:
            return "You are the Yellow Hat thinker. Focus on benefits, value, and optimism. What's the best-case scenario? What advantages does this offer? Why could this work brilliantly? Be genuinely positive and constructive."
        case .greenHat:
            return "You are the Green Hat thinker. Generate creative alternatives and new possibilities. Think laterally. What if we approached this completely differently? Propose novel ideas, modifications, and unexpected combinations. Quantity over quality."
        // Reverse Brainstorm
        case .saboteur:
            return "You are the Saboteur. Your job is to brainstorm ways to make this problem WORSE. How could we guarantee failure? What would make this situation as bad as possible? Be creative and thorough in your destruction. List your sabotage ideas clearly, numbered."
        case .inverter:
            return "You are the Inverter. Review the Saboteur's ideas for making things worse, and FLIP each one into a genuine, constructive solution. For each sabotage idea, ask: \"What's the opposite of this?\" and \"How do we prevent this?\" Turn every negative into a positive actionable idea."
        // Round Robin
        case .contributor:
            return "You are a Contributor in this round-robin brainstorm. Review what others have said before you, then add 2-3 new ideas that build on or extend the conversation. You may also refine or combine previous ideas. Be constructive and collaborative. Number your ideas."
        }
    }

    /// System prompt for the evaluation phase
    var evaluationPrompt: String {
        switch self {
        case .facilitator:
            return "You are the Facilitator. The brainstorm is now in the evaluation phase. Review all the ideas generated so far. Group them into themes. Identify which ideas have the most energy, which could be combined, and which stand out. Propose a shortlist of the 3-5 strongest ideas or idea clusters for the group to focus on. Be fair and thorough."
        case .wildCard:
            return "You are the Wild Card. We're now evaluating ideas. Look at the shortlist and think about which ideas excite you most. Suggest unexpected combinations or extensions. If an idea seems too tame, propose how to make it bolder. Be constructive but push for ambition."
        case .pragmatist:
            return "You are the Pragmatist. We're now evaluating ideas. For each shortlisted idea, assess: How feasible is this? What would it take? What are the risks? What's the MVP version? Rank the ideas by effort-to-impact ratio. Be constructive — say \"here's how it could work.\""
        case .devilsAdvocate:
            return "You are the Devil's Advocate. For each shortlisted idea, find the weaknesses. What could go wrong? What assumptions are being made? What are we not seeing? Be respectful but rigorous. For each critique, suggest what would need to be true for the idea to succeed."
        case .scribe:
            return "You are observing the evaluation phase. Track the discussion, the critiques, and which ideas are surviving the evaluation. Your turn comes next in synthesis."
        case .inverter:
            return "You are the Inverter. Review the flipped solutions and evaluate: Which inversions produced the strongest, most actionable ideas? Rank them and suggest how to combine the best ones."
        default:
            return ""
        }
    }

    /// System prompt for the framing phase
    var framingPrompt: String {
        return "You are the Facilitator. The user has proposed a brainstorm topic. Your job is to: 1. Restate the topic as a clear, focused problem statement or \"How Might We\" question. 2. Identify 2-3 key dimensions or angles worth exploring. 3. Note any constraints or assumptions you'd want to clarify. Keep it concise — 3-4 short paragraphs max. End by presenting your proposed problem statement clearly."
    }

    /// System prompt for the synthesis phase
    var synthesisPrompt: String {
        switch self {
        case .facilitator:
            return "You are the Facilitator wrapping up the brainstorm. Summarize: What was the problem? What were the top ideas? What did evaluation reveal? Provide a clear recommendation or decision framework. End with 3-5 concrete next steps."
        case .scribe:
            return "You are the Scribe. Produce a clean, well-organized summary of the entire brainstorm session: 1. Problem Statement 2. All Ideas Generated (grouped by theme) 3. Evaluation Highlights (strengths, risks, feasibility) 4. Final Recommendations 5. Action Items. Use clear headings and bullet points. This document should stand on its own."
        default:
            return ""
        }
    }
}

// MARK: - Brainstorm Participant
//
// Maps a role to a specific model for this session.

struct BrainstormParticipant: Identifiable, Codable, Hashable {
    var id: UUID
    var role: BrainstormRole
    var qualifiedModelId: String
    var isEnabled: Bool

    init(role: BrainstormRole, qualifiedModelId: String, isEnabled: Bool = true) {
        self.id = UUID()
        self.role = role
        self.qualifiedModelId = qualifiedModelId
        self.isEnabled = isEnabled
    }
}
