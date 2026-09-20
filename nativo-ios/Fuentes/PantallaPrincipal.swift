/* LA APP: cuatro pestañas, como la web pero todo nativo.

   · Mapa     -> el mapa, la navegación y los avisos de radar
   · Ubicaciones -> tu lista (buscar, ordenar, filtrar por categoría, ficha, añadir, borrar)
   · Rutas    -> las rutas guardadas con sus paradas
   · Ajustes  -> tema, categorías, etiquetas, papelera y estado de la sincronización
*/
import SwiftUI
import CoreLocation

struct PantallaPrincipal: View {
    @StateObject private var estado = Estado()
    @StateObject private var almacen = Almacen()
    @ObservedObject private var avisos = AvisosFlotantes.compartido
    /* LA PESTAÑA SE RECUERDA: si cierras la app en Rutas, al volver sigues en Rutas (antes
       siempre volvía al Mapa). Va en UserDefaults, así que sobrevive al cierre. */
    @AppStorage("pestanaElegida") private var pestana = 0
    /// Tamaño de letra elegido en Ajustes (0 = el del sistema)
    @AppStorage("tamanoLetra") private var tamanoLetra = 1
    /// Para saber cuándo la app se va al fondo (y guardar la sesión)
    @Environment(\.scenePhase) private var fase
    /// El botón de capturar radar, en TODAS las pantallas si está activado en Ajustes
    @State private var capturandoGlobal = false
    @AppStorage("capturarRadaresSiempre") private var capturarSiempreGlobal = false
    @AppStorage("avisosRadares") private var avisosRadaresGlobal = true

