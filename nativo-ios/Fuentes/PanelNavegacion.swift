/* TANDA C · LA NAVEGACIÓN COMO APPLE MAPS

   · ARRIBA, la INSTRUCCIÓN del próximo giro (imagen 7): una barra negra redondeada con la
     flechita del giro, lo que tienes que hacer y por qué calle.
   · ABAJO, el panel redondeado con lo que llevas.
   · Y DESLIZANDO EL PANEL HACIA ARRIBA, el menú de la imagen 8: añadir parada, compartir la
     llegada, informar de una incidencia y las opciones de la voz (más cosas prácticas). */
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
        HStack(spacing: 14) {
            Image(systemName: icono(pasoActual?.instruccion ?? ""))
                .font(.system(size: 28, weight: .heavy))
                .foregroundColor(.white)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Siguiente")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.65))
                Text(pasoActual?.instruccion ?? "Sigue recto")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let km = pasoActual?.distKm {
                Text(km < 0.05 ? "Ahora" : textoDistancia(km))
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(Diseno.acento)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.10), lineWidth: 0.5))
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

// ── El menú que sale deslizando el panel hacia arriba (imagen 8) ───────────────
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

    var body: some View {
        VStack(spacing: 12) {
            // Lo que llevas: llegada, minutos y km
            HStack(spacing: 26) {
                dato(titulo: "Llegada", valor: horaDeLlegada)
                dato(titulo: "min", valor: "\(Int(estado.rutaElegida?.durationMins ?? 0))")
                dato(titulo: "km", valor: String(format: "%.0f", estado.rutaElegida?.distKm ?? 0))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)

            VStack(spacing: 0) {
                // El destino (con las paradas que queden)
                HStack(spacing: 12) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Diseno.peligro)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(estado.destino?.name ?? "Destino")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(Diseno.texto)
                            .lineLimit(1)
                        if estado.paradas.count > 1 {
                            Text("\(estado.paradas.count) paradas")
                                .font(.disEtiqueta)
                                .foregroundColor(Diseno.apagado)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 18)

                Divider().overlay(Color.white.opacity(0.08))

                fila(icono: "plus.circle.fill", color: Diseno.acento, titulo: "Añadir parada") {
                    anadirParada()
                }
                Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 56)

                fila(icono: "person.2.fill", color: Diseno.verde, titulo: "Compartir llegada") {
                    compartir("Voy a \(estado.destino?.name ?? "mi destino") y llego a las \(horaDeLlegada).")
                }
                Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 56)

                fila(icono: "exclamationmark.bubble.fill", color: Diseno.peligro, titulo: "Informar de una incidencia") {
                    informando = true
                }
                Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 56)

                fila(
                    icono: vozActivada ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    color: Diseno.azul,
                    titulo: vozActivada ? "Silenciar la voz" : "Activar la voz"
                ) {
                    vozActivada.toggle()
                }
                Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 56)

                fila(icono: "wrench.and.screwdriver.fill", color: Diseno.apagado, titulo: "Opciones de la voz") {
                    abrirAjustesDeVoz()
                }
                Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 56)

                fila(
                    icono: avisosRadares ? "camera.fill" : "camera",
                    color: Diseno.acento,
                    titulo: avisosRadares ? "Desactivar los avisos de radares" : "Activar los avisos de radares"
                ) {
                    avisosRadares.toggle()
                }
                Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 56)

                fila(
                    icono: capturarSiempre ? "camera.badge.ellipsis" : "camera.badge.ellipsis",
                    color: Diseno.acento,
                    titulo: capturarSiempre ? "Ocultar el botón de capturar" : "Botón de capturar a la vista"
                ) {
                    capturarSiempre.toggle()
                }
            }
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 14)

            // El botón de terminar, como el «Finalizar» de Apple Maps
            Button {
                Task {
                    await estado.salirDeNavegacion()
                    cerrar()
                }
            } label: {
                Text("Finalizar")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Diseno.peligro, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .padding(.top, 6)
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
        let formato = DateFormatter()
        formato.dateFormat = "HH:mm"
        return formato.string(from: Date().addingTimeInterval(minutos * 60))
    }

    private func dato(titulo: String, valor: String) -> some View {
        VStack(spacing: 0) {
            Text(valor)
                .font(.system(size: 26, weight: .heavy))
                .foregroundColor(Diseno.texto)
            Text(titulo)
                .font(.system(size: 14))
                .foregroundColor(Diseno.apagado)
        }
    }

    private func fila(icono: String, color: Color, titulo: String, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            HStack(spacing: 14) {
                Image(systemName: icono)
                    .font(.system(size: 20))
                    .foregroundColor(color)
                    .frame(width: 28)
                Text(titulo)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Diseno.texto)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 15)
            .padding(.horizontal, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// ── LA BARRA DE ABAJO DURANTE LA NAVEGACIÓN (la de Apple Maps) ─────────────────
/* Redondeada, con el guion arriba: Llegada · min · km, y a la derecha el botón para
   subir el menú. Tocando el guion (o el botón) sale el menú de navegación. */
struct BarraDeNavegacion: View {
    @ObservedObject var estado: Estado
    var abrirMenu: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color.white.opacity(0.35))
                .frame(width: 44, height: 5)

            HStack(spacing: 0) {
                dato(titulo: "Llegada", valor: horaDeLlegada)
                dato(titulo: "min", valor: "\(Int(estado.rutaElegida?.durationMins ?? 0))")
                dato(titulo: "km", valor: String(format: "%.0f", estado.rutaElegida?.distKm ?? 0))

            }
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 22))
        .contentShape(Rectangle())
        .onTapGesture { abrirMenu() }
    }

    private var horaDeLlegada: String {
        let minutos = estado.rutaElegida?.durationMins ?? 0
        let formato = DateFormatter()
        formato.dateFormat = "HH:mm"
        return formato.string(from: Date().addingTimeInterval(minutos * 60))
    }

    private func dato(titulo: String, valor: String) -> some View {
        VStack(spacing: 0) {
            Text(valor)
                .font(.system(size: 26, weight: .heavy))
                .foregroundColor(Diseno.texto)
            Text(titulo)
                .font(.system(size: 14))
                .foregroundColor(Diseno.apagado)
        }
        .frame(maxWidth: .infinity)
    }
}