/* LA FILA DESLIZABLE (el «SwipeRow» de la web), copiado EXACTAMENTE de la web.

   Las cuentas están sacadas de src/components/SwipeRow.jsx, no inventadas:

   · UMBRALES: primero se ven los botones (su ancho), después el botón del borde se
     ESTIRA siguiendo al dedo (30 px de margen) y 30 px más allá VIBRA y queda armado:
     al soltar, esa acción se ejecuta.
         base  = max(120, min(200, ancho × 0,35))
         umbral = max(base, ancho_de_ese_lado + 30) + 30
   · VIBRACIÓN: al cruzar el umbral (y otra suave al volver atrás), con el motor nativo
     de iOS (UIImpactFeedbackGenerator).
   · AL CRUZAR EL UMBRAL: el icono se hace 1,4× más grande y se va AL BORDE del bloque
     (a la derecha si el bloque entra por la izquierda, y al revés), con animación; y la
     etiqueta de ese botón se esconde (los demás la siguen mostrando).
   · EL NOMBRE VA FUERA DEL CÍRCULO, debajo (como en la web: `.swipe-action-inner` es
     una columna con el círculo arriba y la etiqueta debajo, con 5 px de separación).
   · El CÍRCULO es REDONDO (46×46) mientras se revelan los botones: sólo se estira
     (convertido en pastilla) cuando el dedo pasa de lo que miden los botones.
   · GESTO COMPLETO: si sueltas pasado el umbral, se ejecuta la acción del borde
     (la primera de la izquierda o la última de la derecha) y la fila se cierra.
   · BLOQUEO DEL SCROLL: mientras el dedo va en horizontal, la lista NO se mueve. En la
     web esto lo resolvía `touch-action: pan-y`; aquí el ScrollView de SwiftUI no tiene
     nada equivalente, así que en cuanto el gesto se decide horizontal se apaga el scroll
     (`.scrollDisabled`) hasta que se suelta el dedo. Es lo que pediste.
   · Se cierra al TOCAR FUERA, al DESPLAZAR la lista y cuando se abre otra fila.
*/
import SwiftUI
import UIKit
import CoreLocation

/// Vibración del sistema (como la `haptic()` de la web, que usa el motor nativo)
enum Tacto {
    static func golpe(_ estilo: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generador = UIImpactFeedbackGenerator(style: estilo)
        generador.prepare()
        generador.impactOccurred()
    }

    static func seleccion() {
        let generador = UISelectionFeedbackGenerator()
        generador.prepare()
        generador.selectionChanged()
    }
}

struct AccionFila: Identifiable {
    let id = UUID()
    let titulo: String
    let icono: String
    let color: Color
    let accion: () -> Void
}

/// Saber qué fila está abierta, para cerrar las demás (y al tocar fuera o al desplazar)
@MainActor
final class FilasAbiertas: ObservableObject {
    static let compartida = FilasAbiertas()
    @Published var abierta: UUID?
    /* ¿Hay un dedo moviendo una fila de lado? Mientras sea «sí», las listas apagan su
       scroll: así el gesto del swipe no arrastra la lista (que es lo que pediste).
       En la web esto lo hace `touch-action: pan-y`; en SwiftUI hay que apagarlo a mano. */
    @Published var arrastrando = false

    func abrir(_ id: UUID) { abierta = id }
    func cerrarTodas() { abierta = nil }
}

struct FilaDeslizable<Contenido: View>: View {
    var izquierda: [AccionFila] = []
    var derecha: [AccionFila] = []
    var alTocar: (() -> Void)?
    @ViewBuilder var contenido: () -> Contenido

    // Medidas de la web
    private let anchoAccion: CGFloat = 76
    private let tamanoCirculo: CGFloat = 46
    private let radioCirculo: CGFloat = 23
    private let adelantoEstiron: CGFloat = 30 // STRETCH_LEAD
    private let extraUmbral: CGFloat = 30 // EXTRA_UMBRAL

