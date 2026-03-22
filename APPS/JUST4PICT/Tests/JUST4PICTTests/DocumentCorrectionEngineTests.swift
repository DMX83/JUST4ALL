import XCTest
import CoreImage
@testable import JUST4PICT

final class DocumentCorrectionEngineTests: XCTestCase {
    var sut: DocumentCorrectionEngine!
    var context: CIContext!

    override func setUp() {
        super.setUp()
        // Usamos contexto sin caché para reproducibilidad
        context = CIContext(options: [.cacheIntermediates: false])
        sut = DocumentCorrectionEngine(context: context)
    }

    override func tearDown() {
        sut = nil
        context = nil
        super.tearDown()
    }

    func testApplyIfNeeded_SkipsNonDocumentScenes() {
        // Given: Imagen dummy (color sólido)
        let image = CIImage(color: CIColor.red).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        
        // When: Escena es retrato y preset es auto
        let result = sut.applyIfNeeded(to: image, scene: .portrait, preset: .auto)
        
        // Then: Debe devolver la misma imagen sin procesar
        XCTAssertEqual(result, image)
    }

    func testApplyIfNeeded_SkipsNonDocumentPresets() {
        let image = CIImage(color: CIColor.blue).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        
        // When: Escena nula pero preset paisaje
        let result = sut.applyIfNeeded(to: image, scene: nil, preset: .landscape)
        
        XCTAssertEqual(result, image)
    }

    func testApplyIfNeeded_ReturnsOriginalIfVisionFailsToFindRectangles() {
        // Given: Imagen sólida donde Vision NO encontrará rectángulos
        let image = CIImage(color: CIColor.white).cropped(to: CGRect(x: 0, y: 0, width: 500, height: 500))
        
        // When: Forzamos la detección (scene .document)
        let result = sut.applyIfNeeded(to: image, scene: .document, preset: .auto)
        
        // Then: El fail-safe debe devolver la original
        XCTAssertEqual(result, image)
    }
}