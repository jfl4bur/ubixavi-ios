/* EL DISEÑO: el TEMA MIDNIGHT de la web, copiado valor por valor.

   Es el tema por defecto de la app (negro puro, tarjetas de cristal translúcido y
   acento DORADO #d4a843, como los pantallazos que me pasaste). Todo lo que se pinta usa
   estos valores, así que la app se ve igual que la web.

   Los valores están sacados del CSS de la web ([data-theme="midnight"]), no inventados.
*/
import SwiftUI
import CoreLocation

/// Un color a partir de "#rrggbb" (es como se guardan categorías y etiquetas)
extension Color {
    init(hex: String) {
        var limpio = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if limpio.hasPrefix("#") { limpio.removeFirst() }
        guard limpio.count == 6, let valor = UInt32(limpio, radix: 16) else {
            self = Color(red: 0.58, green: 0.63, blue: 0.70)
            return
        }
        self = Color(
            red: Double((valor & 0xFF0000) >> 16) / 255.0,
            green: Double((valor & 0x00FF00) >> 8) / 255.0,
            blue: Double(valor & 0x0000FF) / 255.0
        )
    }

    /// Un color con transparencia, del mismo tono
    func conAlfa(_ alfa: Double) -> Color { opacity(alfa) }

    /// Color aleatorio del tema (para categorías nuevas)
    static func doradoDegradado(_ desde: Double = 0, _ hasta: Double = 1) -> LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#e8c060"), Color(hex: "#d4a843"), Color(hex: "#b8902e")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

enum Diseno {
    // ── Colores del tema midnight (los mismos que la web) ────────────────────
    static let fondo = Color.black
    static let fondoTarjeta = Color.white.opacity(0.045)      // --card
    static let fondoTarjetaAlta = Color.white.opacity(0.072)  // --card-hi
    static let fondoTarjetaBaja = Color.white.opacity(0.032)  // --card2
    static let fondoFila = Color(hex: "#0d0d0d")              // el item del swipe-row
    static let linea = Color.white.opacity(0.08)
    static let lineaFuerte = Color.white.opacity(0.13)
    static let texto = Color(hex: "#f5f5f7")
    static let apagado = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.48)

    /// Acento DORADO del tema midnight
    static let acento = Color(hex: "#d4a843")
    static let acentoSuave = Color(hex: "#d4a843").opacity(0.24)
    static let acentoBorde = Color(hex: "#d4a843").opacity(0.45)
    static let verde = Color(hex: "#32d74b")
    static let naranja = Color(hex: "#ff9f0a")
    static let naranjaPin = Color(hex: "#ff9f0a")
    static let morado = Color(hex: "#bf5af2")
    static let rosa = Color(hex: "#ff375f")
    static let peligro = Color(hex: "#ff453a")
    static let oro = Color(hex: "#d4a843")
    static let azul = Color(hex: "#5b7cfa")

    // ── Formas (radio 18 / 12 de la web) ─────────────────────────────────────
    static let radio: CGFloat = 18
    static let radioSm: CGFloat = 12
    static let radioFila: CGFloat = 18
    static let radioGrande: CGFloat = 26

    /// Colores del tráfico (los mismos que la web)
    static func colorTrafico(_ estado: String?) -> Color {
        switch estado {
        case "red": return Color(hex: "#ff453a")
        case "orange": return Color(hex: "#ff9f0a")
        case "green": return Color(hex: "#32d74b")
        default: return apagado
        }
    }

    static func textoTrafico(_ estado: String?, retrasoMin: Int?) -> String {
        let retraso = (retrasoMin ?? 0) > 0 ? " · +\(retrasoMin ?? 0) min" : ""
        switch estado {
        case "red": return "Atascado\(retraso)"
        case "orange": return "Moderado\(retraso)"
        case "green": return "Fluido"
        default: return "Sin datos"
        }
    }
}

// ── Letras ────────────────────────────────────────────────────────────────────
extension Font {
    static let disTitulo = Font.system(.title, design: .default).weight(.heavy)
    static let disSubtitulo = Font.system(.title2, design: .default).weight(.heavy)
    static let disFila = Font.system(.title3, design: .default).weight(.bold)
    static let disCuerpo = Font.system(.body, design: .default)
    static let disSecundario = Font.system(.subheadline, design: .default)
    static let disEtiqueta = Font.system(.caption, design: .default).weight(.bold)
    static let disNumero = Font.system(.largeTitle, design: .default).weight(.heavy)
}