    private var tamanoDinamico: DynamicTypeSize {
        switch tamanoLetra {
        case 0: return .large
        case 1: return .xLarge
        case 2: return .xxLarge
        case 3: return .xxxLarge
        default: return .xLarge
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(spacing: 0) {
                // La pantalla de la pestaña elegida (ocupa todo menos la barra)
                Group {
                    switch pestana {
                    case 0:
                        PantallaMapa(estado: estado, almacen: almacen, irALista: { pestana = 1 })
                    case 1:
                        PantallaUbicaciones(estado: estado, almacen: almacen, irAlMapa: { pestana = 0 })
                    case 2:
                        PantallaRutas(estado: estado, almacen: almacen, irAlMapa: { pestana = 0 })
                    case 3:
                        PantallaRadares(estado: estado, almacen: almacen, irAlMapa: { pestana = 0 })
                    default:
                        PantallaAjustes(almacen: almacen, estado: estado, irAlMapa: { pestana = 0 })
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // La barra de pestañas, con el diseño de la web
                BarraPestanas(seleccion: $pestana)
            }

            /* EL BOTÓN DE CAPTURAR RADAR: en las pestañas que NO son el mapa va flotando aquí
               (encima de la barra de pestañas). En el mapa va en su fila de botones del panel,
               porque si no TAPA los botones de abajo (se veía en la captura). */
            if capturarSiempreGlobal && avisosRadaresGlobal && pestana != 0 {
                FabDorado(icono: "camera.fill") { capturandoGlobal = true }
                    .padding(.leading, 18)
                    .padding(.bottom, 104)
            }
        }
        .background(FondoMidnight())
        .environment(\.dynamicTypeSize, tamanoDinamico)
        .overlay(AvisoFlotanteVista(avisos: avisos))
        .sheet(isPresented: $capturandoGlobal) {
            CapturarRadar(estado: estado) { texto in
                AvisosFlotantes.compartido.bien(texto)
            }
        }
        .task {
            // Los datos se cargan una vez al abrir; luego se guardan solos al editar
            await almacen.cargar()
            if almacen.fallo == nil {
                AvisosFlotantes.compartido.info("\(almacen.ubicaciones.count) ubicaciones cargadas")
            }
            /* PRIMERA VEZ DESPUÉS DE INSTALAR O ACTUALIZAR: los ajustes y el viaje se
               recuperan del respaldo del servidor (el mismo documento de las ubicaciones).
               Así, aunque el iPhone se lleve por delante los datos de la app, todo sigue
               como lo tenías. */
            let primeraVez = almacen.esPrimeraVez
            if primeraVez {
                almacen.restaurarAjustesDelRespaldo()
                almacen.esPrimeraVez = false
            }
            /* Y SE RECUPERA LA SESIÓN: el viaje que llevabas, qué paradas estaban hechas y
               si ibas navegando. Si es la primera vez, se toma del servidor. */
            await estado.restaurarSesion(
                con: almacen,
                datos: primeraVez && !almacen.viajeDelRespaldo.isEmpty ? almacen.viajeDelRespaldo : nil
            )
        }
        .onChange(of: fase) { nueva in
            // Al salir de la app se guarda todo, en el móvil y en el servidor
            if nueva != .active {
                estado.guardarSesion()
                Task { await almacen.guardarRespaldo(ajustes: Almacen.ajustesLocales(), viaje: estado.viajeComoDiccionario) }
            }
        }
        .onChange(of: pestana) { _ in estado.guardarSesion() }
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// PESTAÑA MAPA
// ══════════════════════════════════════════════════════════════════════════════
struct PantallaMapa: View {
    @ObservedObject var estado: Estado
    @ObservedObject var almacen: Almacen
    var irALista: () -> Void
    @StateObject private var controlador = ControladorMapa()
    /// LA HOJA QUE ESTÁ ABIERTA (una sola: SwiftUI no admite más de una)
    @State private var hoja: HojaDeMapa?
    @State private var ficha: Ubicacion?
    @State private var editor: Ubicacion?
    @State private var capturando = false
    /// El radar cuya alerta ha cerrado el usuario (no se le vuelve a abrir)
    @State private var alertaCerrada: String?
    /// El botón de capturar, siempre a la vista si está activado en Ajustes
    @AppStorage("capturarRadaresSiempre") private var capturarSiempre = false
    @AppStorage("avisosRadares") private var avisosRadares = true
    /* LAS CAPAS DEL MAPA: qué quieres ver encima y de qué color va la ruta. Se guardan, así
       que siguen puestas la próxima vez (y el color de ruta también). */
    @AppStorage("mapaUbicaciones") private var verUbicaciones = true
    @AppStorage("mapaRadares") private var verRadares = true
    @AppStorage("mapaPuntosInteres") private var verPuntosInteres = false
    @AppStorage("mapaTrafico") private var verTrafico = false
    @AppStorage("mapaEdificios") private var verEdificios = false
    @AppStorage("mapaApagado") private var mapaApagado = false
    @AppStorage("mapaSatelite") private var mapaSatelite = false
    @AppStorage("colorRuta") private var colorRuta = "#d4a843"
    /// EVITAR PEAJES: las rutas se calculan sin peajes
    @AppStorage("evitarPeajes") private var evitarPeajes = false
    /// ¿Está abierto el panel de capas?
    @State private var capasAbiertas = false
    /// ¿Está el mapa inclinado (3D)? El botón pasa a decir 2D
    @AppStorage("mapa3D") private var mapa3D = false


    private var capas: ControladorMapa.Capas {
        ControladorMapa.Capas(
            ubicaciones: verUbicaciones,
            radares: verRadares,
            puntosInteres: verPuntosInteres,
            trafico: verTrafico,
            edificios: verEdificios,
            mapaApagado: mapaApagado,
            satelite: mapaSatelite,
            colorRuta: colorRuta
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            MapaView(
                estado: estado,
                controlador: controlador,
                ubicaciones: almacen.ubicaciones,
                capas: capas,
                colorDeCategoria: { id in
                    let (r, g, b) = colorDeHex(almacen.categoria(id)?.color ?? "#94a1b3")
                    return UIColor(red: r, green: g, blue: b, alpha: 1)
                }
            )
            .ignoresSafeArea()

            VStack(spacing: 8) {
                /* ARRIBA SÓLO LA INSTRUCCIÓN DE LA RUTA (imagen 7): el panel viejo de
                   «34 min / 0 km/h / chips / barra de progreso» ya no existe (sobraba). */
                if estado.navegando {
                    BarraDeInstruccion(estado: estado)
                }
                if let fallo = estado.fallo {
                    Text(fallo)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.black.opacity(0.7), in: Capsule())
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            /* EL AVISO DE RADAR: el cartel CENTRADO de la web, con su capa oscura detrás.
               Va el último del ZStack para que tape el mapa, los paneles y los botones
               (en la web es un modal con `z-index: 9000`). */
            if let radar = radarAvisando, alertaCerrada != radar.id {
                AlertaRadar(radar: radar, estado: estado) {
                    alertaCerrada = radar.id
                }
                .zIndex(9)
            }

            // ── Los botones del mapa, como Apple Maps (abajo a la derecha) ───
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    // El botón de CAPTURAR RADAR, a la izquierda si lo tienes activado
                    if capturarSiempre && avisosRadares {
                        FabDorado(icono: "camera.fill") { hoja = .radar }
                    }
                    Spacer()
                    /* LA COLUMNA DE APPLE MAPS, de arriba abajo:
                         3D/2D   -> inclina el mapa un 30 % (y el botón pasa a decir 2D)
                         coche   -> los MODOS DE MAPA (Explorar / En coche / Satélite…)
                         centrar -> vuelve a tu posición (sale cuando te has ido)        */
                    VStack(alignment: .trailing, spacing: 10) {
                        /* LA BRÚJULA, ENCIMA DEL 3D (la de toda la vida: gira con el mapa y
                           al tocarla vuelve al norte) */
                        Brujula(controlador: controlador)
                        BotonRedondo(
                            icono: "cube.transparent",
                            color: mapa3D ? Diseno.acento : Diseno.texto,
                            texto: mapa3D ? "2D" : "3D"
                        ) {
                            mapa3D.toggle()
                            controlador.mapa3DActivo = mapa3D
                            controlador.inclinacion3D = mapa3D ? 60 : 0
                            controlador.forzarCamara = true
                        }
                        BotonRedondo(icono: "car.fill", color: Diseno.texto) {
                            withAnimation(.easeOut(duration: 0.18)) { capasAbiertas.toggle() }
                        }
                        if !controlador.siguiendo {
                            BotonRedondo(icono: "location.fill", color: Diseno.acento) {
                                controlador.volverAlTamanoQueToca(navegando: estado.navegando)
                            }
                        }
                    }
                    .padding(.trailing, 14)
                    .padding(.bottom, 10)
                }
            if capasAbiertas {
                    panelDeCapas
                        .padding(.bottom, 8)
                }
                /* ABAJO, como Apple Maps: la BARRA DE BÚSQUEDA («Ubicaciones») siempre a la
                   vista —sin destino es la de abajo del todo y con destino va encima del
                   panel de la ruta—, y debajo el panel de la ruta si hay destino. */
                /* AL NAVEGAR, abajo va el panel de Apple Maps: Llegada · min · km y el guion
                   para subir el menú. SIN navegar, la barra de búsqueda y el panel de siempre. */
                if estado.navegando {
                    BarraDeNavegacion(estado: estado) {
                        hoja = .menu
                    }
                } else if estado.destino != nil {
                    /* CON DESTINO, ABAJO SE QUEDA EL PANEL DE «CÓMO LLEGAR» (imagen 1): la
                       barra de buscar DESAPARECE y aquí salen las rutas con su botón IR.
                       La X de arriba limpia la ruta (como en Apple Maps). */
                    PanelComoLlegar(estado: estado) { estado.limpiarViaje() }
                        .frame(maxHeight: 420)
                } else {
                    // SIN DESTINO: sólo la barra de buscar, como Apple Maps
                    barraDeBusqueda
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)

        }
        /* EL PANEL DE UBICACIONES, con el PANEL NATIVO DE iOS (el mismo que usan las apps
           de Apple): así va a los fps del sistema, sube y baja siguiendo al dedo, se puede
           estirar a dos tamaños (mediano y grande) y se cierra deslizando hacia abajo.
           El fondo es NEGRO TRANSPARENTE SIN DIFUMINADO NI SOMBRA: se ve el mapa por detrás. */
        /* UNA SOLA HOJA PARA TODO. SwiftUI SÓLO ADMITE UNA HOJA POR VISTA: con cinco
           encadenadas, unas no se abrían (por eso al tocar una ubicación no salía «Cómo
           llegar») y la app se quedaba pillada. Ahora hay una sola y se elige por caso. */
        .sheet(item: $hoja) { cual in
            switch cual {
            case .ubicaciones:
                PanelUbicaciones(estado: estado, almacen: almacen) { hoja = nil }
                    .presentationDetents([.height(430), .large])
                    .presentationDragIndicator(.visible)
                    .fondoDelPanelNativo()
            case .comoLlegar:
                PanelComoLlegar(estado: estado) { hoja = nil }
                    .presentationDetents([.height(460), .large])
                    .presentationDragIndicator(.visible)
                    .fondoDelPanelNativo()
            case .menu:
                PanelDeNavegacion(
                    estado: estado,
                    almacen: almacen,
                    anadirParada: { hoja = .elegirDestino },
                    compartir: { texto in
                        UIPasteboard.general.string = texto
                        AvisosFlotantes.compartido.bien("Copiado para compartir")
                    },
                    abrirAjustesDeVoz: { hoja = nil },
                    cerrar: { hoja = nil }
                )
                .presentationDetents([.height(520), .large])
                .presentationDragIndicator(.visible)
                .fondoDelPanelNativo()
            case .radar:
                CapturarRadar(estado: estado) { texto in
                    AvisosFlotantes.compartido.bien(texto)
                }
            case .elegirDestino:
                ElegirDestino(estado: estado, almacen: almacen, cerrar: { hoja = nil })
            case .ficha(let ubicacion):
                FichaUbicacion(
                    estado: estado,
                    almacen: almacen,
                    ubicacion: ubicacion,
                    irAlMapa: {},
                    editar: { actual in hoja = .editor(actual) }
                )
            case .editor(let ubicacion):
                EditorUbicacion(almacen: almacen, original: ubicacion, cerrar: { hoja = nil })
            }
        }
        /* AL ELEGIR UN DESTINO se abre solo «Cómo llegar» con sus rutas */
        .onChange(of: estado.destino?.id) { nuevo in
            if nuevo != nil, !estado.navegando { hoja = .comoLlegar }
        }
        .onChange(of: estado.radarAvisando) { nuevo in
            // Al cambiar de radar, la alerta vuelve a salir
            if nuevo != alertaCerrada { alertaCerrada = nil }
        }
    }

    private var radarAvisando: Radar? {
        guard let id = estado.radarAvisando else { return nil }
        return estado.radares.first(where: { $0.id == id })
    }
    /// Un botón ancho de la fila de abajo (Cómo llegar / Limpiar)
    private func botonDeAbajo(_ titulo: String, icono: String, color: Color, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            HStack(spacing: 8) {
                Image(systemName: icono).font(.system(size: 17, weight: .bold))
                Text(titulo).font(.system(size: 17, weight: .bold))
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    /// LA BARRA DE BÚSQUEDA DE ABAJO (el «Mapas de Apple» de Apple Maps, aquí «Ubicaciones»)
    private var barraDeBusqueda: some View {
        Button {
            withAnimation(.easeOut(duration: 0.24)) { hoja = .ubicaciones }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(Diseno.texto)
                Text("Ubicaciones")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(Diseno.texto.opacity(0.75))
                Spacer(minLength: 0)
                Image(systemName: "mic.fill")
                    .font(.system(size: 19))
                    .foregroundColor(Diseno.texto)
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            /* NEGRO TRANSPARENTE, SIN DIFUMINADO NI SOMBRA: se ve el mapa por detrás */
            // UN POQUITO de blur y negro suave: se ve el mapa por detrás
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(Color.black.opacity(0.25))
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// El panel de CAPAS del mapa: ubicaciones, radares y puntos de interés
    private var panelDeCapas: some View {
        VStack(spacing: 0) {
            filaDeCapa("Ubicaciones", icono: "mappin.and.ellipse", activo: verUbicaciones) {
                verUbicaciones.toggle()
            }
            Divider().overlay(Diseno.linea)
            filaDeCapa("Radares", icono: "camera.fill", activo: verRadares) {
                verRadares.toggle()
            }
            Divider().overlay(Diseno.linea)
            filaDeCapa("Puntos de interés", icono: "fork.knife", activo: verPuntosInteres) {
                verPuntosInteres.toggle()
            }
            Divider().overlay(Diseno.linea)
            filaDeCapa("Tráfico", icono: "car.2.fill", activo: verTrafico) { verTrafico.toggle() }
            Divider().overlay(Diseno.linea)
            filaDeCapa("Edificios en 3D", icono: "building.2.fill", activo: verEdificios) { verEdificios.toggle() }
            Divider().overlay(Diseno.linea)
            filaDeCapa("Mapa apagado (resalta la ruta)", icono: "circle.lefthalf.filled", activo: mapaApagado) { mapaApagado.toggle() }
            Divider().overlay(Diseno.linea)
            filaDeCapa("Satélite", icono: "globe.europe.africa.fill", activo: mapaSatelite) { mapaSatelite.toggle() }
            Divider().overlay(Diseno.linea)
            /* EVITAR PEAJES: al activarlo, las rutas se vuelven a calcular sin autopistas de
               peaje (el servidor se lo pide a OSRM con `exclude=toll`). */
            filaDeCapa("Evitar peajes", icono: "eurosign.circle", activo: evitarPeajes) {
                evitarPeajes.toggle()
                Task { await estado.recalcularRuta() }
            }
        }
        .background(Diseno.fondoFila, in: RoundedRectangle(cornerRadius: Diseno.radio))
        .overlay(RoundedRectangle(cornerRadius: Diseno.radio).stroke(Diseno.lineaFuerte, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
    }

    private func filaDeCapa(_ titulo: String, icono: String, activo: Bool, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            HStack(spacing: 10) {
                Image(systemName: icono)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(activo ? Diseno.acento : Diseno.apagado)
                    .frame(width: 24)
                Text(titulo)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Diseno.texto)
                Spacer(minLength: 12)
                Image(systemName: activo ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundColor(activo ? Diseno.verde : Diseno.apagado)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }


}

// ── El panel de arriba: viaje + velocidad + progreso ──────────────────────────
struct PanelArriba: View {
    /// Abrir el panel de «Cómo llegar» (una fila por ruta) al tocar este panel
    var abrirComoLlegar: () -> Void = {}
    @ObservedObject var estado: Estado

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    // Tiempo que queda y km que quedan (de la ruta elegida)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(textoDuracion(estado.rutaElegida?.durationMins ?? 0))
                            .font(.disNumero)
                            .foregroundColor(Diseno.texto)
                        Text(textoDistancia(estado.quedaKm ?? estado.rutaElegida?.distKm ?? 0))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Diseno.apagado)
                    }

                    // Hora de llegada + estado del tráfico (Fluido / Moderado / Atascado)
                    HStack(spacing: 7) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Diseno.apagado)
                        Text(estado.horaLlegada.map { horaTexto($0) } ?? "—:—")
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundColor(Diseno.texto)
                        Pastilla(
                            texto: Diseno.textoTrafico(estado.trafico?.status, retrasoMin: estado.trafico?.delayMin),
                            color: Diseno.colorTrafico(estado.trafico?.status)
                        )
                    }

                    Text(estado.destino?.name ?? "")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Diseno.apagado)
                        .lineLimit(1)

                    if estado.rutas.count > 1 {
                        HStack(spacing: 6) {
                            ForEach(Array(estado.rutas.enumerated()), id: \.offset) { indice, ruta in
                                Button {
                                    estado.elegida = indice
                                } label: {
                                    Text("\(textoDuracion(ruta.durationMins)) · \(textoDistancia(ruta.distKm))")
                                        .font(.disEtiqueta)
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 6)
                                        .background(
                                            indice == estado.elegida ? Diseno.acento : Color.white.opacity(0.12),
                                            in: Capsule()
                                        )
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
                Velocidad(estado: estado)
            }
            // TOCAR el panel de la ruta abre «Cómo llegar» (una fila por ruta, con su IR)
            .contentShape(Rectangle())
            .onTapGesture { abrirComoLlegar() }

            // BARRA DE PROGRESO: sólo la barra, como en la web (sin números)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(LinearGradient(colors: [Diseno.verde, Diseno.acento], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, geo.size.width * estado.progreso))
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: Diseno.radio))
        .overlay(RoundedRectangle(cornerRadius: Diseno.radio).stroke(Color.white.opacity(0.13), lineWidth: 1))
    }

    private func horaTexto(_ fecha: Date) -> String {
        let formato = DateFormatter()
        formato.dateFormat = "HH:mm"
        return formato.string(from: fecha)
    }
}

/// Velocidad en tiempo real (dentro del panel, a la derecha) + la señal del límite
struct Velocidad: View {
    @ObservedObject var estado: Estado

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(estado.velocidadKmh.map { "\($0)" } ?? "--")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundColor(estado.pasadoDeLimite ? Color(red: 1, green: 0.36, blue: 0.32) : .white)
                Text("km/h")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            if let limite = estado.limiteActual {
                Text("\(limite)")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.black)
                    .frame(width: 28, height: 28)
                    .background(Color.white, in: Circle())
                    .overlay(
                        Circle().stroke(
                            estado.pasadoDeLimite ? Color(red: 1, green: 0.27, blue: 0.23) : Color(red: 0.88, green: 0.14, blue: 0.14),
                            lineWidth: 3
                        )
                    )
            }
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.white.opacity(0.16)).frame(width: 1)
        }
    }
}

// ── El panel de abajo: los botones ────────────────────────────────────────────
struct PanelAbajo: View {
    @ObservedObject var estado: Estado
    var abrirLista: () -> Void