    @ObservedObject private var abiertas = FilasAbiertas.compartida
    @State private var miId = UUID()
    @State private var desplazamiento: CGFloat = 0
    @State private var base: CGFloat = 0
    @State private var abierta = false
    @State private var arrastrando = false
    @State private var pasoUmbralDerecha = false
    @State private var pasoUmbralIzquierda = false
    @State private var anchoFila: CGFloat = 360

    private var anchoIzquierda: CGFloat { CGFloat(izquierda.count) * anchoAccion }
    private var anchoDerecha: CGFloat { CGFloat(derecha.count) * anchoAccion }

    private var umbralBase: CGFloat { max(120, min(200, anchoFila * 0.35)) }
    private var umbralIzquierda: CGFloat { max(umbralBase, anchoIzquierda + adelantoEstiron) + extraUmbral }
    private var umbralDerecha: CGFloat { max(umbralBase, anchoDerecha + adelantoEstiron) + extraUmbral }

    var body: some View {
        ZStack {
            // Las acciones van DETRÁS; el contenido (la tarjeta), delante y opaco
            HStack(spacing: 0) {
                if !izquierda.isEmpty { acciones(izquierda, ladoIzquierdo: true) }
                Spacer(minLength: 0)
                if !derecha.isEmpty { acciones(derecha, ladoIzquierdo: false) }
            }

            contenido()
                .background(Diseno.fondoFila)
                .clipShape(RoundedRectangle(cornerRadius: Diseno.radioFila))
                .contentShape(Rectangle())
                .offset(x: desplazamiento)
                .onTapGesture {
                    if abierta {
                        cerrar()
                    } else {
                        alTocar?()
                    }
                }
                .simultaneousGesture(gesto)
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { anchoFila = max(geo.size.width, 1) }
                    .onChange(of: geo.size.width) { nuevo in anchoFila = max(nuevo, 1) }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Diseno.radioFila))
        .overlay(
            RoundedRectangle(cornerRadius: Diseno.radioFila)
                .stroke(Color.white.opacity(0.09), lineWidth: 0.5)
        )
        .onChange(of: abiertas.abierta) { nueva in
            if nueva != miId && abierta { cerrar() }
        }
    }

    // ── Las acciones ─────────────────────────────────────────────────────────
    /* Cada celda nace con ancho 0 y crece hasta su tamaño real conforme se revela
       (desde el borde hacia dentro). El botón pegado al borde, al pasarse del ancho
       total de los botones, se ESTIRA siguiendo al dedo. */
    private func acciones(_ lista: [AccionFila], ladoIzquierdo: Bool) -> some View {
        let revelado = ladoIzquierdo ? max(0, desplazamiento) : max(0, -desplazamiento)
        let total = ladoIzquierdo ? anchoIzquierda : anchoDerecha
        let disparado = ladoIzquierdo ? disparoIzquierda : disparoDerecha
        let visible = ladoIzquierdo ? desplazamiento > 0 : desplazamiento < 0

        let anchos: [CGFloat] = lista.indices.map { indice in
            let distanciaAlBorde = ladoIzquierdo ? indice : (lista.count - 1 - indice)
            let base = min(anchoAccion, max(0, revelado - CGFloat(distanciaAlBorde) * anchoAccion))
            let estiron = distanciaAlBorde == 0 ? max(0, revelado - total) : 0
            return base + estiron
        }

        return HStack(spacing: 2) {
            ForEach(Array(lista.enumerated()), id: \.element.id) { indice, accion in
                let anchoCelda = anchos[indice]
                let crecido = min(1, max(0, anchoCelda / anchoAccion))
                let estiron = max(0, anchoCelda - anchoAccion)
                let distanciaAlBorde = ladoIzquierdo ? indice : (lista.count - 1 - indice)
                let esElQueSeEstira = distanciaAlBorde == 0 && disparado
                // El círculo se estira SÓLO al pasar de los botones (si no, es redondo)
                let anchoCirculo = estiron > 0
                    ? max(tamanoCirculo, min(anchoCelda - 8, tamanoCirculo + estiron))
                    : tamanoCirculo
                let radio = radioCirculo - 8 * (disparado ? 1 : min(1, estiron / adelantoEstiron))
                let progresoEstiron = disparado ? 1 : min(1, estiron / adelantoEstiron)
                let desplazamientoIcono = esElQueSeEstira
                    ? ((anchoCirculo - 24) / 2 - 18) * (ladoIzquierdo ? 1 : -1)
                    : 0
                let opacidadEtiqueta = esElQueSeEstira ? 0 : max(0, min(1, (crecido - 0.88) / 0.12))

                ZStack {
                    // El círculo de color (con el icono dentro)
                    Capsule()
                        .fill(accion.color)
                        .frame(width: anchoCirculo, height: tamanoCirculo)
                        .overlay(
                            Image(systemName: accion.icono)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .scaleEffect(esElQueSeEstira ? 1.4 : 1)
                                .offset(x: desplazamientoIcono)
                                .animation(.easeOut(duration: 0.24), value: esElQueSeEstira)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: max(radio, 8)))
                        .shadow(color: accion.color.opacity(0.4), radius: 6)
                        .scaleEffect(crecido)
                }
                .frame(width: anchoCelda, height: 62, alignment: .top)
                .overlay(alignment: .bottom) {
                    /* EL NOMBRE VA FUERA DEL CÍRCULO, DEBAJO (como la web, donde
                       `.swipe-action-inner` es una columna: círculo arriba y nombre
                       debajo, con 5 px de aire). Sólo se esconde el que se estira. */
                    Text(accion.titulo)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .opacity(opacidadEtiqueta)
                        .frame(width: anchoAccion)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    accion.accion()
                    cerrar()
                }
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(visible)
                .animation(arrastrando ? nil : .easeOut(duration: 0.2), value: progresoEstiron)
            }
        }
        .frame(width: ladoIzquierdo ? anchoIzquierda : anchoDerecha, alignment: ladoIzquierdo ? .leading : .trailing)
        .allowsHitTesting(visible)
    }

    private var disparoIzquierda: Bool { desplazamiento > umbralIzquierda }
    private var disparoDerecha: Bool { desplazamiento < -umbralDerecha }

    // ── El gesto ─────────────────────────────────────────────────────────────
    private var gesto: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { valor in
                let dx = valor.translation.width
                let dy = valor.translation.height
                /* El eje lo decide el movimiento: si va más en vertical, se deja el
                   scroll de la lista tal cual. */
                if !arrastrando {
                    guard abs(dx) > 8, abs(dx) > abs(dy) * 1.25 || desplazamiento != 0 else { return }
                    arrastrando = true
                    base = desplazamiento
                    FilasAbiertas.compartida.abrir(miId)
                    /* A PARTIR DE AQUÍ LA LISTA NO SE MUEVE: se apaga su scroll hasta
                       que se suelte el dedo (es el bloqueo que pediste). */
                    FilasAbiertas.compartida.arrastrando = true
                }
                // Se puede estirar hasta el ancho de la fila (como en la web)
                let bruto = base + dx
                let nuevo = min(max(bruto, -anchoFila), anchoFila)

                // VIBRACIÓN al cruzar el umbral (y otra suave al volver atrás)
                if !izquierda.isEmpty {
                    let pasado = nuevo > umbralIzquierda
                    if pasado != pasoUmbralIzquierda {
                        pasoUmbralIzquierda = pasado
                        Tacto.golpe(pasado ? .medium : .light)
                    }
                }
                if !derecha.isEmpty {
                    let pasado = nuevo < -umbralDerecha
                    if pasado != pasoUmbralDerecha {
                        pasoUmbralDerecha = pasado
                        Tacto.golpe(pasado ? .medium : .light)
                    }
                }
                desplazamiento = nuevo
            }
            .onEnded { _ in
                arrastrando = false
                // Se vuelve a encender el scroll de la lista
                FilasAbiertas.compartida.arrastrando = false
                let x = desplazamiento
                let izquierdaDisparada = !izquierda.isEmpty && x > umbralIzquierda
                let derechaDisparada = !derecha.isEmpty && x < -umbralDerecha

                if izquierdaDisparada {
                    // GESTO COMPLETO: se ejecuta la acción del borde izquierdo
                    cerrar()
                    izquierda.first?.accion()
                    pasoUmbralIzquierda = false
                    return
                }
                if derechaDisparada {
                    cerrar()
                    derecha.last?.accion()
                    pasoUmbralDerecha = false
                    return
                }
                pasoUmbralIzquierda = false
                pasoUmbralDerecha = false
                // Si no, se queda abierta con los botones a la vista o vuelve a su sitio
                withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
                    if x > anchoIzquierda / 2 {
                        desplazamiento = anchoIzquierda
                        abierta = true
                    } else if x < -anchoDerecha / 2 {
                        desplazamiento = -anchoDerecha
                        abierta = true
                    } else {
                        desplazamiento = 0
                        abierta = false
                    }
                }
            }
    }

    private func cerrar() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
            desplazamiento = 0
            abierta = false
        }
    }
}

