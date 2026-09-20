/* CAPTURAR UN RADAR, igual que en la web.

   Lo que hace falta que haga, tal cual lo pediste:
     · AL PULSAR EL BOTÓN SE CONGELA LA POSICIÓN: se coge la de ese instante y ya no
       cambia, aunque sigas andando (en la web lo avisa: «se guardará la posición del
       clic»). Hay un botón para volver a cogerla si quieres.
     · PANELES CON ICONOS Y CUADRÍCULA GRANDE: los tipos van en una cuadrícula de dos
       columnas con su icono y su color, y los límites en una cuadrícula de tres.
     · AL TOCAR EL LÍMITE SE GUARDA Y SE CIERRA SOLO: un toque menos en la carretera.
     · La cámara de infracciones se guarda al tocarla (no es de velocidad) y el FINAL de
       un tramo también (el límite lo marca el inicio).
*/
import SwiftUI
import CoreLocation

struct CapturarRadar: View {
    @ObservedObject var estado: Estado
    var hecho: (String) -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var paso: Paso = .tipos
    @State private var tipo = "fixed"
    @State private var rol: String?
    /// LA POSICIÓN CONGELADA: la del momento de pulsar el botón
    @State private var congelada: CLLocation?
    @State private var guardando = false
    @State private var mensaje: String?
    @State private var fueBien = false

    enum Paso { case tipos, tramo, velocidad }

    private let tipos: [(id: String, etiqueta: String, icono: String, color: Color)] = [
        ("fixed", "Radar fijo", "camera.fill", Color(hex: "#ff453a")),
        ("section", "Radar de tramo", "arrow.left.and.right", Color(hex: "#ff9f0a")),
        ("mobile", "Posible radar móvil", "car.fill", Color(hex: "#0a84ff")),
        ("tunnel", "Radar de túnel", "arrow.up.arrow.down", Color(hex: "#0a84ff")),
        ("redlight", "Radar de semáforo", "light.beacon.max.fill", Color(hex: "#8b5cf6")),
        ("belt", "Cámara de infracciones", "figure.walk.motion", Color(hex: "#ff9f0a")),
    ]

