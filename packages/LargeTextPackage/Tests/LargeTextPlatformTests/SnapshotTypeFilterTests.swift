import Testing
@testable import LargeTextPlatform

@Suite struct SnapshotTypeFilterTests {
    @Test(arguments: [
        "public.utf8-plain-text", "public.rtf", "public.html", "public.png", "public.file-url",
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.apple.webarchive",
    ])
    func includesRegularTypesAndMarkers(type: String) {
        #expect(SnapshotTypeFilter.shouldInclude(type))
    }

    @Test(arguments: [
        "dyn.ah62d4rv4gu8yc6durvwwaznwmuuha2pxsvw0e55bsmwca7d3sbwu",
        "com.apple.NSFilePromiseItemMetaData",
        "com.apple.pasteboard.promised-file-url",
        "com.apple.pasteboard.promised-file-content-type",
        "NSPromiseContentsPboardType",
        "Apple files promise pasteboard type",
    ])
    func skipsDynamicAndPromiseTypes(type: String) {
        #expect(!SnapshotTypeFilter.shouldInclude(type))
    }
}