    // (Los textos se calculan aparte: juntos en el cuerpo, Swift se atasca al revisarlos)
    private var tituloDestino: String { estado.destino == nil ? "Elegir destino" : "Cambiar destino" }
    private var tituloNavegar: String { estado.navegando ? "Salir" : "Iniciar" }
    private var iconoNavegar: String { estado.navegando ? "xmark" : "location.north.line.fill" }
    private var tipoNavegar: BotonApp.Tipo { estado.navegando ? .peligro : .verde }
    private var paradaActual: Int { min((estado.indiceActual ?? 0) + 1, max(estado.paradas.count, 1)) }
    private var textoHechas: String {
        "· \(estado.hechas.count) hecha\(estado.hechas.count == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(spacing: 10) {
            // ── El viaje: en qué parada vas ──────────────────────────────────
            if estado.paradas.count > 1 {
                HStack(spacing: 8) {
                    Image(systemName: "flag.checkered")
                        .foregroundColor(Diseno.acento)
                    Text("Parada \(paradaActual) de \(estado.paradas.count)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Diseno.texto)
                    if !estado.hechas.isEmpty {
                        Text(textoHechas)
                            .font(.system(size: 13))
                            .foregroundColor(Diseno.apagado)
                    }
                    Spacer()
                }
            }

            if estado.destino != nil {
                // El perfil (En coche / A pie), como la barra de la web
                SelectorPerfil(estado: estado)
            }

            HStack(spacing: 10) {
                BotonApp(titulo: tituloDestino, icono: "magnifyingglass", tipo: .fantasma, compacto: true) {
                    abrirLista()
                }
                if estado.destino != nil {
                    BotonApp(titulo: tituloNavegar, icono: iconoNavegar, tipo: tipoNavegar, compacto: true) {
                        if estado.navegando {
                            estado.salirDeNavegacion()
                        } else {
                            estado.iniciarNavegacion()
                        }
                    }
                }
            }

            if estado.destino != nil {
                HStack(spacing: 10) {
                    BotonApp(titulo: "Google Maps", icono: "globe", tipo: .fantasma, compacto: true) {
                        abrirViajeEnGoogleMaps(paradas: estado.paradas, desde: estado.posicion?.coordinate)
                    }
                    BotonApp(titulo: "Limpiar", icono: "trash", tipo: .fantasma, compacto: true) {
                        estado.limpiarViaje()
                    }
                }
            }

            // ── La barra de progreso, pegada al borde de abajo (como la web) ──
            if estado.destino != nil {
                BarraProgreso(valor: estado.progreso, alto: 5)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: Diseno.radio))
        .overlay(RoundedRectangle(cornerRadius: Diseno.radio).stroke(Color.white.opacity(0.13), lineWidth: 0.5))
    }
}

// ── Elegir destino y armar el viaje (varias paradas) ──────────────────────────
struct ElegirDestino: View {
    @ObservedObject var estado: Estado
    @ObservedObject var almacen: Almacen
    var cerrar: () -> Void
    @State private var consulta = ""
    @State private var guardandoRuta = false
    @State private var nombreRuta = ""
    @State private var mensaje: String?

