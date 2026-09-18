import Testing
@testable import InkflowCore

@Test func buildCapabilitiesMatchTheSigningVariant() {
    #if LOCAL_ONLY
    #expect(!BuildFeatures.cloudSync)
    #expect(!BuildFeatures.shareExtension)
    #else
    #expect(BuildFeatures.cloudSync)
    #expect(BuildFeatures.shareExtension)
    #endif
}
