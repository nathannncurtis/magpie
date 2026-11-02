import Foundation
import Testing

@testable import Magpie

@Suite("DownloadNaming")
struct DownloadNamingTests {

    @Test("the server's suggestion wins, cleaned of path parts")
    func suggestionWins() {
        let url = URL(string: "https://example.com/files/other.bin")
        #expect(DownloadNaming.name(suggested: "report.pdf", url: url, mimeType: nil) == "report.pdf")
        #expect(
            DownloadNaming.name(suggested: "../../etc/passwd", url: url, mimeType: nil)
                == "_.._etc_passwd")
        #expect(DownloadNaming.name(suggested: "a:b\\c.txt", url: url, mimeType: nil) == "a_b_c.txt")
        #expect(DownloadNaming.name(suggested: ".hidden", url: url, mimeType: nil) == "hidden")
    }

    @Test("with no suggestion the address names the file")
    func addressNames() {
        let url = URL(string: "https://example.com/files/my%20photo.jpg?x=1")
        #expect(DownloadNaming.name(suggested: nil, url: url, mimeType: nil) == "my photo.jpg")
        #expect(DownloadNaming.name(suggested: "  ", url: url, mimeType: nil) == "my photo.jpg")
    }

    @Test("a bare address falls back, and the type gives an extension")
    func fallbackAndExtension() {
        let url = URL(string: "https://example.com/")
        #expect(DownloadNaming.name(suggested: nil, url: url, mimeType: nil) == "download")
        #expect(DownloadNaming.name(suggested: nil, url: url, mimeType: "application/pdf") == "download.pdf")
        #expect(
            DownloadNaming.name(suggested: "notes", url: url, mimeType: "text/plain") == "notes.txt")
        #expect(
            DownloadNaming.name(suggested: "notes.md", url: url, mimeType: "text/plain") == "notes.md")
    }

    @Test("a long name is cut, keeping its extension")
    func longNames() {
        let long = String(repeating: "a", count: 300) + ".pdf"
        let name = DownloadNaming.name(suggested: long, url: nil, mimeType: nil)
        #expect(name.count == DownloadNaming.maxLength)
        #expect(name.hasSuffix(".pdf"))
    }

    @Test("a taken name gets a number before its extension")
    func collisions() {
        #expect(DownloadNaming.uniqueName("a.pdf", existing: []) == "a.pdf")
        #expect(DownloadNaming.uniqueName("a.pdf", existing: ["a.pdf"]) == "a 2.pdf")
        #expect(DownloadNaming.uniqueName("a.pdf", existing: ["a.pdf", "a 2.pdf"]) == "a 3.pdf")
        #expect(DownloadNaming.uniqueName("A.PDF", existing: ["a.pdf"]) == "A 2.PDF")
        #expect(DownloadNaming.uniqueName("notes", existing: ["notes"]) == "notes 2")
        #expect(DownloadNaming.uniqueName("a.tar.gz", existing: ["a.tar.gz"]) == "a.tar 2.gz")
    }

    @Test("an attachment disposition is spotted however it is spelled")
    func attachments() {
        #expect(DownloadNaming.isAttachment(disposition: "attachment; filename=\"a.txt\""))
        #expect(DownloadNaming.isAttachment(disposition: "Attachment"))
        #expect(DownloadNaming.isAttachment(disposition: " ATTACHMENT ;filename=a"))
        #expect(!DownloadNaming.isAttachment(disposition: "inline; filename=a.txt"))
        #expect(!DownloadNaming.isAttachment(disposition: nil))
    }

    @Test("a request carries the cookies that match its address")
    func cookieMatching() throws {
        func cookie(_ domain: String, path: String = "/", secure: Bool = false) throws -> HTTPCookie {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: "n", .value: "v", .domain: domain, .path: path,
            ]
            if secure { properties[.secure] = "TRUE" }
            return try #require(HTTPCookie(properties: properties))
        }
        let url = try #require(URL(string: "https://files.example.com/a/b"))
        let jar = [
            try cookie(".example.com"), try cookie("files.example.com", path: "/a"),
            try cookie("other.com"), try cookie("example.com", path: "/z"),
            try cookie("evilexample.com"),
        ]
        #expect(DownloadNaming.cookies(jar, for: url).count == 2)

        let plain = try #require(URL(string: "http://example.com/"))
        #expect(DownloadNaming.cookies([try cookie("example.com", secure: true)], for: plain).isEmpty)
    }
}

@Suite("DownloadStore")
@MainActor
struct DownloadStoreTests {

    private func scratch() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "downloads-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func tempFile(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test("a finished file lands under its name, and the next of that name is numbered")
    func placing() throws {
        let store = DownloadStore(directory: scratch())
        let first = try DownloadStore.place(try tempFile("one"), named: "a.txt", in: store.directory)
        let second = try DownloadStore.place(try tempFile("two"), named: "a.txt", in: store.directory)
        #expect(first.lastPathComponent == "a.txt")
        #expect(second.lastPathComponent == "a 2.txt")
        #expect(try String(contentsOf: first, encoding: .utf8) == "one")

        store.reload()
        #expect(Set(store.files.map(\.name)) == ["a.txt", "a 2.txt"])
    }

    @Test("deleting removes the file from disk and the list")
    func deleting() throws {
        let store = DownloadStore(directory: scratch())
        _ = try DownloadStore.place(try tempFile("x"), named: "gone.txt", in: store.directory)
        store.reload()
        let file = try #require(store.files.first)
        store.delete(file)
        #expect(store.files.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
    }
}
