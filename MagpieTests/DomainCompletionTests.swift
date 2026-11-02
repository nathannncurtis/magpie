import Testing

@testable import Magpie

@Suite("DomainCompletion")
struct DomainCompletionTests {

    private let completion = DomainCompletion(
        userHosts: ["recipes.example", "www.Notes.example"],
        popularHosts: ["github.com", "gitlab.com", "google.com", "www.wikipedia.org", "x.com"])

    @Test("a prefix of a host completes to the rest of it")
    func completesPrefix() {
        #expect(completion.suffix(for: "git") == "hub.com")
        #expect(completion.suffix(for: "goo") == "gle.com")
        #expect(completion.suffix(for: "github.c") == "om")
    }

    @Test("the user's own hosts come before the well-known ones")
    func userHostsFirst() {
        let both = DomainCompletion(userHosts: ["gitea.example"], popularHosts: ["github.com"])

        #expect(both.suffix(for: "git") == "ea.example")
        #expect(both.suffix(for: "gith") == "ub.com")
    }

    @Test("matching ignores case and a leading www on either side")
    func ignoresCaseAndWWW() {
        #expect(completion.suffix(for: "GIT") == "hub.com")
        #expect(completion.suffix(for: "wiki") == "pedia.org")
        #expect(completion.suffix(for: "www.wiki") == "pedia.org")
        #expect(completion.suffix(for: "note") == "s.example")
    }

    @Test("a whole host has nothing left to complete")
    func wholeHost() {
        #expect(completion.suffix(for: "github.com") == nil)
        #expect(completion.suffix(for: "x.com") == nil)
    }

    @Test("nothing completes when no host starts with the text")
    func noMatch() {
        #expect(completion.suffix(for: "zzz") == nil)
        #expect(completion.suffix(for: "ithub") == nil)
    }

    @Test("text that is not the start of a bare host is left alone")
    func notAHost() {
        #expect(completion.suffix(for: "") == nil)
        #expect(completion.suffix(for: "git hub") == nil)
        #expect(completion.suffix(for: "github.com/an") == nil)
        #expect(completion.suffix(for: "https://git") == nil)
        #expect(completion.suffix(for: "github.com:80") == nil)
        #expect(completion.suffix(for: "gith?") == nil)
        #expect(completion.suffix(for: "gïthub") == nil)
    }

    @Test("a single letter completes, to the first host in order")
    func singleLetter() {
        #expect(completion.suffix(for: "g") == "ithub.com")
        #expect(completion.suffix(for: "x") == ".com")
    }

    @Test("the bundled list loads, with no duplicates and only bare hosts")
    func bundledList() {
        let hosts = DomainCompletion.bundledHosts

        #expect(hosts.count > 100)
        #expect(hosts.count <= 500)
        #expect(Set(hosts).count == hosts.count)
        #expect(hosts.allSatisfy { !$0.contains("/") && !$0.contains(" ") && $0.contains(".") })
        #expect(DomainCompletion().suffix(for: "wikip") == "edia.org")
    }
}
