# Reporte de Optimización de Código - JUST4PICT

Este documento detalla las áreas de mejora identificadas en el análisis del código y las soluciones propuestas para mejorar el rendimiento y la gestión de recursos.

## 1. Optimización de I/O en `OpenAIImageReconstructionService`

**Ubicación:** `Sources/JUST4PICT/OpenAIImageReconstructionService.swift`

### Problema

El método `pixelSize(for:)` inicializa un `CGImageSource` pasando `nil` como opciones. Esto permite que el sistema utilice los valores predeterminados, lo que puede causar que ImageIO intente decodificar especulativamente la imagen o cachearla en memoria, aunque el objetivo sea únicamente leer sus dimensiones (metadatos). Esto resulta en un uso ineficiente de memoria y operaciones de E/S innecesarias, especialmente con imágenes grandes.

### Solución

Especificar explícitamente `kCGImageSourceShouldCache: false` durante la creación del `CGImageSource`. Esto instruye al sistema para leer solo las propiedades del encabezado sin decodificar los datos de píxeles.

### Implementación sugerida

```swift
    private func pixelSize(for inputURL: URL) -> CGSize {
        // Optimización: kCGImageSourceShouldCache: false evita decodificación innecesaria
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return .zero
        }

        return CGSize(width: width, height: height)
    }
```

## 2. Optimización de Recursos en `ImageEnhancerDiagnosticsTests`

**Ubicación:** `Tests/JUST4PICTTests/ImageEnhancerDiagnosticsTests.swift`

### Problema

Los métodos auxiliares de los tests, como `averageRGBA` y `averageEdgeEnergy`, instancian un nuevo `CIContext` (contexto Metal) cada vez que son invocados. La creación de un contexto es una operación pesada que implica compilación de shaders e inicialización de recursos GPU. En suites de pruebas que realizan múltiples verificaciones o bucles de benchmark, esto introduce una latencia significativa y sobrecarga innecesariamente el sistema.

### Solución

Utilizar una instancia estática y compartida de `CIContext` para toda la clase de pruebas. Esto alinea la estrategia de pruebas con la arquitectura de producción (que ya usa un contexto compartido en `ImageEnhancer`) y reduce drásticamente el tiempo de ejecución de los tests.

### Implementación sugerida

```swift
final class ImageEnhancerDiagnosticsTests: XCTestCase {
    // ...
    
    // Optimización: Instancia compartida para evitar recreación costosa en cada test
    private static let sharedDiagnosticContext = CIContext(options: [.cacheIntermediates: false])

    // ... 
    
    private func averageRGBA(...) {
        // En lugar de crear let context = CIContext()...
        // Usar:
        // Self.sharedDiagnosticContext.render(...)
    }
}
```