/// Cierra las filas abiertas cuando se desplaza la lista (como en la web)
struct CerrarFilasAlDesplazar: ViewModifier {
    @State private var ultimo: CGFloat?

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ClaveDesplazamiento.self,
                        value: geo.frame(in: .named("listaSwipe")).minY
                    )
                }
            )
            .coordinateSpace(name: "listaSwipe")
            .onPreferenceChange(ClaveDesplazamiento.self) { valor in
                if let anterior = ultimo, abs(valor - anterior) > 8 {
                    FilasAbiertas.compartida.cerrarTodas()
                }
                ultimo = valor
            }
    }
}

private struct ClaveDesplazamiento: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    func cerrarFilasAlDesplazar() -> some View {
        modifier(CerrarFilasAlDesplazar())
    }

    /// Apaga el scroll de la lista mientras un dedo está moviendo una fila de lado
    /* En la web esto lo resuelve `touch-action: pan-y` del propio navegador; SwiftUI no
       tiene equivalente, así que el scroll se apaga a mano mientras dura el gesto. Sin
       esto, al deslizar una fila la lista también se movía. */
    func bloqueaScrollAlDeslizarFila() -> some View {
        modifier(BloqueaScrollAlDeslizarFila())
    }
}

struct BloqueaScrollAlDeslizarFila: ViewModifier {
    @ObservedObject private var filas = FilasAbiertas.compartida

