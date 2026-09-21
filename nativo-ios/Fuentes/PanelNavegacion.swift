/* LA NAVEGACIÓN COMO APPLE MAPS (imágenes 9 y 10).

   · ARRIBA, la INSTRUCCIÓN del próximo giro: la barra negra redondeada con la flechita,
     lo que tienes que hacer y por qué calle (con su placa de carretera).
   · ABAJO, la barra con Llegada · min · km y el GUION: tirando de él HACIA ARRIBA con el
     dedo sale el menú, que es justo lo que hace Apple Maps (imagen 10).
   · El MENÚ es un panel del sistema de paneles (PanelDeMapa.swift): mismo fondo, misma
     esquina, mismo gesto y su «Finalizar» rojo, como el de Apple.

   LAS MEDIDAS son las de los pantallazos (medidas con scripts/medir-pantallazos.mjs):
     · la instrucción: banda de 30 px → 26 pt en negrita muy gruesa;
     · las cifras de abajo: 26 pt con la etiqueta de 15 pt (medido en la imagen 10);
     · el guion: 50 × 5 pt;
     · las filas del menú: 48 pt de paso.
*/
import SwiftUI
import CoreLocation

// ── La instrucción de arriba (la del próximo giro) ─────────────────────────────
struct BarraDeInstruccion: View {
    @ObservedObject var estado: Estado

    /// El paso que toca ahora: se busca por la distancia que llevas hecha del recorrido
    private var pasoActual: Paso? {
        guard let pasos = estado.rutaElegida?.pasos, !pasos.isEmpty else { return nil }
        // Distancia que llevas desde la salida (en línea recta, que para esto sobra)
        var recorrido: Double = 0
        if let primera = estado.paradas.first(where: { $0.tieneCoordenadas }),
           let pos = estado.posicion {
            recorrido = CLLocation(latitude: primera.lat, longitude: primera.lng)
                .distance(from: pos) / 1000
        }
        // El primer paso cuya distancia acumulada todavía no has pasado
        var acumulado: Double = 0
        for paso in pasos {
            acumulado += paso.distKm
            if acumulado >= recorrido { return paso }
        }
        return pasos.last
    }

