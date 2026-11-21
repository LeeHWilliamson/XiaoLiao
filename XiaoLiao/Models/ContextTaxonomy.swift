import Foundation

/// Stable machine identifiers; localized display labels belong at the view boundary.
/// Tags describe attempted content/tasks, never grammatical success or proficiency.
nonisolated enum ContextTaxonomy {
    static let version = "learning-context-v1"

    enum Topic: String, CaseIterable, Codable, Hashable, Sendable {
        case unclassified
        case dailyLife = "daily-life"
        case workAndCareers = "work-and-careers"
        case educationAndLearning = "education-and-learning"
        case travelAndPlaces = "travel-and-places"
        case foodAndDining = "food-and-dining"
        case relationshipsAndSocialLife = "relationships-and-social-life"
        case hobbiesAndEntertainment = "hobbies-and-entertainment"
        case healthAndWellbeing = "health-and-wellbeing"
        case shoppingAndServices = "shopping-and-services"
        case societyAndTechnology = "society-and-technology"
    }

    enum LanguageTask: String, CaseIterable, Codable, Hashable, Sendable {
        case unclassified
        case describing
        case recountingPastEvents = "recounting-past-events"
        case discussingHabits = "discussing-habits"
        case discussingPlansAndIntentions = "discussing-plans-and-intentions"
        case expressingOpinionsAndPreferences = "expressing-opinions-and-preferences"
        case explainingReasonsAndProcesses = "explaining-reasons-and-processes"
        case comparingAndEvaluating = "comparing-and-evaluating"
        case imaginingAndHypothesizing = "imagining-and-hypothesizing"
        case askingForInformationOrClarification = "asking-for-information-or-clarification"
        case makingRequestsOffersAndSuggestions = "making-requests-offers-and-suggestions"
    }

    enum Situation: String, CaseIterable, Codable, Hashable, Sendable {
        case unclassified
        case casualConversation = "casual-conversation"
        case meetingSomeone = "meeting-someone"
        case interview
        case workplaceInteraction = "workplace-interaction"
        case serviceEncounter = "service-encounter"
        case discussionOrDebate = "discussion-or-debate"
        case presentationOrStorytelling = "presentation-or-storytelling"
    }
}

/// Multiple tags may apply per dimension. Use [.unclassified] when unknown;
/// consumers must reject duplicates or mixing unclassified with known tags.
/// A missing analysis record means no classification has been performed.
nonisolated struct ContextTags: Codable, Equatable, Sendable {
    let topics: [ContextTaxonomy.Topic]
    let languageTasks: [ContextTaxonomy.LanguageTask]
    let situations: [ContextTaxonomy.Situation]
    /// Optional detail, not an aggregation key or a new taxonomy tag.
    let topicDescription: String?
}