// ── El fondo de la app (negro + los tres tintes de la web) ────────────────────
struct FondoMidnight: View {
    var body: some View {
        ZStack {
            Color.black
            // Los tres brillos suaves del tema: dorado arriba a la izquierda, verde
            // arriba a la derecha y morado abajo (los mismos del CSS)
            RadialGradient(
                colors: [Color(hex: "#d4a843").opacity(0.06), .clear],
                center: UnitPoint(x: 0.15, y: 0),
                startRadius: 0,
                endRadius: 420
            )
            RadialGradient(
                colors: [Color(hex: "#32d74b").opacity(0.04), .clear],
                center: UnitPoint(x: 0.9, y: 0.1),
                startRadius: 0,
                endRadius: 380
            )
            RadialGradient(
                colors: [Color(hex: "#bf5af2").opacity(0.05), .clear],
                center: UnitPoint(x: 0.5, y: 1.1),
                startRadius: 0,
                endRadius: 480
            )
        }
        .ignoresSafeArea()
    }
}

// ── Piezas de interfaz ────────────────────────────────────────────────────────
/// TARJETA de cristal: fondo blanco al 4,5 %, degradado suave y borde fino
struct Tarjeta: ViewModifier {
    var radio: CGFloat = Diseno.radio
    var relleno: CGFloat = 14
    var alta: Bool = false
    var opaca: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(relleno)
            .background {
                RoundedRectangle(cornerRadius: radio)
                    .fill(opaca ? Diseno.fondoFila : (alta ? Diseno.fondoTarjetaAlta : Diseno.fondoTarjeta))
                    .overlay {
                        if !opaca {
                            RoundedRectangle(cornerRadius: radio)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.08), .clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    }
            }
            .overlay(RoundedRectangle(cornerRadius: radio).stroke(Color.white.opacity(0.09), lineWidth: 0.5))
    }
}

extension View {
    func tarjeta(radio: CGFloat = Diseno.radio, relleno: CGFloat = 14, alta: Bool = false, opaca: Bool = false) -> some View {
        modifier(Tarjeta(radio: radio, relleno: relleno, alta: alta, opaca: opaca))
    }

    /// Fondo de la app (el tema midnight)
    func fondoApp() -> some View {
        background(FondoMidnight())
    }
}