    var body: some View {
        /* EL PASO SE CALCULA UNA VEZ POR REPINTADO: antes se llamaba tres veces (en el
           icono, en el texto y en la distancia) y cada llamada recorría todos los pasos de
           la ruta creando un `CLLocation`; y esto se repinta con cada aviso del GPS. */
        let paso = pasoActual
        HStack(spacing: 14) {
            Image(systemName: icono(paso?.instruccion ?? ""))
                .font(.system(size: 30, weight: .heavy))
                .foregroundColor(.white)
                .frame(width: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text("Siguiente")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                Text(paso?.instruccion ?? "Sigue recto")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let km = paso?.distKm {
                Text(km < 0.05 ? "Ahora" : textoDistancia(km))
                    .font(.system(size: Medida.numero, weight: .heavy))
                    .foregroundColor(Diseno.acento)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Diseno.panelDelMapa.opacity(0.94), in: RoundedRectangle(cornerRadius: Medida.radioPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Medida.radioPanel, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }

    private func icono(_ texto: String) -> String {
        let dicho = texto.lowercased()
        if dicho.contains("rotonda") { return "arrow.triangle.turn.up.right.circle.fill" }
        if dicho.contains("izquierda") { return "arrow.turn.up.left" }
        if dicho.contains("derecha") { return "arrow.turn.up.right" }
        if dicho.contains("cambio de sentido") { return "arrow.uturn.up" }
        if dicho.contains("incorp") { return "arrow.merge" }
        if dicho.contains("salida") || dicho.contains("desv") { return "arrow.up.right" }
        if dicho.contains("llega") || dicho.contains("destino") { return "flag.checkered" }
        return "arrow.up"
    }
}

// ── LA BARRA DE ABAJO DURANTE LA NAVEGACIÓN (la de Apple Maps) ─────────────────
/* Redondeada, con el guion arriba: Llegada · min · km.
   TIRANDO DEL GUION HACIA ARRIBA sale el menú (imagen 10); tocándola, también.
   El botón de la voz está en el menú. */
struct BarraDeNavegacion: View {
    @ObservedObject var estado: Estado
    var abrirMenu: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            GuionDePanel()
            HStack(spacing: 0) {
                CifraConEtiqueta(valor: horaDeLlegada, etiqueta: "Llegada")
                CifraConEtiqueta(valor: "\(Int(estado.rutaElegida?.durationMins ?? 0))", etiqueta: "min")
                CifraConEtiqueta(valor: String(format: "%.0f", estado.rutaElegida?.distKm ?? 0), etiqueta: "km")
            }
        }
        .padding(.top, 9)
        .padding(.bottom, 12)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(Diseno.panelDelMapa.opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { abrirMenu() }
        // EL GESTO HACIA ARRIBA DEL GUION: el menú, como en Apple Maps
        .arrastrarHaciaArriba { abrirMenu() }
        .accessibilityHint("Tira hacia arriba para ver el menú")
    }

    private var horaDeLlegada: String {
        let minutos = estado.rutaElegida?.durationMins ?? 0
        return Hora.corta(Date().addingTimeInterval(minutos * 60))
    }
}

// ── El MENÚ que sale tirando de la barra hacia arriba (imagen 10) ──────────────
struct PanelDeNavegacion: View {
    @ObservedObject var estado: Estado
    @ObservedObject var almacen: Almacen
    var anadirParada: () -> Void
    var compartir: (String) -> Void
    var abrirAjustesDeVoz: () -> Void
    var cerrar: () -> Void

    @AppStorage("vozActivada") private var vozActivada = true
    @AppStorage("avisosRadares") private var avisosRadares = true
    @AppStorage("capturarRadaresSiempre") private var capturarSiempre = false
    @State private var informando = false
    @State private var textoInforme = ""

    /// LAS FILAS QUE LLEVA EL MENÚ (para que la hoja mida lo que tiene que medir):
    /// el destino + las siete de debajo = 8. La cuenta es la del sistema de paneles
    /// (182 + filas × 48), la misma que da los 519 pt de la hoja de la imagen 10.
    private var cuantasFilas: Int { 8 }

    var body: some View {
        PanelDeMapa(alto: AltoDePanel.menuNavegacion(filas: cuantasFilas)) {
            VStack(spacing: 14) {
                // Lo que llevas: llegada, minutos y km (como la cabecera de la imagen 10)
                HStack(spacing: 0) {
                    CifraConEtiqueta(valor: horaDeLlegada, etiqueta: "Llegada")
                    CifraConEtiqueta(valor: "\(Int(estado.rutaElegida?.durationMins ?? 0))", etiqueta: "min")
                    CifraConEtiqueta(valor: String(format: "%.0f", estado.rutaElegida?.distKm ?? 0), etiqueta: "km")
                }
                .padding(.horizontal, 8)

                VStack(spacing: 0) {
                    // El destino (con las paradas que queden)
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Diseno.peligro)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(estado.destino?.name ?? "Destino")
                                .font(.system(size: Medida.fila))
                                .foregroundColor(Diseno.texto)
                                .lineLimit(1)
                            if estado.paradas.count > 1 {
                                Text("\(estado.paradas.count) paradas")
                                    .font(.system(size: Medida.etiqueta))
                                    .foregroundColor(Diseno.apagado)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Medida.lado)
                    .frame(minHeight: 56)

                    SeparadorDePanel()

                    fila(icono: "plus.circle.fill", color: Diseno.acento, titulo: "Añadir parada") {
                        anadirParada()
                    }
                    SeparadorDePanel(sangria: 56)

                    fila(icono: "person.2.fill", color: Diseno.verde, titulo: "Compartir llegada") {
                        compartir("Voy a \(estado.destino?.name ?? "mi destino") y llego a las \(horaDeLlegada).")
                    }
                    SeparadorDePanel(sangria: 56)

                    fila(icono: "exclamationmark.bubble.fill", color: Diseno.peligro, titulo: "Informar de una incidencia") {
                        informando = true
                    }
                    SeparadorDePanel(sangria: 56)

                    fila(
                        icono: vozActivada ? "speaker.wave.2.fill" : "speaker.slash.fill",
                        color: Diseno.azul,
                        titulo: vozActivada ? "Silenciar la voz" : "Activar la voz"
                    ) {
                        vozActivada.toggle()
                    }
                    SeparadorDePanel(sangria: 56)

                    fila(icono: "wrench.and.screwdriver.fill", color: Diseno.apagado, titulo: "Opciones de la voz") {
                        abrirAjustesDeVoz()
                    }
                    SeparadorDePanel(sangria: 56)

                    fila(
                        icono: avisosRadares ? "camera.fill" : "camera",
                        color: Diseno.acento,
                        titulo: avisosRadares ? "Desactivar los avisos de radares" : "Activar los avisos de radares"
                    ) {
                        avisosRadares.toggle()
                    }
                    SeparadorDePanel(sangria: 56)

                    // El botón de capturar radares, a la vista o escondido (Ajustes)
                    fila(
                        icono: "camera.badge.ellipsis",
                        color: Diseno.acento,
                        titulo: capturarSiempre ? "Ocultar el botón de capturar" : "Botón de capturar a la vista"
                    ) {
                        capturarSiempre.toggle()
                    }
                }
                .background(Diseno.panelDentro, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, Medida.lado)

                // EL BOTÓN DE TERMINAR, como el «Finalizar» rojo de Apple Maps
                Button {
                    estado.salirDeNavegacion()
                    cerrar()
                } label: {
                    Text("Finalizar")
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Diseno.peligro, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Medida.lado)
            }
            .padding(.top, 2)
            .padding(.bottom, 24)
        }
        .alert("Informar de una incidencia", isPresented: $informando) {
            TextField("¿Qué pasa? (atasco, obra, radar…)", text: $textoInforme)
            Button("Cancelar", role: .cancel) { textoInforme = "" }
            Button("Enviar") {
                let informe = textoInforme
                textoInforme = ""
                AvisosFlotantes.compartido.info("Aviso enviado: \(informe)")
            }
        } message: {
            Text("Se avisará a los demás usuarios de esta zona.")
        }
    }

    private var horaDeLlegada: String {
        let minutos = estado.rutaElegida?.durationMins ?? 0
        return Hora.corta(Date().addingTimeInterval(minutos * 60))
    }

    private func fila(icono: String, color: Color, titulo: String, accion: @escaping () -> Void) -> some View {
        FilaDePanel(icono: icono, color: color, titulo: titulo, accion: accion)
    }
}