    func body(content: Content) -> some View {
        content.scrollDisabled(filas.arrastrando)
    }
}

/// El contenido de una fila de ubicación (la tarjeta con la franja de la categoría)
struct ContenidoFilaUbicacion: View {
    let ubicacion: Ubicacion
    let categoria: Categoria?
    let etiquetas: [Etiqueta]
    let distancia: CLLocationDistance?
    let mostrarDireccion: Bool
    let mostrarTiempoDistancia: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(categoria.map { Color(hex: $0.color) } ?? Diseno.apagado.opacity(0.4))
                .frame(width: 5)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(ubicacion.name)
                        .font(.disFila)
                        .foregroundColor(Diseno.texto)
                        .lineLimit(1)
                    if ubicacion.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Diseno.naranjaPin)
                    }
                }
                if mostrarDireccion && !ubicacion.address.isEmpty {
                    Text(ubicacion.address)
                        .font(.disSecundario)
                        .foregroundColor(Diseno.apagado)
                        .lineLimit(2)
                }
                if !etiquetas.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(etiquetas) { etiqueta in
                            Pastilla(texto: etiqueta.name, color: Color(hex: etiqueta.color))
                        }
                    }
                }
                if mostrarTiempoDistancia, let metros = distancia {
                    HStack(spacing: 6) {
                        Pastilla(texto: textoDistanciaCorta(metros), color: Diseno.apagado)
                        if let minutos = minutosEstimados(metros) {
                            Pastilla(texto: "\(minutos) min", color: Diseno.verde)
                        }
                    }
                }
            }
            .padding(.vertical, 13)
            .padding(.leading, 13)

            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Diseno.apagado)
                .padding(.trailing, 12)
        }
        .background(Diseno.fondoFila)
    }
}

