import CoreAudio
@testable import DontSwitchMicsCore
import Testing

@Suite
struct OSStatusFormattingTests {
    @Test
    func printableFourCharacterStatusIncludesIntegerAndFourCC() {
        let status = OSStatus(0x6E6F7065) // 'nope'
        let description = CoreAudioDeviceError.osStatus(operation: "Test operation", status: status).description

        #expect(description.contains("1852797029"))
        #expect(description.contains("'nope'"))
        #expect(description.contains("0x6E6F7065"))
    }

    @Test
    func negativeStatusIncludesSignedIntegerAndFallbackFourCC() {
        let description = CoreAudioDeviceError.osStatus(operation: "Bad parameter", status: -50).description

        #expect(description.contains("-50"))
        #expect(description.contains("'....'"))
        #expect(description.contains("0xFFFFFFCE"))
    }
}
