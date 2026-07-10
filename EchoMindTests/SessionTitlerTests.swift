import Testing
import Foundation
@testable import EchoMind

/// F3: AI session titles. Placeholder detection must be conservative (never
/// clobber a user rename); sanitization must turn messy model output into a
/// clean list title or nothing.
@Suite struct SessionNamingTests {
    let created = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func placeholderRoundTrips() {
        let placeholder = SessionNaming.defaultTitle(created)
        #expect(SessionNaming.isPlaceholder(placeholder, createdAt: created))
    }

    @Test func userTitlesAreNotPlaceholders() {
        #expect(!SessionNaming.isPlaceholder("Q3 Launch Planning", createdAt: created))
        // Even a user title that STARTS with "Meeting" must not match.
        #expect(!SessionNaming.isPlaceholder("Meeting with Bob", createdAt: created))
    }

    @Test func placeholderForDifferentDateDoesNotMatch() {
        let other = SessionNaming.defaultTitle(created.addingTimeInterval(3_600))
        #expect(!SessionNaming.isPlaceholder(other, createdAt: created))
    }
}

@Suite struct MeetingTitlerSanitizationTests {
    @Test func stripsQuotesLabelsAndTrailingPunctuation() {
        #expect(MeetingTitler.sanitized("\"Q3 Launch Planning.\"") == "Q3 Launch Planning")
        #expect(MeetingTitler.sanitized("Title: Budget Review") == "Budget Review")
        #expect(MeetingTitler.sanitized("“Hiring Sync”") == "Hiring Sync")
    }

    @Test func firstLineOnly() {
        #expect(MeetingTitler.sanitized("Roadmap Review\nHere is why I chose it") == "Roadmap Review")
    }

    @Test func capsLengthAtWordBoundary() {
        let long = "An Extremely Long Title About The Quarterly Marketing Budget Review Session"
        let result = MeetingTitler.sanitized(long)
        #expect(result != nil)
        #expect((result ?? "").count <= MeetingTitler.maxTitleLength)
        #expect(!(result ?? "").hasSuffix(" "))   // clean word-boundary cut
    }

    @Test func rejectsEmptyAndGenericOutput() {
        #expect(MeetingTitler.sanitized(nil) == nil)
        #expect(MeetingTitler.sanitized("") == nil)
        #expect(MeetingTitler.sanitized("   ") == nil)
        #expect(MeetingTitler.sanitized("Meeting") == nil)
        #expect(MeetingTitler.sanitized("\"\"") == nil)
        #expect(MeetingTitler.sanitized("ab") == nil)   // below minimum length
    }
}