    var body: some View {
        NavigationStack {
            /* OJO: aquí NO se usa una `List` a propósito. Dentro de una `List`, el fondo con
               `GeometryReader` del hilo recibe alto cero y LA LÍNEA NO SE PINTA (era el fallo
               de «el progresbar de Cambiar destino no funciona»). Con un `ScrollView` +
               `LazyVStack` se pinta igual que en la ruta abierta, que es lo que quieres. */
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    cabecera

                    if !estado.paradas.isEmpty {
                        Text("Tu viaje · \(estado.paradas.count) parada\(estado.paradas.count == 1 ? "" : "s") · \(estado.hechas.count) hecha\(estado.hechas.count == 1 ? "" : "s")")
                            .font(.disEtiqueta)
                            .foregroundColor(Diseno.apagado)

                        ForEach(Array(estado.paradas.enumerated()), id: \.offset) { indice, parada in
                            VStack(alignment: .leading, spacing: 0) {
                                // 1) El tramo que llega a esta parada (hilo + paneles)
                                if estado.tramos.indices.contains(indice) {
                                    conectorDeViaje(indice: indice)
                                }
                                // 2) La parada, con su progreso
                                FilaDeslizable(
                                    izquierda: [
                                        AccionFila(
                                            titulo: estado.hechas.contains(indice) ? "Deshacer" : "Hecha",
                                            icono: "checkmark.circle.fill",
                                            color: Diseno.verde
                                        ) {
                                            Task { await estado.marcarHecha(indice) }
                                        },
                                        AccionFila(titulo: "Subir", icono: "arrow.up", color: Diseno.acento) {
                                            if indice > 0 {
                                                estado.moverParada(de: IndexSet(integer: indice), a: indice - 1)
                                            }
                                        },
                                    ],
                                    derecha: [
                                        AccionFila(titulo: "Bajar", icono: "arrow.down", color: Diseno.acento) {
                                            if indice < estado.paradas.count - 1 {
                                                estado.moverParada(de: IndexSet(integer: indice), a: indice + 2)
                                            }
                                        },
                                        AccionFila(titulo: "Quitar", icono: "trash.fill", color: Diseno.peligro) {
                                            estado.quitarParada(indice)
                                        },
                                    ],
                                    alTocar: { Task { await estado.marcarHecha(indice) } }
                                ) {
                                    tarjetaDeViaje(indice: indice, parada: parada)
                                }
                            }
                        }

                        Text("Toca una parada para marcarla hecha. Deslizando: a un lado para marcarla o subirla, al otro para bajarla o quitarla.")
                            .font(.disEtiqueta)
                            .foregroundColor(Diseno.apagado)
                    }

                    // ── El buscador para añadir paradas ──────────────────────
                    Text(estado.paradas.isEmpty ? "Elige destino" : "Añadir otra parada")
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundColor(Diseno.texto)
                        .padding(.top, 6)

                    buscadorDeUbicaciones

                    if almacen.cargando && almacen.ubicaciones.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Cargando ubicaciones…").foregroundColor(Diseno.apagado)
                        }
                    } else if filtradas.isEmpty {
                        Text("No hay ubicaciones que coincidan.")
                            .font(.disSecundario)
                            .foregroundColor(Diseno.apagado)
                    } else {
                        /* LA MISMA FILA QUE EN UBICACIONES (SwipeRow con la franja de la
                           categoría redondeada) y con el botón de FIJAR, como en la web. */
                        ForEach(filtradas) { ubicacion in
                            FilaDeslizable(
                                izquierda: [
                                    AccionFila(
                                        titulo: ubicacion.pinned ? "Desfijar" : "Fijar",
                                        icono: ubicacion.pinned ? "pin.slash.fill" : "pin.fill",
                                        color: Diseno.naranjaPin
                                    ) {
                                        Task { await almacen.alternarFijada(ubicacion) }
                                    },
                                ],
                                derecha: [
                                    AccionFila(titulo: "Añadir", icono: "plus.circle.fill", color: Diseno.verde) {
                                        Task {
                                            if estado.paradas.isEmpty {
                                                await estado.elegirDestino(ubicacion)
                                            } else {
                                                await estado.anadirParada(ubicacion)
                                            }
                                        }
                                    },
                                ],
                                alTocar: {
                                    Task {
                                        if estado.paradas.isEmpty {
                                            await estado.elegirDestino(ubicacion)
                                        } else {
                                            await estado.anadirParada(ubicacion)
                                        }
                                    }
                                }
                            ) {
                                ContenidoFilaUbicacion(
                                    ubicacion: ubicacion,
                                    categoria: almacen.categoria(ubicacion.categoryId),
                                    etiquetas: ubicacion.tagIds.compactMap { almacen.etiqueta($0) },
                                    distancia: almacen.distancia(ubicacion, desde: estado.posicion),
                                    mostrarDireccion: true,
                                    mostrarTiempoDistancia: true
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .background(FondoMidnight())
            .simultaneousGesture(TapGesture().onEnded { FilasAbiertas.compartida.cerrarTodas() })
            .cerrarFilasAlDesplazar()
            .bloqueaScrollAlDeslizarFila()
            .navigationTitle("Ir a")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Diseno.fondo, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(Diseno.acento)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { cerrar() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Las paradas se reordenan y se quitan deslizando (FilaDeslizable)
                    EmptyView()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button {
                            abrirEnGoogleMaps()
                        } label: {
                            Label("Abrir el viaje en Google Maps", systemImage: "globe")
                        }
                        Button {
                            nombreRuta = "Ruta a \(estado.paradas.last?.name ?? "destino")"
                            guardandoRuta = true
                        } label: {
                            Label("Guardar como ruta", systemImage: "square.and.arrow.down")
                        }
                        Button(role: .destructive) {
                            estado.limpiarViaje()
                        } label: {
                            Label("Limpiar el viaje", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(estado.paradas.isEmpty)
                }
            }
            .alert("Guardar la ruta", isPresented: $guardandoRuta) {
                TextField("Nombre de la ruta", text: $nombreRuta)
                Button("Cancelar", role: .cancel) {}
                Button("Guardar") {
                    Task {
                        let nombre = nombreRuta.trimmingCharacters(in: .whitespacesAndNewlines)
                        let ruta = await almacen.guardarRuta(
                            nombre: nombre.isEmpty ? "Ruta sin nombre" : nombre,
                            locationIds: estado.paradas.map { $0.id }
                        )
                        mensaje = "Guardada: «\(ruta.name)»"
                    }
                }
            } message: {
                Text("Aparecerá en la pestaña Rutas (y en la web).")
            }
            .alert(mensaje ?? "", isPresented: Binding(
                get: { mensaje != nil },
                set: { if !$0 { mensaje = nil } }
            )) {
                Button("Vale") { mensaje = nil }
            }
        }
    }

    /// La cabecera del viaje, como el título del panel de la web
    private var cabecera: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Ir a")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundColor(Diseno.texto)
                Image(systemName: "arrow.right")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Diseno.acento)
                Text(estado.destino?.name ?? "Sin destino")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(Diseno.acento)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            SelectorPerfil(estado: estado)
            if !estado.paradas.isEmpty {
                TotalesViaje(estado: estado)
            }
        }
    }

