import AppKit
import LifeOSCore
import LifeOSUI
import SwiftUI

/// La puerta por la que entra lo que viene de **fuera** de la app: el menú
/// Servicios, abrir un fichero con LifeOS, arrastrar algo a la ventana.
///
/// Vive aparte del `AppDelegate` porque tiene una regla propia que merece estar
/// escrita en un sitio: **lo que llega no se guarda a escondidas**. El texto pasa
/// por el flujo de captura (propuesta y revisión, como si se hubiera escrito); un
/// documento se sube y se dice qué ha pasado, sin inventarse nada.
@MainActor
final class IntakeCoordinator {
    private weak var model: LifeOSModel?
    private weak var panel: QuickCapturePanelController?

    func attach(model: LifeOSModel, panel: QuickCapturePanelController) {
        self.model = model
        self.panel = panel
    }

    /// Un texto que llega de fuera (selección del menú Servicios).
    ///
    /// Se abre el panel **antes** de mandarlo: lo que viene de fuera también se
    /// revisa, y sin panel el usuario no vería la propuesta.
    func accept(text: String) async {
        guard let model else { return }
        panel?.show()
        await model.receive(.text(text))
    }

    /// Ficheros abiertos con la app o arrastrados a ella.
    func accept(files: [URL]) async {
        guard let model, !files.isEmpty else { return }
        await model.receive(files: files)
        // Si el resultado hay que leerlo y la app está detrás, se trae al frente:
        // un aviso silencioso no sirve de nada.
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
