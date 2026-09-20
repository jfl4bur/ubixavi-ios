/* LA PESTAÑA DE RADARES.

   · CERCA: los radares que hay alrededor (oficiales y míos), con su límite y distancia.
   · LOS MÍOS: los que has capturado tú, para revisarlos y borrarlos.
   · BASE: cuándo se actualizó la base oficial, forzar la actualización y PROBAR EL AVISO
     (voz y pitidos) para comprobar el volumen antes de salir a la carretera.
   Y el botón de CAPTURAR: guarda un radar en la posición en la que estás, con su tipo y
   su límite, igual que la web.
*/
import SwiftUI
import CoreLocation

struct PantallaRadares: View {
    @ObservedObject var estado: Estado
    @ObservedObject var almacen: Almacen
    var irAlMapa: () -> Void

    enum Seccion: String, CaseIterable, Identifiable {
        case cerca = "Cerca de mí"
        case mios = "Los míos"
        case base = "Base"
        var id: String { rawValue }
    }

    @State private var seccion: Seccion = .cerca
    @State private var mios: [Servidor.RadarPropio] = []
    @State private var resumen: Servidor.ResumenRadares?
    @State private var estadoBase: Servidor.EstadoBase?
    @State private var cargando = false
    @State private var capturando = false
    @State private var refrescandoBase = false
    @State private var mensaje: String?
    @State private var borrando: Servidor.RadarPropio?
    @State private var editando: Servidor.RadarPropio?
    @State private var elegido: Radar?