    /// El buscador para añadir paradas
    private var buscadorDeUbicaciones: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(Diseno.apagado)
            TextField("Buscar ubicación…", text: $consulta)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(Diseno.texto)
            if !consulta.isEmpty {
                Button {
                    consulta = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(Diseno.apagado)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(Diseno.fondoTarjeta, in: RoundedRectangle(cornerRadius: Diseno.radioSm))
        .overlay(RoundedRectangle(cornerRadius: Diseno.radioSm).stroke(Diseno.linea, lineWidth: 0.5))
    }

    /* EL HILO DE UN TRAMO DEL VIAJE: es el MISMO componente que usa la ruta abierta
       (HiloVertical), así que también lleva la pista, el relleno con degradado y el punto
       que viaja por la línea. */
    private func conectorDeViaje(indice: Int) -> some View {
        let tramo = estado.tramos[indice]
        let completado = estado.hechas.contains(indice)
        let activo = !completado && indice == (estado.indiceActual ?? 0)
        let progreso = avanceHaciaLaParada(
            indice: indice,
            paradas: estado.paradas,
            hechas: estado.hechas,
            objetivo: estado.indiceActual,
            posicion: estado.posicion,
            perfil: estado.perfil
        )
        return HStack(alignment: .center, spacing: 12) {
            Color.clear.frame(width: 28)
            PanelesTramo(
                minutos: tramo.durationMins,
                km: tramo.distKm,
                trafico: tramo.trafico,
                retrasoMin: tramo.retrasoMin,
                hecho: completado,
                sinTrafico: estado.perfil == "pie",
                llegada: tramo.llegada
            )
        }
        .background(alignment: .topLeading) {
            GeometryReader { geo in
                HiloVertical(progreso: progreso, activo: activo, completado: completado, alto: geo.size.height)
            }
        }
        .padding(.vertical, 8)
    }

    /// La tarjeta de una parada del viaje: con su barra de progreso de fondo y su %
    private func tarjetaDeViaje(indice: Int, parada: Ubicacion) -> some View {
        let completada = estado.hechas.contains(indice)
        let progreso = avanceHaciaLaParada(
            indice: indice,
            paradas: estado.paradas,
            hechas: estado.hechas,
            objetivo: estado.indiceActual,
            posicion: estado.posicion,
            perfil: estado.perfil
        )
        let color = completada ? Color(hex: "#8a272e") : Diseno.acento
        return ZStack(alignment: .leading) {
            GeometryReader { geo in
                Rectangle()
                    .fill(
                        completada
                            ? LinearGradient(colors: [Color(hex: "#6e2429"), Color(hex: "#6e2429")], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [color, Color(hex: "#5c1e22")], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: geo.size.width * max(0, min(1, progreso)))
            }

            HStack(spacing: 12) {
                Rectangle()
                    .fill(color)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(parada.name)
                            .font(.system(size: 21, weight: .regular))
                            .foregroundColor(completada ? Color.white.opacity(0.65) : Diseno.texto)
                            .strikethrough(completada)
                            .lineLimit(2)
                        if !completada && progreso > 0.01 {
                            Text("\(Int((progreso * 100).rounded()))%")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundColor(Color(hex: "#ffe2a1"))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .overlay(Capsule().stroke(Color(hex: "#ffe0a0").opacity(0.45), lineWidth: 1))
                        }
                    }
                    if !parada.address.isEmpty {
                        Text(parada.address)
                            .font(.system(size: 15))
                            .foregroundColor(Diseno.apagado)
                            .strikethrough(completada)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 14)
                Spacer(minLength: 8)
                ZStack {
                    Circle()
                        .fill(completada ? Color(hex: "#7a2228") : Color.clear)
                        .frame(width: 30, height: 30)
                        .overlay(
                            Circle().stroke(
                                completada ? Color(hex: "#aa3840") : Color.white.opacity(0.25),
                                lineWidth: 2
                            )
                        )
                    if completada {
                        Text("✓")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundColor(.white)
                    }
                }
                .padding(.trailing, 14)
            }
        }
        .background(completada ? Color(hex: "#4e1a1d").opacity(0.45) : Diseno.fondoFila)
        .clipShape(RoundedRectangle(cornerRadius: Diseno.radio))
        .overlay(
            RoundedRectangle(cornerRadius: Diseno.radio)
                .stroke(completada ? Color(hex: "#a03237").opacity(0.35) : Diseno.linea, lineWidth: 0.5)
        )
        .padding(.vertical, 5)
    }

    private var filtradas: [Ubicacion] {
        let texto = consulta.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = almacen.ubicaciones.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        /* ¡OJO!: antes, cuando NO había texto de búsqueda, se devolvía la lista alfabética y
           las fijadas NO se ponían arriba (por eso «no se muestra fijada»). Ahora se agrupan
           siempre: primero las fijadas y después el resto. */
        let lista = texto.isEmpty ? base : base.filter { "\($0.name) \($0.address)".lowercased().contains(texto) }
        return lista.filter { $0.pinned } + lista.filter { !$0.pinned }
    }

    /// El viaje entero en Google Maps: destino + todas las paradas como puntos de paso
    private func abrirEnGoogleMaps() {
        let paradas = estado.paradas
        guard let primera = paradas.first, paradas.count >= 1 else { return }
        let destino = paradas.count == 1 ? primera : (paradas.last ?? primera)
        var comp = URLComponents(string: "https://www.google.com/maps/dir/")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(destino.lat),\(destino.lng)"),
        ]
        // Los puntos intermedios (todas menos la última) van como waypoints
        let intermedias = paradas.dropLast().dropFirst()
        if !intermedias.isEmpty {
            let waypoints = intermedias.map { "\($0.lat),\($0.lng)" }.joined(separator: "|")
            items.append(URLQueryItem(name: "waypoints", value: waypoints))
        }
        if let pos = estado.posicion {
            items.append(URLQueryItem(name: "origin", value: "\(pos.coordinate.latitude),\(pos.coordinate.longitude)"))
        }
        comp.queryItems = items
        if let url = comp.url { UIApplication.shared.open(url) }
    }
}

/// Fila sencilla (nombre + dirección + distancia), la usan el selector y las rutas
struct FilaUbicacionSimple: View {
    let ubicacion: Ubicacion
    let posicion: CLLocation?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ubicacion.name)
                    .font(.disFila)
                    .foregroundColor(Diseno.texto)
                    .lineLimit(1)
                if !ubicacion.address.isEmpty {
                    Text(ubicacion.address)
                        .font(.disSecundario)
                        .foregroundColor(Diseno.apagado)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let metros = distancia {
                Pastilla(texto: textoDistanciaCorta(metros), color: Diseno.apagado)
            }
        }
    }

    private var distancia: CLLocationDistance? {
        guard let posicion = posicion, ubicacion.tieneCoordenadas else { return nil }
        return CLLocation(latitude: ubicacion.lat, longitude: ubicacion.lng).distance(from: posicion)
    }
}