/// El botón de la app: PÍLDORA DORADA con brillo, texto negro y sombra dorada
struct BotonApp: View {
    enum Tipo { case principal, fantasma, peligro, verde }
    let titulo: String
    var icono: String?
    var tipo: Tipo = .principal
    var compacto: Bool = false
    var accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 8) {
                if let icono = icono {
                    Image(systemName: icono).font(.system(size: compacto ? 15 : 18, weight: .bold))
                }
                Text(titulo)
                    .font(.system(size: compacto ? 15 : 17, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compacto ? 11 : 16)
            .padding(.horizontal, 16)
            .foregroundColor(textoColor)
            .background(fondo)
            .clipShape(RoundedRectangle(cornerRadius: compacto ? Diseno.radioSm : 16))
            .overlay(
                RoundedRectangle(cornerRadius: compacto ? Diseno.radioSm : 16)
                    .stroke(borde, lineWidth: 0.5)
            )
            .shadow(color: sombra, radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var fondo: some View {
        switch tipo {
        case .principal:
            ZStack {
                Diseno.acento
                LinearGradient(colors: [Color.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)
            }
        case .fantasma:
            Diseno.fondoTarjetaBaja
        case .peligro:
            Diseno.peligro
        case .verde:
            Diseno.verde
        }
    }

    private var textoColor: Color {
        switch tipo {
        case .principal: return .black
        case .verde: return .black
        case .fantasma: return Diseno.texto
        case .peligro: return .white
        }
    }

    private var borde: Color {
        tipo == .principal ? Color.white.opacity(0.18) : Color.white.opacity(0.14)
    }

    private var sombra: Color {
        switch tipo {
        case .principal: return Diseno.acento.opacity(0.35)
        case .peligro: return Diseno.peligro.opacity(0.35)
        case .verde: return Diseno.verde.opacity(0.30)
        case .fantasma: return .clear
        }
    }
}

/// Abre el viaje entero en Google Maps (destino + paradas como puntos de paso)
func abrirViajeEnGoogleMaps(paradas: [Ubicacion], desde: CLLocationCoordinate2D?) {
    guard let destino = paradas.last ?? paradas.first else { return }
    var comp = URLComponents(string: "https://www.google.com/maps/dir/")!
    var items: [URLQueryItem] = [
        URLQueryItem(name: "api", value: "1"),
        URLQueryItem(name: "destination", value: "\(destino.lat),\(destino.lng)"),
    ]
    let intermedias = paradas.dropLast().dropFirst()
    if !intermedias.isEmpty {
        items.append(URLQueryItem(name: "waypoints", value: intermedias.map { "\($0.lat),\($0.lng)" }.joined(separator: "|")))
    }
    if let desde = desde {
        items.append(URLQueryItem(name: "origin", value: "\(desde.latitude),\(desde.longitude)"))
    }
    comp.queryItems = items
    if let url = comp.url {
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }
}

/* COMPARTIR CON EL MENÚ DE APPLE: el mismo que sale en la web con navigator.share
   (mensajes, WhatsApp, correo, copiar…). Se le pasa el texto y, si hay, el enlace. */
struct Compartir: Identifiable {
    let id = UUID()
    let texto: String
    let url: URL?
}

#if canImport(UIKit)
struct HojaCompartir: UIViewControllerRepresentable {
    let texto: String
    let url: URL?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var cosas: [Any] = [texto]
        if let url = url { cosas.append(url) }
        return UIActivityViewController(activityItems: cosas, applicationActivities: nil)
    }

    func updateUIViewController(_ controlador: UIActivityViewController, context: Context) {}
}
#endif

extension View {
    /// Saca la hoja de compartir del sistema cuando `valor` deja de ser nil
    func hojaCompartir(_ valor: Binding<Compartir?>) -> some View {
        #if canImport(UIKit)
        return sheet(item: valor) { datos in
            HojaCompartir(texto: datos.texto, url: datos.url)
        }
        #else
        return self
        #endif
    }
}

/// El enlace de Google Maps con todas las paradas, como el que comparte la web
func enlaceRutaGoogleMaps(_ paradas: [Ubicacion]) -> URL? {
    let conCoordenadas = paradas.filter { $0.tieneCoordenadas }
    guard !conCoordenadas.isEmpty else { return nil }
    let camino = conCoordenadas.map { "\($0.lat),\($0.lng)" }.joined(separator: "/")
    return URL(string: "https://www.google.com/maps/dir/\(camino)")
}

/// El botón flotante dorado (el «+» de la lista, el de capturar radares)
struct FabDorado: View {    let icono: String
    var accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Image(systemName: icono)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 62, height: 62)
                .background(LinearGradient(
                    colors: [Color(hex: "#e8c060"), Diseno.acento, Color(hex: "#b8902e")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), in: Circle())
                .shadow(color: Diseno.acento.opacity(0.5), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
    }
}

/// Botón redondo para el mapa (centrar, norte, ruta entera)
struct BotonRedondo: View {
    let icono: String
    var color: Color = Diseno.texto
    var tamano: CGFloat = 50
    /// Si trae texto, sale el texto en vez del icono (el botón 3D/2D de Apple Maps)
    var texto: String?
    var accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Group {
                if let texto = texto {
                    Text(texto)
                        .font(.system(size: tamano * 0.34, weight: .heavy))
                } else {
                    Image(systemName: icono)
                        .font(.system(size: tamano * 0.44, weight: .bold))
                }
            }
            .foregroundColor(color)
            .frame(width: tamano, height: tamano)
            .background {
                    Circle()
                        .fill(Diseno.fondoTarjetaAlta)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}

/// Las «pastillas» de estado: como los .chip de la web
struct Pastilla: View {
    let texto: String
    var color: Color = Diseno.apagado
    var relleno: Bool = true

    var body: some View {
        Text(texto)
            .font(.disEtiqueta)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(relleno ? color.opacity(0.16) : .clear, in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 0.5))
            .foregroundColor(color)
    }
}

/// El chip de filtro (categorías, etiquetas): el mismo que la web
struct Chip: View {
    let texto: String
    var color: Color?
    var activo: Bool
    var accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Text(texto)
                .font(.system(size: 15, weight: .bold))
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .foregroundColor(activo ? (color ?? Diseno.acento) : Diseno.texto)
                .background(
                    activo ? (color ?? Diseno.acento).opacity(0.18) : Diseno.fondoTarjeta,
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(
                        activo ? (color ?? Diseno.acento).opacity(0.6) : Color.white.opacity(0.10),
                        lineWidth: activo ? 1 : 0.5
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

/// La barra de progreso (la usan el viaje y las rutas)
struct BarraProgreso: View {
    var valor: Double
    var alto: CGFloat = 6
    var color: Color = Diseno.acento

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(LinearGradient(colors: [color, Diseno.verde], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geo.size.width * min(max(valor, 0), 1)))
            }
        }
        .frame(height: alto)
    }
}

/* LA BARRA DE PROGRESO DE LA RUTA, con los números de la web:
   pista de 12 px en blanco al 10 % y relleno con el degradado verde → dorado → granate
   (y granate apagado cuando ya está al 100 %, como la web). */
struct BarraProgresoRuta: View {
    var valor: Double

    private var progreso: Double { min(max(valor, 0), 1) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(
                        progreso >= 1
                            ? LinearGradient(colors: [Color(hex: "#6e2429"), Color(hex: "#6e2429")], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(
                                colors: [Diseno.verde, Diseno.acento, Color(hex: "#5c1e22")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                    )
                    .frame(width: max(0, geo.size.width * progreso))
            }
        }
        .frame(height: 12)
    }
}

/// La cabecera de la barra («Progreso total de la ruta» + el porcentaje en grande)
struct CabeceraProgresoRuta: View {
    var valor: Double

    private var porcentaje: Int { Int((min(max(valor, 0), 1) * 100).rounded()) }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Progreso total de la ruta")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Diseno.apagado)
                Spacer()
                Text("\(porcentaje)%")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(Diseno.texto)
            }
            BarraProgresoRuta(valor: valor)
        }
    }
}