    private let velocidades = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120]

    private var tipoActual: (id: String, etiqueta: String, icono: String, color: Color) {
        tipos.first { $0.id == tipo } ?? tipos[0]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    selloPosicion

                    switch paso {
                    case .tipos: pasoTipos
                    case .tramo: pasoTramo
                    case .velocidad: pasoVelocidad
                    }

                    if let mensaje = mensaje {
                        Text(mensaje)
                            .font(.disSecundario.weight(.semibold))
                            .foregroundColor(fueBien ? Diseno.verde : Diseno.peligro)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)
                    }
                }
                .padding(16)
            }
            .fondoApp()
            .navigationTitle("Capturar radar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { cerrar() }
                        .foregroundColor(Diseno.acento)
                }
            }
            .onAppear {
                // LA POSICIÓN SE CONGELA AQUÍ, al abrir (que es al pulsar el botón)
                if congelada == nil { congelada = estado.posicion }
            }
        }
    }

    // ── El sello con la posición congelada ───────────────────────────────────
    private var selloPosicion: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundColor(Diseno.acento)
                if let pos = congelada {
                    Text(String(format: "%.5f, %.5f · ±%.0f m", pos.coordinate.latitude, pos.coordinate.longitude, pos.horizontalAccuracy))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(Diseno.texto)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("Localizando… (será la del momento del clic)")
                        .font(.disEtiqueta)
                        .foregroundColor(Diseno.naranja)
                }
            }
            Button {
                congelada = estado.posicion
                AvisosFlotantes.compartido.info("Posición vuelta a coger")
            } label: {
                Label("Volver a coger la posición", systemImage: "arrow.clockwise")
                    .font(.disEtiqueta)
                    .foregroundColor(Diseno.acento)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .tarjeta(relleno: 12)
    }

    // ── Paso 1: el tipo, en cuadrícula de dos ────────────────────────────────
    private var pasoTipos: some View {
        VStack(spacing: 12) {
            Text("Al pulsar un tipo se guarda tu posición de ese instante, sin que la app se pare.")
                .font(.disSecundario)
                .foregroundColor(Diseno.apagado)
                .multilineTextAlignment(.center)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(tipos, id: \.id) { opcion in
                    Button {
                        elegirTipo(opcion.id)
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: opcion.icono)
                                .font(.system(size: 38, weight: .semibold))
                                .foregroundColor(opcion.color)
                            Text(opcion.etiqueta)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(Diseno.texto)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 132)
                        .background(opcion.color.opacity(0.12), in: RoundedRectangle(cornerRadius: Diseno.radio))
                        .overlay(RoundedRectangle(cornerRadius: Diseno.radio).stroke(opcion.color.opacity(0.45), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            if guardando { ProgressView().tint(Diseno.acento) }
        }
    }

    // ── Paso 2: inicio o final del tramo ─────────────────────────────────────
    private var pasoTramo: some View {
        VStack(spacing: 12) {
            Text("Radar de tramo: ¿qué punto es?")
                .font(.disSubtitulo)
                .foregroundColor(Diseno.texto)

            HStack(spacing: 12) {
                Button {
                    rol = "inicio"
                    paso = .velocidad
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "flag.fill").font(.system(size: 34)).foregroundColor(Diseno.verde)
                        Text("Inicio del tramo").font(.system(size: 15, weight: .bold)).foregroundColor(Diseno.texto)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
                    .background(Diseno.verde.opacity(0.12), in: RoundedRectangle(cornerRadius: Diseno.radio))
                    .overlay(RoundedRectangle(cornerRadius: Diseno.radio).stroke(Diseno.verde.opacity(0.45)))
                }
                .buttonStyle(.plain)

                Button {
                    // El FINAL no lleva límite: lo marca el inicio del tramo
                    Task { await guardar(tipo: "section", rol: "final", velocidad: nil) }
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "flag.checkered").font(.system(size: 34)).foregroundColor(Diseno.acento)
                        Text("Final del tramo").font(.system(size: 15, weight: .bold)).foregroundColor(Diseno.texto)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
                    .background(Diseno.acento.opacity(0.12), in: RoundedRectangle(cornerRadius: Diseno.radio))
                    .overlay(RoundedRectangle(cornerRadius: Diseno.radio).stroke(Diseno.acento.opacity(0.45)))
                }
                .buttonStyle(.plain)
            }

            BotonApp(titulo: "Volver", icono: "chevron.left", tipo: .fantasma) {
                paso = .tipos
            }
        }
    }

    // ── Paso 3: el límite, en cuadrícula de tres (se guarda al tocar) ────────
    private var pasoVelocidad: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(tipoActual.color).frame(width: 12, height: 12)
                Text("\(tipoActual.etiqueta)\(rol.map { " · \($0)" } ?? ""): ¿qué límite tiene?")
                    .font(.disSubtitulo)
                    .foregroundColor(Diseno.texto)
                    .multilineTextAlignment(.center)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ], spacing: 12) {
                ForEach(velocidades, id: \.self) { velocidad in
                    Button {
                        // SE GUARDA Y SE CIERRA SOLO
                        Task { await guardar(tipo: tipo, rol: rol, velocidad: Double(velocidad)) }
                    } label: {
                        Text("\(velocidad)")
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundColor(Diseno.texto)
                            .frame(maxWidth: .infinity)
                            .frame(height: 76)
                            .background(Diseno.fondoTarjetaAlta, in: RoundedRectangle(cornerRadius: Diseno.radioSm))
                            .overlay(RoundedRectangle(cornerRadius: Diseno.radioSm).stroke(Diseno.lineaFuerte, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(guardando)
                }
            }

            if tipo == "redlight" {
                Button {
                    Task { await guardar(tipo: tipo, rol: rol, velocidad: nil) }
                } label: {
                    Text("Sin límite · avisa solo por el semáforo")
                        .font(.disCuerpo.weight(.semibold))
                        .foregroundColor(Diseno.acento)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Diseno.acento.opacity(0.12), in: RoundedRectangle(cornerRadius: Diseno.radioSm))
                        .overlay(RoundedRectangle(cornerRadius: Diseno.radioSm).stroke(Diseno.acento.opacity(0.4)))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                BotonApp(titulo: "Volver", icono: "chevron.left", tipo: .fantasma, compacto: true) {
                    paso = (rol != nil) ? .tramo : .tipos
                }
                BotonApp(titulo: guardando ? "Guardando…" : "Guardar aquí", icono: "checkmark", compacto: true) {
                    Task { await guardar(tipo: tipo, rol: rol, velocidad: nil) }
                }
            }

            if guardando { ProgressView().tint(Diseno.acento) }
        }
    }

    // ── El flujo, como en la web ─────────────────────────────────────────────
    private func elegirTipo(_ id: String) {
        tipo = id
        rol = nil
        mensaje = nil
        if id == "section" {
            paso = .tramo
            return
        }
        if id == "belt" {
            // La cámara de infracciones no es de velocidad: se guarda del tirón
            Task { await guardar(tipo: id, rol: nil, velocidad: nil) }
            return
        }
        paso = .velocidad
    }

    private func guardar(tipo: String, rol: String?, velocidad: Double?) async {
        guard let pos = congelada else {
            mensaje = "Todavía no tengo tu posición. Espera un momento y vuelve a intentarlo."
            fueBien = false
            return
        }
        guardando = true
        defer { guardando = false }
        /* El sentido de la marcha: así el aviso sólo salta si vas en SU sentido */
        let sentido = estado.rumbo >= 0 ? estado.rumbo : (pos.course >= 0 ? pos.course : -1)
        do {
            let resultado = try await Servidor.capturarRadar(
                type: tipo,
                lat: pos.coordinate.latitude,
                lng: pos.coordinate.longitude,
                speed: velocidad,
                role: rol,
                dir: sentido
            )
            if resultado.ok == true {
                let confirmaciones = resultado.item?.confirmations ?? 0
                let texto = resultado.created == true
                    ? "Guardado: \(tipoTexto(tipo))\(velocidad.map { " · \(Int($0)) km/h" } ?? "")"
                    : "Ya estaba ahí: confirmado (\(confirmaciones) veces)"
                hecho(texto)
                cerrar()
            } else {
                mensaje = resultado.error ?? "No se pudo guardar"
                fueBien = false
            }
        } catch {
            mensaje = "No se pudo guardar: \(error.localizedDescription)"
            fueBien = false
        }
    }
}
