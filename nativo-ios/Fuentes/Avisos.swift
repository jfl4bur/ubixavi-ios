/* AVISOS: VOZ Y PITIDOS, TODO NATIVO.

   La voz es la de iOS (AVSpeechSynthesizer) y los pitidos se generan aquí con
   AVAudioEngine: es el MISMO código que ya funcionaba en la app anterior (dentro del
   WebView el audio de la web tiene latencia y a veces no suena; aquí sale siempre).

   La sesión de audio es de MEDIOS (.playback + .voicePrompt): así el aviso sale por los
   ALTAVOCES DEL COCHE (Bluetooth o CarPlay) y no por el altavoz del móvil.
*/
import Foundation
import AVFoundation

@MainActor
final class Avisos {
    private let voz = AVSpeechSynthesizer()
    private let motor = AVAudioEngine()
    private let reproductor = AVAudioPlayerNode()
    private var motorListo = false

    init() {
        activarSesion()
    }

    func activarSesion() {
        do {
            let sesion = AVAudioSession.sharedInstance()
            try sesion.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.mixWithOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try sesion.setActive(true)
        } catch {
            NSLog("Avisos: sesión de audio: \(error)")
        }
    }

    private func prepararMotor() {
        guard !motorListo else { return }
        motor.attach(reproductor)
        let formato = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        motor.connect(reproductor, to: motor.mainMixerNode, format: formato)
        motor.mainMixerNode.outputVolume = 1.0
        do {
            try motor.start()
            reproductor.play()
            motorListo = true
        } catch {
            NSLog("Avisos: el motor de audio no arranca: \(error)")
        }
    }

    /// Pitidos: se genera UN buffer con los N pitidos ya separados, así el ritmo es exacto
    func pitidos(veces: Int, frecuencia: Double = 630, separacionMs: Double = 140, duracion: Double = 0.09, volumen: Float = 0.65) {
        prepararMotor()
        guard motorListo else { return }
        let cuantos = max(1, min(12, veces))
        let formato = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let sr = formato.sampleRate
        let porPitido = AVAudioFrameCount(sr * duracion)
        let salto = AVAudioFrameCount(sr * (separacionMs / 1000.0))
        let total = salto * AVAudioFrameCount(max(0, cuantos - 1)) + porPitido
        guard let buffer = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: total) else { return }
        buffer.frameLength = total
        if let datos = buffer.floatChannelData?[0] {
            for i in 0..<Int(total) { datos[i] = 0 }
            for v in 0..<cuantos {
                let inicio = Int(salto) * v
                for i in 0..<Int(porPitido) {
                    let t = Double(i) / sr
                    // Envolvente suave: suena a «bip», no a chasquido
                    let ataque = min(1.0, Double(i) / (sr * 0.006))
                    let caida = min(1.0, Double(Int(porPitido) - i) / (sr * 0.02))
                    datos[inicio + i] = Float(sin(2 * Double.pi * frecuencia * t) * Double(volumen) * ataque * caida)
                }
            }
        }
        reproductor.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !reproductor.isPlaying { reproductor.play() }
    }

    func decir(_ texto: String) {
        activarSesion()
        let frase = AVSpeechUtterance(string: texto)
        frase.voice = AVSpeechSynthesisVoice(language: "es-ES")
        frase.rate = 0.5
        frase.volume = 1
        voz.speak(frase)
    }

    func callar() {
        voz.stopSpeaking(at: .immediate)
    }
}
