/* EL AVISO DE RADAR, con el diseño EXACTO de la web.

   Copiado de src/components/RadarAlert.jsx + los estilos .radar-* de src/index.css:

   · Es un CARTEL CENTRADO en la pantalla, con una capa oscura detrás que lleva un pelín
     de rojo (degradado radial), igual que el modal de la web.
   · Arriba el TIPO de radar (28 px, muy grueso) y debajo la vía (17 px, gris #a9a9a9).
   · El BLOQUE ROJO es una cápsula de 145 px de alto, con su degradado de 160° y sus
     sombras. El VELOCÍMETRO va MONTADO ENCIMA: un círculo de 160×160 apoyado en el borde
     izquierdo, con un borde de 10 px del color del fondo del cartel (parece recortado) y
     el arco de un coche de verdad (270° desde 225°, del color del tipo; el resto, gris).
     Dentro, la velocidad en 48 px y «km/h» debajo.
   · LA CÁMARA DEL RADAR es la IMAGEN de su tipo (las mismas de la web), colocada arriba a
     la derecha del bloque, INCLINADA 25° y del color de la fiabilidad.
   · La SEÑAL DEL LÍMITE, de 110×110 con borde rojo de 8 px (o gris claro si no se sabe).
   · «Fiabilidad: ALTA/MEDIA/BAJA» en 24 px con sus tres puntos de 16 px.
   · La BARRA de distancia: 48 px de alto, redondeada, con el relleno azul de la web
     (degradado #2b7bff → #0a4fe0) que se VACÍA conforme te acercas, y los metros encima,
     en 26 px.
   · Al PASAR POR ENCIMA (a menos de 60 m) pregunta «¿Sigue ahí?» con Sí / No y una cuenta
     atrás de 5 s; si no contestas, no se hace nada. Es lo que hace la web.
   · Tocar fuera la cierra.
*/
import SwiftUI
import CoreLocation
import UIKit

struct AlertaRadar: View {
    let radar: Radar
    @ObservedObject var estado: Estado
    var alCerrar: () -> Void

    /// El color del fondo del cartel: lo usan el círculo del velocímetro y su borde
    private let fondoCartel = Color(hex: "#050505")
    private let velocidadMaxima: Double = 190
    private let arcoMaximo: Double = 270

    @State private var aparecer = false
    /// La pregunta de «¿sigue ahí?» (se vuelve a poner al cambiar de radar)
    @State private var preguntando = true
    @State private var segundos = 5
    @State private var contestada = false
    /// La distancia a la que ARRANCÓ el aviso: así la barra se vacía desde ahí
    @State private var distanciaInicial: Double?

    private var velocidad: Int? { estado.velocidadKmh }

    private var distancia: CLLocationDistance? {
        guard let pos = estado.posicion else { return nil }
        return CLLocation(latitude: radar.lat, longitude: radar.lng).distance(from: pos)
    }

    /// Se considera que estás ENCIMA del radar a menos de 60 m (la web usa 25 m sobre el
    /// punto exacto; con el GPS del móvil 60 m es lo mismo en la práctica)
    private var encima: Bool { (distancia ?? 9999) < 60 }

    private var umbral: Double { max(200, distanciaInicial ?? 800) }

    /// La barra se VACÍA conforme te acercas (llena = lejos, vacía = encima)
    private var restante: Double {
        guard let metros = distancia else { return 0 }
        return min(max(metros / umbral, 0), 1)
    }

    /// Fiabilidad: las mismas reglas que la web
    private var fiabilidad: (nivel: String, puntos: Int, color: Color) {
        var puntos = 1
        if radar.src == "dgt" || radar.src == "lufop" { puntos += 1 }
        if radar.speed != nil { puntos += 1 }
        if radar.dir != nil { puntos += 1 }
        if puntos >= 3 { return ("ALTA", 3, Diseno.verde) }
        if puntos == 2 { return ("MEDIA", 2, Diseno.naranja) }
        return ("BAJA", 1, Diseno.peligro)
    }

    /// El color del tipo de radar (los mismos de la web)
    private var colorTipo: Color {
        switch radar.kind ?? "" {
        case "fixed": return Color(hex: "#ff453a")
        case "section", "belt": return Color(hex: "#ff9f0a")
        case "redlight": return Color(hex: "#8b5cf6")
        case "tunnel", "mobile": return Color(hex: "#0a84ff")
        default: return Color(hex: "#ff453a")
        }
    }

    /// La imagen del tipo (las mismas que usa la web en el cartel)
    private var imagenTipo: String? {
        switch radar.kind ?? "" {
        case "fixed": return "RadarFixed"
        case "mobile": return "RadarMobile"
        case "section": return "RadarSection"
        case "redlight": return "RadarRedlight"
        case "tunnel": return "RadarTunnel"
        case "belt": return "RadarBelt"
        default: return nil
        }
    }