/// Fila genérica (título + subtítulo + chips): rutas, radares y papelera
struct ContenidoFilaGenerica: View {
    let titulo: String
    var subtitulo: String?
    var icono: String?
    var colorIcono: Color = Diseno.apagado
    var chips: [(String, Color)] = []
    var franja: Color?

    var body: some View {
        HStack(spacing: 0) {
            if let franja = franja {
                Rectangle().fill(franja).frame(width: 5)
            }
            HStack(spacing: 12) {
                if let icono = icono {
                    Image(systemName: icono)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(colorIcono)
                        .frame(width: 26)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(titulo)
                        .font(.disFila)
                        .foregroundColor(Diseno.texto)
                        .lineLimit(2)
                    if let subtitulo = subtitulo, !subtitulo.isEmpty {
                        Text(subtitulo)
                            .font(.disSecundario)
                            .foregroundColor(Diseno.apagado)
                            .lineLimit(2)
                    }
                    if !chips.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                                Pastilla(texto: chip.0, color: chip.1)
                            }
                        }
                    }
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Diseno.apagado)
            }
            .padding(.vertical, 13)
            .padding(.leading, franja == nil ? 14 : 13)
            .padding(.trailing, 12)
        }
        .background(Diseno.fondoFila)
    }
}

func textoDistanciaCorta(_ metros: CLLocationDistance) -> String {
    if metros < 1000 { return "\(Int(metros.rounded())) m" }
    return String(format: "%.1f km", metros / 1000)
}

/// Estimación rápida de coche: la carretera es ~30 % más larga que la línea recta y se
/// va a unos 50 km/h de media (lo mismo que hace la web)
func minutosEstimados(_ metros: CLLocationDistance) -> Int? {
    guard metros > 30 else { return nil }
    let kmCarretera = (metros / 1000) * 1.3
    return max(1, Int((kmCarretera / 50 * 60).rounded()))
}

/* EL AVANCE HACIA UNA PARADA CONCRETA (lo usan la ruta abierta y el «Cambiar destino»).
   Es lo mismo que hace la web: 100 % si la parada ya está hecha o si estás dentro del radio
   de llegada; si no, la parte del tramo que llevas recorrida, midiendo tu posición entre la
   parada ANTERIOR y esta. Así la barra de la parada y el punto del hilo se van moviendo
   mientras avanzas, sin tener que marcar nada a mano. */
func avanceHaciaLaParada(
    indice: Int,
    paradas: [Ubicacion],
    hechas: Set<Int>,
    objetivo: Int?,
    posicion: CLLocation?,
    perfil: String
) -> Double {
    if hechas.contains(indice) { return 1 }
    guard indice == objetivo, let pos = posicion, paradas.indices.contains(indice) else { return 0 }
    let destino = paradas[indice]
    guard destino.tieneCoordenadas else { return 0 }
    let origen: CLLocationCoordinate2D = indice == 0
        ? pos.coordinate
        : (paradas[indice - 1].tieneCoordenadas ? paradas[indice - 1].coordinate : pos.coordinate)
    let hasta = CLLocation(latitude: destino.lat, longitude: destino.lng)
    let desde = CLLocation(latitude: origen.latitude, longitude: origen.longitude)
    let aqui = CLLocation(latitude: pos.coordinate.latitude, longitude: pos.coordinate.longitude)
    let distToB = desde.distance(from: hasta)
    let distToA = desde.distance(from: aqui)
    let meQueda = aqui.distance(from: hasta)
    let radio: Double = perfil == "pie" ? max(6, min(20, pos.horizontalAccuracy)) : 25
    if meQueda <= radio { return 1 }
    /* SÓLO SE PINTA EL AVANCE SI ESTÁS EN EL CAMINO entre las dos paradas.
       ¡Aquí estaba el «me dice que estoy al 73% de Figueres y estoy en Barcelona»!: antes se
       calculaba la fracción aunque estuvieras lejísimos, así que salía un porcentaje sin
       sentido. Si no estás entre la parada anterior y esta, el avance es 0. */
    let caminoRecto = distToA + meQueda
    guard distToB > 20, caminoRecto <= distToB * 1.25 + 50 else { return 0 }
    return min(max(distToA / distToB, 0), 0.99)
}