/* LAS DOS TARJETAS DE TOTALES DE LA WEB: arriba lo que QUEDA en grande y debajo, en
   pequeño y apagado, el total del viaje (km en verde, tiempo en naranja). */
struct PanelTotalesRuta: View {
    var kmRestantes: Double
    var kmTotales: Double
    var minutosRestantes: Int
    var minutosTotales: Int

    var body: some View {
        HStack(spacing: 12) {
            tarjeta(
                principal: textoKm(kmRestantes),
                etiquetaPrincipal: "Km restantes",
                secundario: textoKm(kmTotales),
                etiquetaSecundario: "Km totales",
                color: Diseno.verde
            )
            tarjeta(
                principal: textoMinutos(minutosRestantes),
                etiquetaPrincipal: "Tiempo restante",
                secundario: textoMinutos(minutosTotales),
                etiquetaSecundario: "Tiempo total",
                color: Diseno.naranja
            )
        }
    }

    private func textoKm(_ km: Double) -> String {
        km < 1 ? "\(Int((km * 1000).rounded())) m" : String(format: "%.1f km", km)
    }

    private func textoMinutos(_ minutos: Int) -> String {
        if minutos < 60 { return "\(minutos) min" }
        let horas = minutos / 60
        let resto = minutos % 60
        return resto == 0 ? "\(horas) h" : "\(horas) h \(resto) min"
    }

    private func tarjeta(
        principal: String,
        etiquetaPrincipal: String,
        secundario: String,
        etiquetaSecundario: String,
        color: Color
    ) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(principal)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(etiquetaPrincipal)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Diseno.apagado)
            }
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 110, height: 1)
                .padding(.vertical, 9)
            VStack(spacing: 2) {
                Text(secundario)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(color.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(etiquetaSecundario)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Diseno.apagado)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
        .padding(.horizontal, 10)
        .background(Diseno.fondoTarjetaAlta, in: RoundedRectangle(cornerRadius: Diseno.radio))
        .overlay(RoundedRectangle(cornerRadius: Diseno.radio).stroke(Diseno.linea, lineWidth: 1))
    }
}

/// El selector de perfil (En coche / A pie), como la barra de la web
struct SelectorPerfil: View {
    @ObservedObject var estado: Estado