    /// Los grados del arco del velocímetro, como el de un coche (0 a 190 km/h)
    private var grados: Double {
        min(max(Double(velocidad ?? 0) / velocidadMaxima, 0), 1) * arcoMaximo
    }

    var body: some View {
        ZStack {
            // ── La capa oscura, con su pelín de rojo (como .radar-backdrop) ──────
            RadialGradient(
                colors: [Color(hex: "#780a06").opacity(0.55), Color.black.opacity(0.66)],
                center: UnitPoint(x: 0.5, y: 0.45),
                startRadius: 0,
                endRadius: 420
            )
            .background(Color.black.opacity(0.35))
            .ignoresSafeArea()
            .onTapGesture { alCerrar() }

            cartel
                .padding(.horizontal, 9)
                .scaleEffect(aparecer ? 1 : 0.94)
                .opacity(aparecer ? 1 : 0)
        }
        .transition(.opacity)
        .onAppear {
            distanciaInicial = distancia
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { aparecer = true }
            empezarCuentaAtras()
        }
        .onChange(of: radar.id) { _ in
            // Cada radar nuevo vuelve a preguntar
            preguntando = true
            contestada = false
            segundos = 5
            distanciaInicial = distancia
            empezarCuentaAtras()
        }
    }

    // ── El cartel ────────────────────────────────────────────────────────────
    private var cartel: some View {
        VStack(spacing: 0) {
            // El tipo y la vía
            VStack(spacing: 3) {
                Text(encima ? "Estás en el radar" : tipoTexto(radar.kind))
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                if let subtitulo = subtituloVia {
                    Text(subtitulo)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color(hex: "#a9a9a9"))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 18)

            // ── EL BLOQUE ROJO, con el velocímetro montado encima ────────────
            bloqueRojo

            // ── La fiabilidad ────────────────────────────────────────────────
            HStack(spacing: 8) {
                Text("Fiabilidad:")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color(hex: "#e2e2e2"))
                Text(fiabilidad.nivel)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(fiabilidad.color)
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { indice in
                        Circle()
                            .fill(indice < fiabilidad.puntos ? fiabilidad.color : Color.white.opacity(0.18))
                            .frame(width: 16, height: 16)
                    }
                }
            }
            .padding(.top, 22)
            .padding(.bottom, 14)

            // ── La barra azul de la distancia ────────────────────────────────
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(hex: "#17181c"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                GeometryReader { geo in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#2b7bff"), Color(hex: "#0a4fe0")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: geo.size.width * restante)
                }
                .clipShape(RoundedRectangle(cornerRadius: 24))
                Text(encima ? "Radar" : (distancia.map { textoDistanciaRadar($0) } ?? ""))
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 48)