// ── El cartel del radar (con la distancia y la barra de acercamiento) ─────────
struct BannerRadar: View {
    let radar: Radar
    @ObservedObject var estado: Estado

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.black)
                VStack(alignment: .leading, spacing: 2) {
                    Text(radar.titulo)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundColor(.black)
                    HStack(spacing: 8) {
                        if let limite = radar.speed {
                            Text("Límite \(Int(limite)) km/h")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.black.opacity(0.8))
                        }
                        if let metros = distancia {
                            Text(textoDistanciaCorta(metros))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.black.opacity(0.8))
                        }
                    }
                }
                Spacer()
                if estado.radarAvisando == radar.id {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.black.opacity(0.7))
                }
            }
            // Barra: se llena conforme te acercas al radar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.18))
                    Capsule()
                        .fill(Color.black.opacity(0.65))
                        .frame(width: max(0, geo.size.width * avance))
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.yellow, in: RoundedRectangle(cornerRadius: Diseno.radioSm))
    }

    private var distancia: CLLocationDistance? {
        guard let pos = estado.posicion else { return nil }
        return CLLocation(latitude: radar.lat, longitude: radar.lng).distance(from: pos)
    }

    /// De 0 a 1: cuánto te has acercado (0 = justo cuando empieza el aviso)
    private var avance: Double {
        guard let metros = distancia else { return 0 }
        let velocidad = Double(estado.velocidadKmh ?? 0) / 3.6
        let total = max(300.0, min(2000.0, velocidad * 35))
        return min(max(1 - (metros / total), 0), 1)
    }
}

