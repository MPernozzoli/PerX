import Testing
@testable import PerXCore

struct PerXCoreTests {
    @Test func stateCodesExposeSystemAndVisibleBoundaries() {
        #expect(StatoSinistro.inGestione.isVisible)
        #expect(!StatoSinistro.inGestione.isSystemState)
        #expect(StatoSinistro.revocata.isSystemState)
        #expect(!StatoSinistro.revocata.isVisible)
    }

    @Test func closureDistanceReflectsWorkflowProgress() {
        #expect(StatoSinistro.chiusa.distanceFromClosure == 0)
        #expect(StatoSinistro.inControllo.distanceFromClosure < StatoSinistro.inGestione.distanceFromClosure)
        #expect(StatoSinistro.inGestione.distanceFromClosure < StatoSinistro.daScaricare.distanceFromClosure)
    }

    @Test func htmlStrippingDecodesEntitiesAndNormalizesWhitespace() {
        let source = "<p>PerX&nbsp;&amp; test</p>\n<strong>operativo</strong>"
        #expect(source.stripHTML() == "PerX & test operativo")
    }
}