    @AppStorage("avisosRadares") private var avisosRadares = true
    @AppStorage("soloRadaresEnRuta") private var soloRadaresEnRuta = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $seccion) {
                    ForEach(Seccion.allCases) { opcion in
                        Text(opcion.rawValue).tag(opcion)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                switch seccion {
                case .cerca:
                    listaCerca
                case .mios:
                    listaMios
                case .base:
                    vistaBase
                }
            }
            .navigationTitle("Radares")
            .background(FondoMidnight())
            .toolbarBackground(Diseno.fondo, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(Diseno.acento)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        capturando = true
                    } label: {
                        Label("Capturar", systemImage: "camera.fill")
                    }
                }
            }
            .task { await cargarCerca() }
            .onChange(of: seccion) { nueva in
                Task {
                    switch nueva {
                    case .cerca: await cargarCerca()
                    case .mios: await cargarMios()
                    case .base: await cargarBase()
                    }
                }
            }
            .sheet(isPresented: $capturando) {
                CapturarRadar(estado: estado) { texto in
                    mensaje = texto
                    Task {
                        await cargarCerca()
                        await cargarMios()
                    }
                }
            }
            .sheet(item: $elegido) { radar in
                DetalleRadar(radar: radar, estado: estado, irAlMapa: irAlMapa)
            }
            .sheet(item: $editando) { radar in
                EditarRadar(radar: radar, estado: estado) { texto in
                    mensaje = texto
                    Task {
                        await cargarMios()
                        await cargarCerca()
                    }
                }
            }
            .alert(mensaje ?? "", isPresented: Binding(
                get: { mensaje != nil },
                set: { if !$0 { mensaje = nil } }
            )) {
                Button("Vale") { mensaje = nil }
            }
            .alert("¿Eliminar «\(tipoTexto(borrando?.type))» de tus radares?", isPresented: Binding(
                get: { borrando != nil },
                set: { if !$0 { borrando = nil } }
            )) {
                Button("Cancelar", role: .cancel) { borrando = nil }
                Button("Eliminar", role: .destructive) {
                    if let radar = borrando {
                        Task { await quitar(radar) }
                    }
                    borrando = nil
                }
            } message: {
                Text("Se quita de tu base de radares propios y dejarás de recibir ese aviso.")
            }
        }
    }

    // ── Cerca de mí ──────────────────────────────────────────────────────────
    private var listaCerca: some View {
        Group {
            if cargando && estado.radares.isEmpty {
                Spacer()
                ProgressView("Buscando radares…")
                Spacer()
            } else if estado.radares.isEmpty {
                Spacer()
                Text("No hay radares cerca ahora mismo.")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(ordenadosCerca) { radar in
                        Button {
                            elegido = radar
                        } label: {
                            FilaRadar(
                                titulo: radar.titulo,
                                limite: radar.speed,
                                metros: radar.dist,
                                propio: radar.src == "user",
                                sentido: radar.dir,
                                tipo: radar.kind
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var ordenadosCerca: [Radar] {
        estado.radares.sorted { ($0.dist ?? 99999) < ($1.dist ?? 99999) }
    }

    // ── Los míos ─────────────────────────────────────────────────────────────
    private var listaMios: some View {
        Group {
            if cargando && mios.isEmpty {
                Spacer()
                ProgressView("Cargando tus radares…")
                Spacer()
            } else if mios.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "camera")
                        .font(.system(size: 40))
                        .foregroundColor(Diseno.apagado)
                    Text("Todavía no has capturado ninguno")
                        .font(.disSubtitulo)
                        .foregroundColor(Diseno.texto)
                        .multilineTextAlignment(.center)
                    Text("Usa el botón «Capturar» cuando pases por uno: se guarda tu posición de ese momento.")
                        .font(.disSecundario)
                        .foregroundColor(Diseno.apagado)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    BotonApp(titulo: "Capturar un radar", icono: "camera.fill", compacto: true) { capturando = true }
                        .frame(maxWidth: 260)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(mios) { radar in
                            FilaDeslizable(
                                izquierda: [
                                    // Como en la web: hacia la DERECHA se edita
                                    AccionFila(titulo: "Editar", icono: "square.and.pencil", color: Diseno.acento) {
                                        editando = radar
                                    },
                                ],
                                derecha: [
                                    AccionFila(titulo: "Eliminar", icono: "trash.fill", color: Diseno.peligro) {
                                        borrando = radar
                                    },
                                ],
                                alTocar: { editando = radar }
                            ) {
                                ContenidoFilaGenerica(
                                    titulo: tipoTexto(radar.type),
                                    subtitulo: subtituloRadar(radar),
                                    icono: iconoDeRadar(radar.type),
                                    colorIcono: colorDeRadar(radar.type),
                                    chips: chipsRadar(radar),
                                    franja: colorDeRadar(radar.type)
                                )
                            }
                        }

                        Text("Desliza una fila hacia la DERECHA para editarla (tipo, límite, inicio/final) o hacia la IZQUIERDA para eliminarla de tu base de datos.")
                            .font(.disEtiqueta)
                            .foregroundColor(Diseno.apagado)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 20)
                }
                .simultaneousGesture(TapGesture().onEnded { FilasAbiertas.compartida.cerrarTodas() })
                .cerrarFilasAlDesplazar()
                    .bloqueaScrollAlDeslizarFila()
            }
        }
    }

    /// Una tarjeta de contador (como las .stat de la web)
    private func tarjetaContador(valor: String, titulo: String, icono: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icono)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(color)
            Text(valor)
                .font(.system(size: 26, weight: .heavy))
                .foregroundColor(Diseno.texto)
            Text(titulo)
                .font(.disEtiqueta)
                .foregroundColor(Diseno.apagado)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: Diseno.radioSm))
        .overlay(RoundedRectangle(cornerRadius: Diseno.radioSm).stroke(color.opacity(0.3), lineWidth: 0.5))
    }

    /// La segunda línea de un radar mío (sentido, confirmaciones y coordenadas)
    private func subtituloRadar(_ radar: Servidor.RadarPropio) -> String {
        var partes: [String] = []
        if let rol = radar.role, !rol.isEmpty { partes.append(rol) }
        if let sentido = radar.dir, sentido >= 0 { partes.append("sentido \(Int(sentido))°") }
        if let confirmaciones = radar.confirmations, confirmaciones > 1 {
            partes.append("confirmado \(confirmaciones)×")
        }
        partes.append(String(format: "%.5f, %.5f", radar.lat, radar.lng))
        return partes.joined(separator: " · ")
    }

    private func chipsRadar(_ radar: Servidor.RadarPropio) -> [(String, Color)] {
        var chips: [(String, Color)] = []
        if let limite = radar.speed { chips.append(("Límite \(Int(limite)) km/h", Diseno.peligro)) }
        if let metros = distancia(radar) {
            chips.append((textoDistanciaCorta(metros), Diseno.apagado))
        }
        return chips
    }

    // ── La base oficial ──────────────────────────────────────────────────────
    private var vistaBase: some View {
        Form {
            // ── Los contadores, con las tarjetas de la web ──────────────────
            Section {
                HStack(spacing: 10) {
                    tarjetaContador(
                        valor: estadoBase?.count.map { "\($0)" } ?? "—",
                        titulo: "Oficiales",
                        icono: "shield.lefthalf.filled",
                        color: Diseno.acento
                    )
                    tarjetaContador(
                        valor: "\(resumen?.total ?? mios.count)",
                        titulo: "Míos",
                        icono: "person.crop.circle.badge.checkmark",
                        color: Diseno.verde
                    )
                    tarjetaContador(
                        valor: "\(estado.radares.count)",
                        titulo: "Cerca",
                        icono: "location.fill",
                        color: Diseno.azul
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                Toggle("Avisos de radar (voz y pitidos)", isOn: $avisosRadares)
                Toggle("Avisar sólo de los radares de la ruta", isOn: $soloRadaresEnRuta)
                Button {
                    estado.probarAviso()
                } label: {
                    Label("Probar el aviso (sólo el sonido)", systemImage: "speaker.wave.3.fill")
                }
                Button {
                    if estado.demoActiva {
                        estado.pararDemo()
                    } else {
                        estado.empezarDemo()
                        irAlMapa() // se cambia al mapa para que se vea la demo entera
                    }
                } label: {
                    Label(
                        estado.demoActiva ? "Parar la demo" : "DEMO completa: conduce sola hasta un radar",
                        systemImage: estado.demoActiva ? "stop.circle.fill" : "play.circle.fill"
                    )
                }
                .tint(estado.demoActiva ? Diseno.peligro : Diseno.acento)
            } header: {
                Text("Avisos")
            } footer: {
                Text("La DEMO conduce sola hacia un radar de mentira 900 m al norte: verás el mapa moverse, tu punto, el velocímetro y el aviso con voz y pitidos cuando toca. Cambia a la pestaña Mapa para verlo.")
            }

            Section("Base de radares") {
                HStack {
                    Text("Radares oficiales")
                    Spacer()
                    Text(estadoBase?.count.map { "\($0)" } ?? "—").foregroundColor(.secondary)
                }
                HStack {
                    Text("Actualizada")
                    Spacer()
                    Text(estadoBase?.updatedAt.map { fecha($0) } ?? "—").foregroundColor(.secondary)
                }
                if let fuentes = estadoBase?.sources, !fuentes.isEmpty {
                    HStack {
                        Text("Fuentes")
                        Spacer()
                        Text(fuentes.joined(separator: ", ")).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                Button {
                    Task { await actualizarBase() }
                } label: {
                    Label(refrescandoBase ? "Actualizando (tarda un minuto)…" : "Actualizar la base ahora", systemImage: "arrow.clockwise")
                }
                .disabled(refrescandoBase)
            }

            Section("Tu base") {
                HStack {
                    Text("Radares propios")
                    Spacer()
                    Text("\(resumen?.total ?? mios.count)").foregroundColor(.secondary)
                }
                HStack {
                    Text("Confirmados por otros")
                    Spacer()
                    Text("\(resumen?.quitados ?? 0)").foregroundColor(.secondary)
                }
                if let porTipo = resumen?.porTipo, !porTipo.isEmpty {
                    ForEach(porTipo.sorted(by: { $0.value > $1.value }), id: \.key) { tipo, cuantos in
                        HStack {
                            Text(tipoTexto(tipo))
                            Spacer()
                            Text("\(cuantos)").foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // ── Cargas ───────────────────────────────────────────────────────────────
    private func cargarCerca() async {
        cargando = true
        defer { cargando = false }
        if let pos = estado.posicion,
           let lista = try? await Servidor.radares(lat: pos.coordinate.latitude, lng: pos.coordinate.longitude) {
            estado.radares = lista
        }
    }

    private func cargarMios() async {
        cargando = true
        defer { cargando = false }
        if let datos = try? await Servidor.misRadares() {
            resumen = datos
            mios = datos.items ?? []
        }
    }

    private func cargarBase() async {
        cargando = true
        defer { cargando = false }
        estadoBase = try? await Servidor.estadoBase()
        await cargarMios()
    }

    private func actualizarBase() async {
        refrescandoBase = true
        defer { refrescandoBase = false }
        do {
            try await Servidor.refrescarBase()
            mensaje = "Actualización lanzada. En un minuto estará lista."
        } catch {
            mensaje = "No pude actualizar: \(error.localizedDescription)"
        }
    }

    private func quitar(_ radar: Servidor.RadarPropio) async {
        do {
            try await Servidor.borrarRadar(lat: radar.lat, lng: radar.lng, type: radar.type ?? "")
            // Y A LA PAPELERA: antes se perdía para siempre; desde Ajustes → Papelera se puede
            // recuperar (vuelve a capturarse en el mismo sitio)
            await almacen.radarALaPapelera(radar)
            await cargarMios()
            await cargarCerca()
            mensaje = "Radar a la Papelera (puedes recuperarlo en Ajustes → Papelera)"
        } catch {
            mensaje = "No pude borrarlo: \(error.localizedDescription)"
        }
    }

    private func distancia(_ radar: Servidor.RadarPropio) -> Double? {
        guard let pos = estado.posicion else { return nil }
        return CLLocation(latitude: radar.lat, longitude: radar.lng).distance(from: pos)
    }

    private func fecha(_ milisegundos: Double) -> String {
        let formato = DateFormatter()
        formato.dateFormat = "dd/MM HH:mm"
        return formato.string(from: Date(timeIntervalSince1970: milisegundos / 1000))
    }
}

func tipoTexto(_ tipo: String?) -> String {
    switch tipo ?? "" {
    case "fixed": return "Radar fijo"
    case "mobile": return "Radar móvil"
    case "tunnel": return "Radar de túnel"
    case "redlight": return "Radar de semáforo"
    case "section": return "Radar de tramo"
    case "belt": return "Cámara de infracciones"
    default: return "Radar"
    }
}

/// El icono de cada tipo de radar (los mismos de la web)
func iconoDeRadar(_ tipo: String?) -> String {
    switch tipo ?? "" {
    case "fixed": return "camera.fill"
    case "mobile": return "car.fill"
    case "tunnel": return "arrow.up.arrow.down"
    case "redlight": return "light.beacon.max.fill"
    case "section": return "arrow.left.and.right"
    case "belt": return "figure.walk.motion"
    default: return "camera.fill"
    }
}

/// El color de cada tipo de radar (los mismos de la web)
func colorDeRadar(_ tipo: String?) -> Color {
    switch tipo ?? "" {
    case "fixed": return Color(hex: "#ff453a")
    case "section", "belt": return Color(hex: "#ff9f0a")
    case "redlight": return Color(hex: "#8b5cf6")
    case "tunnel", "mobile": return Color(hex: "#0a84ff")
    default: return Diseno.peligro
    }
}

// ── Fila de radar ─────────────────────────────────────────────────────────────
struct FilaRadar: View {
    let titulo: String
    let limite: Double?
    let metros: Double?
    let propio: Bool
    let sentido: Double?
    var confirmaciones: Int?
    /// El tipo (para pintar SU icono y SU color, como en la web)
    var tipo: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconoDeRadar(tipo))
                .foregroundColor(colorDeRadar(tipo))
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 3) {
                Text(titulo).font(.system(size: 16, weight: .semibold))
                HStack(spacing: 8) {
                    if let limite = limite {
                        Text("Límite \(Int(limite)) km/h")
                            .font(.system(size: 12.5))
                            .foregroundColor(.secondary)
                    }
                    if let sentido = sentido, sentido >= 0 {
                        Text("sentido \(Int(sentido))°")
                            .font(.system(size: 12.5))
                            .foregroundColor(.secondary)
                    }
                    if let confirmaciones = confirmaciones, confirmaciones > 1 {
                        Text("confirmado \(confirmaciones)×")
                            .font(.system(size: 12.5))
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            if let metros = metros {
                Text(metros < 1000 ? "\(Int(metros.rounded())) m" : String(format: "%.1f km", metros / 1000))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// ── Editar un radar propio ────────────────────────────────────────────────────
/* EDITAR UN AVISO, exactamente igual que en la web: los mismos paneles de la app
   (cuadrícula grande de tipos con su icono y su color, cuadrícula de inicio/final para
   los de tramo y cuadrícula de límites), el mismo aspecto que la pantalla de capturar,
   y además CAMBIAR LA UBICACIÓN pegando el enlace de Google Maps (se resuelve solo).
   Los deslizamientos de «Los míos» son los de la app, así que se edita desde el mismo
   gesto de siempre: deslizar la fila (o tocarla) y sale este panel. */
struct EditarRadar: View {
    let radar: Servidor.RadarPropio
    @ObservedObject var estado: Estado
    var hecho: (String) -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var tipo: String = "fixed"
    @State private var rol: String?
    @State private var velocidad: Int?
    @State private var lat: Double = 0
    @State private var lng: Double = 0
    /// Si la posición se ha tocado (si no, el servidor deja la que ya tenía)
    @State private var posicionCambiada = false
    @State private var enlace = ""
    @State private var buscandoEnlace = false
    @State private var errorEnlace: String?
    @State private var direccionResuelta: String?
    @State private var guardando = false
    @State private var aviso: String?

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

    /// El de tramo pregunta inicio o final; la cámara de infracciones no lleva límite
    private var pideTramo: Bool { tipo == "section" }
    private var pideLimite: Bool { tipo != "belt" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    cabecera
                    panelTipos
                    if pideTramo { panelTramo }
                    if pideLimite { panelVelocidad }
                    panelPosicion
                    if guardando { ProgressView().tint(Diseno.acento) }
                }
                .padding(16)
            }
            .fondoApp()
            .simultaneousGesture(TapGesture().onEnded { ocultarTeclado() })
            .navigationTitle("Editar aviso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Diseno.fondo, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(Diseno.acento)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { cerrar() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(guardando ? "Guardando…" : "Guardar") {
                        Task { await guardar() }
                    }
                    .disabled(guardando)
                }
            }
            .alert(aviso ?? "", isPresented: Binding(
                get: { aviso != nil },
                set: { if !$0 { aviso = nil } }
            )) {
                Button("Vale") { aviso = nil }
            }
            .onAppear {
                tipo = radar.type ?? "fixed"
                rol = radar.role
                velocidad = radar.speed.map { Int($0) }
                lat = radar.lat
                lng = radar.lng
            }
        }
    }

    // ── La cabecera: el tipo que es ahora mismo ──────────────────────────────
    private var cabecera: some View {
        HStack(spacing: 12) {
            Image(systemName: tipoActual.icono)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(tipoActual.color)
                .frame(width: 52, height: 52)
                .background(tipoActual.color.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(tipoActual.etiqueta)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundColor(Diseno.texto)
                Text("Capturado el \(fechaCorta(radar))\(radar.confirmations.map { " · confirmado \($0)×" } ?? "")")
                    .font(.disEtiqueta)
                    .foregroundColor(Diseno.apagado)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tarjeta(relleno: 12)
    }

    private func fechaCorta(_ radar: Servidor.RadarPropio) -> String {
        guard let milisegundos = radar.createdAt else { return "—" }
        let formato = DateFormatter()
        formato.dateFormat = "dd/MM/yyyy"
        return formato.string(from: Date(timeIntervalSince1970: milisegundos / 1000))
    }

    // ── El tipo, en cuadrícula de dos (igual que al capturar) ────────────────
    private var panelTipos: some View {
        VStack(spacing: 12) {
            Text("¿Qué tipo de aviso es?")
                .font(.disSubtitulo)
                .foregroundColor(Diseno.texto)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(tipos, id: \.id) { opcion in
                    Button {
                        tipo = opcion.id
                        if opcion.id != "section" { rol = nil }
                        if opcion.id == "belt" { velocidad = nil }
                        Tacto.seleccion()
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
                        .background(opcion.color.opacity(tipo == opcion.id ? 0.24 : 0.1), in: RoundedRectangle(cornerRadius: Diseno.radio))
                        .overlay(
                            RoundedRectangle(cornerRadius: Diseno.radio)
                                .stroke(opcion.color.opacity(tipo == opcion.id ? 0.9 : 0.35), lineWidth: tipo == opcion.id ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // ── Inicio o final del tramo ─────────────────────────────────────────────
    private var panelTramo: some View {
        VStack(spacing: 12) {
            Text("¿Inicio o final del tramo?")
                .font(.disSubtitulo)
                .foregroundColor(Diseno.texto)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                botonTramo("inicio", "Inicio del tramo", "flag.fill", Diseno.verde)
                botonTramo("final", "Final del tramo", "flag.checkered", Diseno.acento)
            }
        }
    }

    private func botonTramo(_ valor: String, _ etiqueta: String, _ icono: String, _ color: Color) -> some View {
        let activo = rol == valor
        return Button {
            rol = valor
            Tacto.seleccion()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icono).font(.system(size: 34)).foregroundColor(color)
                Text(etiqueta).font(.system(size: 15, weight: .bold)).foregroundColor(Diseno.texto)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 130)
            .background(color.opacity(activo ? 0.24 : 0.1), in: RoundedRectangle(cornerRadius: Diseno.radio))
            .overlay(
                RoundedRectangle(cornerRadius: Diseno.radio)
                    .stroke(color.opacity(activo ? 0.9 : 0.35), lineWidth: activo ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // ── El límite, en cuadrícula de tres ─────────────────────────────────────
    private var panelVelocidad: some View {
        VStack(spacing: 12) {
            Text("Límite de velocidad")
                .font(.disSubtitulo)
                .foregroundColor(Diseno.texto)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ], spacing: 12) {
                ForEach(velocidades, id: \.self) { valor in
                    Button {
                        velocidad = (velocidad == valor) ? nil : valor
                        Tacto.seleccion()
                    } label: {
                        Text("\(valor)")
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundColor(velocidad == valor ? .black : Diseno.texto)
                            .frame(maxWidth: .infinity)
                            .frame(height: 76)
                            .background(
                                velocidad == valor ? Diseno.acento : Diseno.fondoTarjetaAlta,
                                in: RoundedRectangle(cornerRadius: Diseno.radioSm)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Diseno.radioSm)
                                    .stroke(velocidad == valor ? Diseno.acento : Diseno.lineaFuerte, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                velocidad = nil
                Tacto.seleccion()
            } label: {
                Text("Sin límite")
                    .font(.disCuerpo.weight(.semibold))
                    .foregroundColor(velocidad == nil ? .black : Diseno.acento)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(velocidad == nil ? Diseno.acento : Diseno.acento.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(Diseno.acento.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }

    // ── La posición: se pega el enlace, se resuelve, o se coge la de ahora ───
    private var panelPosicion: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cambiar la ubicación (si la pusiste mal)")
                .font(.disSubtitulo)
                .foregroundColor(Diseno.texto)

            HStack(spacing: 8) {
                TextField("Pega el enlace de Google Maps…", text: $enlace)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(Diseno.texto)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(Diseno.fondoTarjetaAlta, in: RoundedRectangle(cornerRadius: Diseno.radioSm))
                    .overlay(RoundedRectangle(cornerRadius: Diseno.radioSm).stroke(Diseno.lineaFuerte, lineWidth: 1))
                BotonApp(titulo: buscandoEnlace ? "…" : "Buscar", icono: "magnifyingglass", tipo: .fantasma, compacto: true) {
                    Task { await resolver() }
                }
                .frame(width: 130)
                .disabled(buscandoEnlace || enlace.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let error = errorEnlace {
                Text(error)
                    .font(.disEtiqueta.weight(.semibold))
                    .foregroundColor(Diseno.peligro)
            } else if posicionCambiada {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(Diseno.verde)
                    Text("Nueva ubicación: \(String(format: "%.5f", lat)), \(String(format: "%.5f", lng))\(direccionResuelta.map { " · \($0)" } ?? "")")
                        .font(.disEtiqueta.weight(.semibold))
                        .foregroundColor(Diseno.verde)
                }
            } else {
                Text("📍 Ahora está en \(String(format: "%.5f", lat)), \(String(format: "%.5f", lng)) · si lo dejas vacío no se toca")
                    .font(.disEtiqueta)
                    .foregroundColor(Diseno.apagado)
            }

            Button {
                if let pos = estado.posicion {
                    lat = pos.coordinate.latitude
                    lng = pos.coordinate.longitude
                    posicionCambiada = true
                    direccionResuelta = "tu posición de ahora"
                    errorEnlace = nil
                    AvisosFlotantes.compartido.info("Posición puesta en la tuya de ahora")
                }
            } label: {
                Label("Poner mi posición actual", systemImage: "location.fill")
                    .font(.disCuerpo.weight(.semibold))
                    .foregroundColor(Diseno.acento)
            }
            .buttonStyle(.plain)
            .disabled(estado.posicion == nil)

            if posicionCambiada {
                Button {
                    lat = radar.lat
                    lng = radar.lng
                    posicionCambiada = false
                    direccionResuelta = nil
                    enlace = ""
                    errorEnlace = nil
                } label: {
                    Label("Dejarla como estaba", systemImage: "arrow.uturn.backward")
                        .font(.disEtiqueta)
                        .foregroundColor(Diseno.apagado)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tarjeta(relleno: 14)
    }

    /// Resuelve el enlace pegado con el mismo resolutor que usan las listas
    private func resolver() async {
        let texto = enlace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { return }
        buscandoEnlace = true
        defer { buscandoEnlace = false }
        errorEnlace = nil
        do {
            let lugar = try await Servidor.resolverEnlace(texto)
            if let nuevaLat = lugar.lat, let nuevaLng = lugar.lng {
                lat = nuevaLat
                lng = nuevaLng
                posicionCambiada = true
                direccionResuelta = lugar.address ?? lugar.name
                ocultarTeclado()
            } else {
                errorEnlace = lugar.error ?? "No pude sacar las coordenadas de ese enlace"
            }
        } catch {
            errorEnlace = "No pude resolver el enlace: \(error.localizedDescription)"
        }
    }

    private func ocultarTeclado() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func guardar() async {
        guardando = true
        defer { guardando = false }
        let tipoFinal = tipo
        let rolFinal = pideTramo ? (rol ?? "inicio") : nil
        let velocidadFinal = pideLimite ? velocidad.map { Double($0) } : nil
        do {
            let resultado = try await Servidor.editarRadar(
                id: radar.id,
                type: tipoFinal,
                speed: velocidadFinal,
                role: rolFinal,
                lat: posicionCambiada ? lat : nil,
                lng: posicionCambiada ? lng : nil
            )
            if resultado.ok == true {
                hecho("Radar actualizado")
                cerrar()
            } else {
                aviso = resultado.error ?? "No se pudo guardar"
            }
        } catch {
            aviso = "No se pudo guardar: \(error.localizedDescription)"
        }
    }
}

// ── Ficha de un radar ─────────────────────────────────────────────────────────
struct DetalleRadar: View {
    let radar: Radar
    @ObservedObject var estado: Estado
    var irAlMapa: () -> Void

    @Environment(\.dismiss) private var cerrar

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // La cabecera, con el tipo y su color
                    HStack(spacing: 12) {
                        Image(systemName: iconoRadar(radar.kind))
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(colorRadar(radar.kind))
                            .frame(width: 54, height: 54)
                            .background(colorRadar(radar.kind).opacity(0.15), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(radar.titulo)
                                .font(.system(size: 24, weight: .heavy))
                                .foregroundColor(Diseno.texto)
                            if let metros = radar.dist {
                                Text(metros < 1000 ? "A \(Int(metros.rounded())) m de ti" : String(format: "A %.1f km de ti", metros / 1000))
                                    .font(.disCuerpo.weight(.semibold))
                                    .foregroundColor(Diseno.acento)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .tarjeta()

                    VStack(alignment: .leading, spacing: 10) {
                        if let limite = radar.speed {
                            FilaDato("Límite", "\(Int(limite)) km/h", Diseno.peligro)
                        } else {
                            FilaDato("Límite", "sin límite conocido", Diseno.apagado)
                        }
                        if let sentido = radar.dir, sentido >= 0 {
                            FilaDato("Sentido de la marcha", "\(Int(sentido))°", Diseno.texto)
                        }
                        FilaDato("Fuente", radar.src == "user" ? "capturado por ti" : "base oficial", Diseno.apagado)
                        FilaDato("Coordenadas", String(format: "%.5f, %.5f", radar.lat, radar.lng), Diseno.apagado)
                    }
                    .tarjeta()

                    BotonApp(titulo: "Ir aquí", icono: "location.north.line.fill", tipo: .verde) {
                        Task {
                            let ubicacion = Ubicacion(
                                id: "radar-\(radar.id)",
                                name: radar.titulo,
                                address: "",
                                code: "",
                                notes: "",
                                lat: radar.lat,
                                lng: radar.lng,
                                categoryId: "",
                                tagIds: [],
                                pinned: false,
                                photos: []
                            )
                            await estado.elegirDestino(ubicacion)
                            cerrar()
                            irAlMapa()
                        }
                    }

                    if let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(radar.lat),\(radar.lng)") {
                        BotonApp(titulo: "Ver en Google Maps", icono: "globe", tipo: .fantasma) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .padding(16)
            }
            .fondoApp()
            .navigationTitle("Radar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Diseno.fondo, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { cerrar() }
                        .foregroundColor(Diseno.acento)
                }
            }
        }
    }

    private func iconoRadar(_ tipo: String?) -> String { iconoDeRadar(tipo) }

    private func colorRadar(_ tipo: String?) -> Color { colorDeRadar(tipo) }
}