// ── LA BRÚJULA DE ENCIMA DEL 3D (gira con el mapa, como la de toda la vida) ────
struct Brujula: View {
    @ObservedObject var controlador: ControladorMapa

    var body: some View {
        Button {
            controlador.ponerNorte()
        } label: {
            ZStack {
                Circle().fill(Color.black.opacity(0.55))
                Image(systemName: "location.north.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(controlador.rumboActual > 180 ? Diseno.peligro : Diseno.texto)
                    // La aguja GIRA con el mapa: si miras al sur, la N apunta hacia abajo
                    .rotationEffect(.degrees(-controlador.rumboActual))
            }
            .frame(width: 50, height: 50)
        }
        .buttonStyle(.plain)
    }
}

// ── LAS HOJAS DE LA PANTALLA DEL MAPA, TODAS EN UNA ───────────────────────────
/* SwiftUI SÓLO ADMITE UNA HOJA (sheet) POR VISTA: con cinco encadenadas, unas no se
   abrían (por eso al tocar una ubicación no salía «Cómo llegar») y la app se quedaba
   pillada. Ahora hay una sola hoja y se elige el contenido por caso. */
enum HojaDeMapa: Identifiable {
    case ubicaciones, comoLlegar, menu, radar, elegirDestino
    case ficha(Ubicacion)
    case editor(Ubicacion)

    var id: String {
        switch self {
        case .ubicaciones: return "ubicaciones"
        case .comoLlegar: return "comoLlegar"
        case .menu: return "menu"
        case .radar: return "radar"
        case .elegirDestino: return "elegirDestino"
        case .ficha(let ubicacion): return "ficha-\(ubicacion.id)"
        case .editor(let ubicacion): return "editor-\(ubicacion.id)"
        }
    }
}