    private let opciones: [(String, String, String)] = [
        ("coche", "En coche", "car.fill"),
        ("pie", "A pie", "figure.walk"),
    ]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(opciones, id: \.0) { id, titulo, icono in
                let activo = estado.perfil == id
                Button {
                    Task { await estado.cambiarPerfil(id) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: icono).font(.system(size: 17, weight: .bold))
                        Text(titulo).font(.system(size: 16, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundColor(activo ? .black : Diseno.texto)
                    .background(
                        activo ? AnyShapeStyle(Diseno.acento) : AnyShapeStyle(Diseno.fondoTarjeta),
                        in: RoundedRectangle(cornerRadius: Diseno.radioSm)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Diseno.radioSm)
                            .stroke(activo ? .clear : Diseno.lineaFuerte, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Las cuatro tarjetas de totales del viaje (como el pie del panel de la web)
struct TotalesViaje: View {
    @ObservedObject var estado: Estado

    var body: some View {
        HStack(spacing: 10) {
            tarjeta(
                valor: estado.quedaKm.map { textoDistancia($0) } ?? "—",
                titulo: "Km restantes",
                color: Diseno.verde
            )
            tarjeta(
                valor: estado.rutaElegida.map { textoDuracion($0.durationMins) } ?? "—",
                titulo: "Tiempo restante",
                color: Diseno.acento
            )
        }
        HStack(spacing: 10) {
            tarjeta(
                valor: estado.totalKm.map { textoDistancia($0) } ?? estado.rutaElegida.map { textoDistancia($0.distKm) } ?? "—",
                titulo: "Km totales",
                color: Diseno.apagado
            )
            tarjeta(
                valor: estado.rutaElegida.map { textoDuracion($0.durationMins) } ?? "—",
                titulo: "Tiempo total",
                color: Diseno.apagado
            )
        }
    }

    private func tarjeta(valor: String, titulo: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(valor)
                .font(.system(size: 24, weight: .heavy))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(titulo)
                .font(.disEtiqueta)
                .foregroundColor(Diseno.apagado)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Diseno.fondoTarjetaBaja, in: RoundedRectangle(cornerRadius: Diseno.radioSm))
        .overlay(RoundedRectangle(cornerRadius: Diseno.radioSm).stroke(Diseno.linea, lineWidth: 0.5))
    }
}

/* LOS DOS PANELES DE UN TRAMO (como los LegPanels de la web):
     · a la izquierda, el TIEMPO que se tarda y los KM, con el tiempo del color del
       tráfico,
     · a la derecha, la HORA DE LLEGADA en grande y la pastilla del tráfico.
   Si la parada ya está hecha, se queda en gris y tachado (como en la web). */
struct PanelesTramo: View {
    var minutos: Double
    var km: Double
    var trafico: String?
    var retrasoMin: Int?
    var hecho: Bool = false
    var sinTrafico: Bool = false
    /// La hora de llegada YA calculada (encadenada). Si no viene, se estima con la duración
    var llegada: Date?

    private var colorTiempo: Color {
        hecho ? Diseno.apagado : Diseno.colorTrafico(trafico)
    }

    private var horaLlegada: String {
        let fecha = llegada ?? Date().addingTimeInterval(minutos * 60)
        let formato = DateFormatter()
        formato.dateFormat = "HH:mm"
        return formato.string(from: fecha)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Panel del tiempo y los km
            VStack(alignment: .leading, spacing: 6) {
                Text(textoDuracion(minutos))
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(colorTiempo)
                    .strikethrough(hecho)
                Text(textoDistancia(km))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Diseno.apagado)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 13)
            .background(Diseno.fondoTarjetaBaja, in: RoundedRectangle(cornerRadius: Diseno.radioSm))
            .overlay(RoundedRectangle(cornerRadius: Diseno.radioSm).stroke(Diseno.lineaFuerte, lineWidth: 0.5))

            // Panel de la hora de llegada y el tráfico
            VStack(spacing: 6) {
                Text(hecho ? "Llegado" : horaLlegada)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundColor(hecho ? Diseno.apagado : colorTiempo)
                    .strikethrough(hecho)
                if !sinTrafico {
                    Pastilla(
                        texto: Diseno.textoTrafico(hecho ? nil : trafico, retrasoMin: hecho ? 0 : retrasoMin),
                        color: hecho ? Diseno.apagado : Diseno.colorTrafico(trafico)
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 10)
            .background(Diseno.fondoTarjetaBaja, in: RoundedRectangle(cornerRadius: Diseno.radioSm))
            .overlay(RoundedRectangle(cornerRadius: Diseno.radioSm).stroke(Diseno.lineaFuerte, lineWidth: 0.5))
        }
    }
}

/* EL FONDO DEL PANEL NATIVO (negro transparente, sin difuminado), pero sólo si el iOS lo
   soporta: `presentationBackground` y `presentationCornerRadius` piden iOS 16.4. En iOS
   anteriores se queda el fondo del sistema (y no pasa nada). */
extension View {
    @ViewBuilder
    func fondoDelPanelNativo() -> some View {
        if #available(iOS 16.4, *) {
            self
                .presentationCornerRadius(20)
                // UN POQUITO de blur (cristal) pero transparente: se sigue viendo el mapa
                .presentationBackground {
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        Color.black.opacity(0.30)
                    }
                }
        } else {
            self
        }
    }
}