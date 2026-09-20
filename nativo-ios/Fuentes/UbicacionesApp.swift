/* ARRANQUE DE LA APP NATIVA.

   Aquí no hay WebView, ni puente, ni página que cargar: es una app de iOS normal, con su
   mapa de MapKit y sus gestos. Por eso arranca al instante y el mapa va fino.
*/
import SwiftUI
import AVFoundation

@main
struct UbicacionesNativoApp: App {
    @UIApplicationDelegateAdaptor(Delegado.self) private var delegado
    /// El tema se elige en Ajustes (por defecto, el midnight de la web)
    @AppStorage("modoOscuro") private var modoOscuro = true
    /// ¿Toca la animación de arranque? (sólo al iniciar la app de verdad)
    @State private var arrancando = !ArranqueAnimado.yaMostrado

    var body: some Scene {
        WindowGroup {
            ZStack {
                PantallaPrincipal()
                    .preferredColorScheme(modoOscuro ? .dark : .light)

                if arrancando {
                    ArranqueAnimado {
                        ArranqueAnimado.yaMostrado = true
                        arrancando = false
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
        }
    }
}

final class Delegado: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        /* SESIÓN DE AUDIO DE MEDIOS: categoría .playback y modo .voicePrompt (lo mismo que
           usa Google Maps). Así el aviso de radar sale por los ALTAVOCES DEL COCHE
           (Bluetooth o CarPlay) y no por el altavoz del móvil, y la música sigue sonando.
           Se deja ACTIVA: antes se ponía la categoría pero no se activaba y iOS seguía
           usando la suya. */
        do {
            let sesion = AVAudioSession.sharedInstance()
            try sesion.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.mixWithOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try sesion.setActive(true)
        } catch {
            NSLog("audio session: \(error)")
        }
        return true
    }
}