            // ── «¿Sigue ahí?» al pasar por encima (con 5 s para contestar) ───
            if encima && preguntando && !contestada {
                VStack(spacing: 10) {
                    Text("¿Sigue ahí?")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundColor(Diseno.texto)
                    HStack(spacing: 10) {
                        BotonApp(titulo: "Sí", icono: "checkmark", tipo: .verde, compacto: true) {
                            contestada = true
                            Task { await responderSigueAhi(true) }
                        }
                        BotonApp(titulo: "No", icono: "xmark", tipo: .peligro, compacto: true) {
                            contestada = true
                            Task { await responderSigueAhi(false) }
                        }
                    }
                    Text("Si no contestas en \(segundos) s no se hace nada")
                        .font(.disEtiqueta)
                        .foregroundColor(Diseno.apagado)
                }
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(maxWidth: 452)
        .background(fondoCartel, in: RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.85), radius: 30, y: 13)
    }

    /// El bloque rojo con el velocímetro y la señal del límite
    private var bloqueRojo: some View {
        ZStack {
            // La cápsula roja (145 px de alto, con su degradado de 160°)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#ff2f22"), Color(hex: "#e01a10"), Color(hex: "#b81309")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 145)
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: Color(hex: "#e01a10").opacity(0.4), radius: 15, y: 6)

            // ── La señal del límite, pegada a la derecha ────────────────────
            HStack {
                Spacer(minLength: 0)
                senalLimite(radar.speed.map { Int($0) })
            }
            .padding(.trailing, 24)

            // ── EL VELOCÍMETRO, montado en el extremo izquierdo ─────────────
            HStack {
                velocimetro.offset(x: -6)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 145)
        // ── LA CÁMARA del radar: arriba a la derecha, saliéndose e inclinada 25° ──
        .overlay(alignment: .topTrailing) {
            imagenCamara.offset(x: 10, y: -22)
        }
    }

    private var velocimetro: some View {
        ZStack {
            /* El arco, como el de un coche: recorre 270° y arranca abajo a la izquierda
               (el `from 225deg` del conic-gradient de la web). El resto, gris; y el hueco
               de abajo se queda del color del cartel. */
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color(hex: "#8e8e8e"), style: StrokeStyle(lineWidth: 22, lineCap: .butt))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: min(grados / 360, 1))
                .stroke(colorTipo, style: StrokeStyle(lineWidth: 22, lineCap: .butt))
                .rotationEffect(.degrees(135))

            // El centro oscuro, con la velocidad
            Circle()
                .fill(fondoCartel)
                .frame(width: 112, height: 112)
            VStack(spacing: 3) {
                Text(velocidad.map { "\($0)" } ?? "--")
                    .font(.system(size: 48, weight: .heavy))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Text("km/h")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "#bdbdbd"))
            }
        }
        .frame(width: 150, height: 150)
        /* El borde del color del fondo del cartel: así el círculo parece RECORTADO sobre
           el rojo, como en la web. */
        .padding(12)
        .background(fondoCartel, in: Circle())
        .shadow(color: .black.opacity(0.55), radius: 8, y: 3)
    }

    /// La imagen de la cámara del tipo, inclinada y del color de la fiabilidad
    private var imagenCamara: some View {
        Group {
            if let nombre = imagenTipo, UIImage(named: nombre) != nil {
                Image(nombre)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                    .foregroundColor(fiabilidad.color)
            } else {
                Image(systemName: "camera.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(fiabilidad.color)
            }
        }
        .rotationEffect(.degrees(25))
        .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
    }

    /// La señal del límite: 110×110 con el borde rojo (o gris claro si no se sabe)
    private func senalLimite(_ limite: Int?) -> some View {
        ZStack {
            Circle()
                .fill(limite == nil ? Color.white.opacity(0.9) : Color.white)
                .frame(width: 94, height: 94)
            Circle()
                .stroke(limite == nil ? Color.white.opacity(0.7) : Color(hex: "#ff453a"), lineWidth: 8)
                .frame(width: 110, height: 110)
            Text(limite.map { "\($0)" } ?? "?")
                .font(.system(size: limite == nil ? 40 : (limite! >= 100 ? 34 : 42), weight: .heavy))
                .foregroundColor(Color(hex: "#111111"))
                .monospacedDigit()
        }
        .frame(width: 110, height: 110)
        .shadow(color: .black.opacity(0.35), radius: 7, y: 2)
    }

    // ── La vía (o la etiqueta del radar), como el subtítulo de la web ────────
    private var subtituloVia: String? {
        if let via = radar.label, !via.isEmpty {
            return via.count > 34 ? String(via.prefix(34)) : via
        }
        return nil
    }

    // ── La cuenta atrás de los 5 s (contra una hora límite, como la web) ─────
    private func empezarCuentaAtras() {
        Task { @MainActor in
            let limite = Date().addingTimeInterval(5)
            while Date() < limite {
                let quedan = max(0, Int(ceil(limite.timeIntervalSince(Date()))))
                if quedan != segundos { segundos = quedan }
                if quedan <= 0 {
                    // Sin respuesta en 5 segundos: no se hace nada y el aviso sigue igual
                    preguntando = false
                    return
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            preguntando = false
        }
    }

    /// «Sí» confirma el radar; «No» lo quita de la base propia (como la web)
    private func responderSigueAhi(_ si: Bool) async {
        let lat = radar.lat
        let lng = radar.lng
        let tipo = radar.kind ?? "fixed"
        if si {
            _ = try? await Servidor.capturarRadar(
                type: tipo,
                lat: lat,
                lng: lng,
                speed: radar.speed,
                role: nil,
                dir: radar.dir
            )
            AvisosFlotantes.compartido.bien("Gracias: radar confirmado")
        } else {
            try? await Servidor.borrarRadar(lat: lat, lng: lng, type: tipo)
            AvisosFlotantes.compartido.info("Radar quitado de tu base")
        }
        // Se cierra el cartel y, si era la demo, se para
        if estado.demoActiva { estado.pararDemo() }
        alCerrar()
    }
}

/// Los metros como en la web: sin decimales hasta 1 km, y a partir de ahí un decimal
func textoDistanciaRadar(_ metros: CLLocationDistance) -> String {
    if metros < 950 { return "\(Int((metros / 10).rounded()) * 10) m" }
    if metros < 10000 { return String(format: "%.1f km", metros / 1000) }
    return "\(Int((metros / 1000).rounded())) km"
}
