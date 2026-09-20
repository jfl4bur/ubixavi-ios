/* AJUSTES: categorías, etiquetas, papelera, vista, radares y estado de la sincronización.

   Todo lo que se cambia aquí o se guarda en el servidor (categorías, etiquetas, papelera)
   o en el propio móvil (vista y avisos), igual que hacía la web.
*/
import SwiftUI
import UIKit

struct PantallaAjustes: View {
    @ObservedObject var almacen: Almacen
    @ObservedObject var estado: Estado
    /// Para saltar a la pestaña del mapa al arrancar la DEMO
    var irAlMapa: (() -> Void)? = nil

    /// La versión de verdad de esta compilación (la pone el compilador)
    static var versionDeLaApp: String {
        let info = Bundle.main.infoDictionary
        let corta = info?["CFBundleShortVersionString"] as? String ?? "2.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(corta) (\($0))" } ?? corta
    }

    @AppStorage("avisosRadares") private var avisosRadares = true
    @AppStorage("capturarRadaresSiempre") private var capturarSiempre = false
    @AppStorage("mostrarTiempoDistancia") private var mostrarTiempoDistancia = true
    @AppStorage("mostrarDireccion") private var mostrarDireccion = true
    @AppStorage("mostrarEtiquetas") private var mostrarEtiquetas = true
    @AppStorage("avisosFlotantes") private var avisosFlotantes = true
    @AppStorage("modoOscuro") private var modoOscuro = true

    @State private var nuevaCategoria = ""
    @State private var colorCategoria = "#5b7cfa"
    @State private var nuevaEtiqueta = ""
    @State private var colorEtiqueta = "#a78bfa"
    @State private var papeleraAbierta = false
    @State private var recargando = false
    @State private var copiado = false
    @State private var categoriaEditando: Categoria?
    @State private var etiquetaEditando: Etiqueta?
    @State private var estadisticasAbiertas = false
    @State private var diagnosticoAbierto = false
    @State private var importarAbierto = false

    /// Tamaño de letra de toda la app (0 = el del sistema)
    @AppStorage("tamanoLetra") private var tamanoLetra = 1

    // ── Las capas del mapa y el color de la ruta (las mismas que el botón del mapa) ──
    @AppStorage("mapaUbicaciones") private var verUbicaciones = true
    @AppStorage("mapaRadares") private var verRadares = true
    @AppStorage("mapaPuntosInteres") private var verPuntosInteres = false
    @AppStorage("mapaTrafico") private var verTrafico = false
    @AppStorage("mapaEdificios") private var verEdificios = false
    @AppStorage("mapaApagado") private var mapaApagado = false
    @AppStorage("mapaSatelite") private var mapaSatelite = false
    /// Evitar peajes al calcular las rutas
    @AppStorage("evitarPeajes") private var evitarPeajes = false
    @AppStorage("colorRuta") private var colorRuta = "#d4a843"

    /// Los colores que se pueden elegir de un toque para la ruta
    static let coloresDeRuta = [
        "#d4a843", // el dorado de la app
        "#2e85fa", // el azul de siempre
        "#32d74b", // verde
        "#ff9f0a", // naranja
        "#bf5af2", // morado
        "#ff375f", // rosa
        "#00d4c8", // turquesa
        "#ffffff", // blanco
    ]

    private func fila(_ titulo: String, _ valor: String) -> some View {
        HStack {
            Text(titulo)
            Spacer()
            Text(valor).foregroundColor(.secondary)
        }
    }

    private func cuentaCategoria(_ categoria: Categoria) -> Int {
        almacen.ubicaciones.filter { $0.categoryId == categoria.id }.count
    }

    private func exportar() {
        UIPasteboard.general.string = almacen.documentoJSON()
        copiado = true
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── Vista ────────────────────────────────────────────────────
                Section {
                    Toggle("Modo oscuro", isOn: $modoOscuro)
                    Picker("Tamaño de letra", selection: $tamanoLetra) {
                        Text("Sistema").tag(0)
                        Text("Grande").tag(1)
                        Text("Muy grande").tag(2)
                        Text("Gigante").tag(3)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Mostrar tiempo y distancia", isOn: $mostrarTiempoDistancia)
                    Toggle("Mostrar la dirección en las listas", isOn: $mostrarDireccion)
                    Toggle("Mostrar las etiquetas", isOn: $mostrarEtiquetas)
                    Toggle("Avisos flotantes (los cartelitos)", isOn: $avisosFlotantes)
                } header: {
                    Text("Vista")
                } footer: {
                    Text("El tamaño de letra se aplica a toda la app (también puedes usar el del sistema, en Ajustes de iOS).")
                }

                // ── El mapa: las capas y el color de la ruta ─────────────────
                Section {
                    Toggle("Ver mis ubicaciones", isOn: $verUbicaciones)
                    Toggle("Ver los radares", isOn: $verRadares)
                    Toggle("Ver los puntos de interés (bares, tiendas…)", isOn: $verPuntosInteres)
                    Toggle("Ver el tráfico", isOn: $verTrafico)
                    Toggle("Edificios en 3D", isOn: $verEdificios)
                    Toggle("Mapa apagado (resalta la ruta)", isOn: $mapaApagado)
                    Toggle("Mapa de satélite", isOn: $mapaSatelite)
                    Toggle("Evitar peajes en las rutas", isOn: $evitarPeajes)
                } header: {
                    Text("Capas del mapa")
                } footer: {
                    Text("Lo mismo que el botón de capas del mapa: aquí queda guardado.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Color de la ruta")
                            .font(.disCuerpo.weight(.semibold))
                            .foregroundColor(Diseno.texto)
                        HStack(spacing: 10) {
                            ForEach(PantallaAjustes.coloresDeRuta, id: \.self) { hex in
                                Button {
                                    colorRuta = hex
                                } label: {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 34, height: 34)
                                        .overlay(
                                            Circle().stroke(
                                                colorRuta.uppercased() == hex.uppercased() ? Color.white : Color.white.opacity(0.2),
                                                lineWidth: colorRuta.uppercased() == hex.uppercased() ? 3 : 1
                                            )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        HStack(spacing: 8) {
                            Text("Otro:")
                                .font(.disEtiqueta)
                                .foregroundColor(Diseno.apagado)
                            TextField("#RRGGBB", text: $colorRuta)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .font(.system(size: 15, design: .monospaced))
                                .foregroundColor(Diseno.texto)
                                .frame(width: 110)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(hex: colorRuta))
                                .frame(width: 44, height: 26)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Diseno.lineaFuerte))
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("La ruta")
                } footer: {
                    Text("La ruta que llevas va de este color, con el borde blanco; las alternativas, en azul.")
                }

                // ── Radares ──────────────────────────────────────────────────
                Section {
                    Toggle("Avisos de radar (voz y pitidos)", isOn: $avisosRadares)
                    Toggle("Botón de capturar radares siempre a la vista", isOn: $capturarSiempre)
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
                            irAlMapa?()
                        }
                    } label: {
                        Label(
                            estado.demoActiva ? "Parar la demo" : "DEMO completa: conduce sola hasta un radar",
                            systemImage: estado.demoActiva ? "stop.circle.fill" : "play.circle.fill"
                        )
                    }
                    .tint(estado.demoActiva ? Diseno.peligro : Diseno.acento)
                } header: {
                    Text("Radares")
                } footer: {
                    Text("Los avisos salen por los altavoces del coche si está conectado. Con el botón a la vista puedes capturar un radar de un toque desde el mapa. La DEMO conduce sola hacia un radar de mentira 1,6 km al norte: verás el mapa moverse, tu punto y el velocímetro, y el aviso con voz y pitidos cuando toca.")
                }

                // ── Sincronización ───────────────────────────────────────────
                Section {
                    HStack {
                        Text("Última sincronización")
                        Spacer()
                        Text(almacen.ultimaCarga.map { hora($0) } ?? "—")
                            .foregroundColor(.secondary)
                    }
                    if let fallo = almacen.fallo {
                        Text(fallo)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }
                    Button {
                        Task {
                            recargando = true
                            await almacen.cargar()
                            recargando = false
                        }
                    } label: {
                        Label(recargando ? "Cargando…" : "Cargar del servidor", systemImage: "arrow.clockwise")
                    }
                    .disabled(recargando || almacen.cargando)
                } header: {
                    Text("Datos")
                } footer: {
                    Text("\(almacen.ubicaciones.count) ubicaciones · \(almacen.categorias.count) categorías · \(almacen.etiquetas.count) etiquetas · \(almacen.rutas.count) rutas · \(almacen.papelera.count) en la papelera")
                }

                // ── Categorías ───────────────────────────────────────────────
                Section {
                    ForEach(almacen.categorias) { categoria in
                        Button {
                            categoriaEditando = categoria
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(hex: categoria.color))
                                    .frame(width: 18, height: 18)
                                Text(categoria.name)
                                    .font(.disCuerpo)
                                    .foregroundColor(Diseno.texto)
                                Spacer()
                                Text("\(cuentaCategoria(categoria))")
                                    .foregroundColor(Diseno.apagado)
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(Diseno.apagado)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(spacing: 8) {
                        TextField("Nueva categoría", text: $nuevaCategoria)
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: colorCategoria) },
                            set: { colorCategoria = hex($0) }
                        ))
                        .labelsHidden()
                        Button {
                            let nombre = nuevaCategoria.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !nombre.isEmpty else { return }
                            nuevaCategoria = ""
                            Task { await almacen.anadirCategoria(nombre: nombre, color: colorCategoria) }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(nuevaCategoria.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Categorías")
                } footer: {
                    Text("Toca una categoría para cambiarle el nombre o el color.")
                }

                // ── Etiquetas ────────────────────────────────────────────────
                Section {
                    ForEach(almacen.etiquetas) { etiqueta in
                        Button {
                            etiquetaEditando = etiqueta
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(hex: etiqueta.color))
                                    .frame(width: 18, height: 18)
                                Text(etiqueta.name)
                                    .font(.disCuerpo)
                                    .foregroundColor(Diseno.texto)
                                Spacer()
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(Diseno.apagado)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(spacing: 8) {
                        TextField("Nueva etiqueta", text: $nuevaEtiqueta)
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: colorEtiqueta) },
                            set: { colorEtiqueta = hex($0) }
                        ))
                        .labelsHidden()
                        Button {
                            let nombre = nuevaEtiqueta.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !nombre.isEmpty else { return }
                            nuevaEtiqueta = ""
                            Task { await almacen.anadirEtiqueta(nombre: nombre, color: colorEtiqueta) }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(nuevaEtiqueta.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Etiquetas")
                } footer: {
                    Text("Toca una etiqueta para cambiarle el nombre o el color.")
                }

                // ── Papelera ─────────────────────────────────────────────────
                Section {
                    Button {
                        papeleraAbierta = true
                    } label: {
                        HStack {
                            Label("Papelera", systemImage: "trash")
                            Spacer()
                            Text("\(almacen.papelera.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // ── Datos: estadísticas, diagnóstico, importar y copia ───────
                Section {
                    Button {
                        estadisticasAbiertas = true
                    } label: {
                        Label("Estadísticas", systemImage: "chart.bar.fill")
                    }
                    Button {
                        diagnosticoAbierto = true
                    } label: {
                        Label("Diagnóstico", systemImage: "stethoscope")
                    }
                    Button {
                        importarAbierto = true
                    } label: {
                        Label("Importar datos (pegar una copia)", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        exportar()
                    } label: {
                        Label("Copiar TODOS los datos (JSON)", systemImage: "doc.on.clipboard")
                    }
                } header: {
                    Text("Datos")
                } footer: {
                    Text("\(almacen.ubicaciones.count) ubicaciones · \(almacen.categorias.count) categorías · \(almacen.etiquetas.count) etiquetas · \(almacen.rutas.count) rutas · \(almacen.papelera.count) en la papelera")
                }

                // ── Acerca de ────────────────────────────────────────────────
                Section("Acerca de") {
                    HStack {
                        Text("Versión")
                        Spacer()
                        // El número lo pone el compilador en cada tanda: así se sabe
                        // exactamente qué compilación tienes instalada
                        Text(PantallaAjustes.versionDeLaApp)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Servidor")
                        Spacer()
                        Text("ubixavi.duckdns.org")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    Text("Mapa: MapKit de Apple (gratis, sin claves). Rutas: OSRM por tu servidor. Voz: la de iOS.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Ajustes")
            .background(FondoMidnight())
            .toolbarBackground(Diseno.fondo, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(Diseno.acento)
            .scrollContentBackground(.hidden)
            .sheet(isPresented: $papeleraAbierta) {
                PantallaPapelera(almacen: almacen)
            }
            .sheet(item: $categoriaEditando) { categoria in
                EditarCategoria(almacen: almacen, categoria: categoria, cerrar: { categoriaEditando = nil })
            }
            .sheet(item: $etiquetaEditando) { etiqueta in
                EditarEtiqueta(almacen: almacen, etiqueta: etiqueta, cerrar: { etiquetaEditando = nil })
            }
            .sheet(isPresented: $estadisticasAbiertas) {
                PantallaEstadisticas(almacen: almacen)
            }
            .sheet(isPresented: $diagnosticoAbierto) {
                PantallaDiagnostico(almacen: almacen, estado: estado)
            }
            .sheet(isPresented: $importarAbierto) {
                PantallaImportar(almacen: almacen)
            }
            .alert("Datos copiados", isPresented: $copiado) {
                Button("Vale") {}
            } message: {
                Text("Tienes todo el JSON en el portapapeles: puedes pegarlo donde quieras como copia de seguridad.")
            }
        }
    }

    private func hora(_ fecha: Date) -> String {
        let formato = DateFormatter()
        formato.dateFormat = "HH:mm:ss"
        return formato.string(from: fecha)
    }

    private func hex(_ color: Color) -> String {
        let componentes = UIColor(color).cgColor.components ?? [0.5, 0.5, 0.5]
        let r = Int((componentes.count > 0 ? componentes[0] : 0.5) * 255)
        let g = Int((componentes.count > 1 ? componentes[1] : 0.5) * 255)
        let b = Int((componentes.count > 2 ? componentes[2] : 0.5) * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}

// ── Editar una categoría (nombre y color) ─────────────────────────────────────
struct EditarCategoria: View {
    @ObservedObject var almacen: Almacen
    let categoria: Categoria
    var cerrar: () -> Void

    @State private var nombre = ""
    @State private var color = "#5b7cfa"
    @State private var borrando = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("Categoría", text: $nombre)
                }
                Section("Color") {
                    ColorPicker("Color de la categoría", selection: Binding(
                        get: { Color(hex: color) },
                        set: { color = hex($0) }
                    ))
                    HStack {
                        Spacer()
                        Pastilla(texto: nombre.isEmpty ? "Categoría" : nombre, color: Color(hex: color))
                        Spacer()
                    }
                }
                Section {
                    Button(role: .destructive) {
                        borrando = true
                    } label: {
                        Label("Borrar la categoría", systemImage: "trash")
                    }
                } footer: {
                    Text("Las ubicaciones que la tuvieran se quedan sin categoría (no se borran).")
                }
            }
            .navigationTitle("Editar categoría")
            .scrollContentBackground(.hidden)
            .background(FondoMidnight())
            .toolbarBackground(Diseno.fondo, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(Diseno.acento)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { cerrar() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        Task {
                            var copia = categoria
                            copia.name = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
                            copia.color = color
                            await almacen.actualizarCategoria(copia)
                            cerrar()
                        }
                    }
                    .disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("¿Borrar «\(categoria.name)»?", isPresented: $borrando) {
                Button("Cancelar", role: .cancel) {}
                Button("Borrar", role: .destructive) {
                    Task {
                        await almacen.borrarCategoria(categoria)
                        cerrar()
                    }
                }
            }
            .onAppear {
                nombre = categoria.name
                color = categoria.color
            }
        }
    }

    private func hex(_ valor: Color) -> String {
        let componentes = UIColor(valor).cgColor.components ?? [0.5, 0.5, 0.5]
        let r = Int((componentes.count > 0 ? componentes[0] : 0.5) * 255)
        let g = Int((componentes.count > 1 ? componentes[1] : 0.5) * 255)
        let b = Int((componentes.count > 2 ? componentes[2] : 0.5) * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}

// ── Editar una etiqueta ───────────────────────────────────────────────────────
struct EditarEtiqueta: View {
    @ObservedObject var almacen: Almacen
    let etiqueta: Etiqueta
    var cerrar: () -> Void

    @State private var nombre = ""
    @State private var color = "#a78bfa"
    @State private var borrando = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("Etiqueta", text: $nombre)
                }
                Section("Color") {
                    ColorPicker("Color de la etiqueta", selection: Binding(
                        get: { Color(hex: color) },
                        set: { color = hex($0) }
                    ))
                    HStack {
                        Spacer()
                        Pastilla(texto: nombre.isEmpty ? "Etiqueta" : nombre, color: Color(hex: color))
                        Spacer()
                    }
                }
                Section {
                    Button(role: .destructive) {
                        borrando = true
                    } label: {
                        Label("Borrar la etiqueta", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Editar etiqueta")
            .scrollContentBackground(.hidden)
            .background(FondoMidnight())
            .toolbarBackground(Diseno.fondo, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(Diseno.acento)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { cerrar() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        Task {
                            var copia = etiqueta
                            copia.name = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
                            copia.color = color
                            await almacen.actualizarEtiqueta(copia)
                            cerrar()
                        }
                    }
                    .disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("¿Borrar «\(etiqueta.name)»?", isPresented: $borrando) {
                Button("Cancelar", role: .cancel) {}
                Button("Borrar", role: .destructive) {
                    Task {
                        await almacen.borrarEtiqueta(etiqueta)
                        cerrar()
                    }
                }
            }
            .onAppear {
                nombre = etiqueta.name
                color = etiqueta.color
            }
        }
    }

    private func hex(_ valor: Color) -> String {
        let componentes = UIColor(valor).cgColor.components ?? [0.5, 0.5, 0.5]
        let r = Int((componentes.count > 0 ? componentes[0] : 0.5) * 255)
        let g = Int((componentes.count > 1 ? componentes[1] : 0.5) * 255)
        let b = Int((componentes.count > 2 ? componentes[2] : 0.5) * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}

// ── La papelera ───────────────────────────────────────────────────────────────
struct PantallaPapelera: View {
    @ObservedObject var almacen: Almacen
    @Environment(\.dismiss) private var cerrar
    @State private var vaciando = false

    var body: some View {
        NavigationStack {
            Group {
                if almacen.papelera.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "trash")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("La papelera está vacía").foregroundColor(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(almacen.papelera) { elemento in
                                FilaDeslizable(
                                    izquierda: [
                                        AccionFila(titulo: "Recuperar", icono: "arrow.uturn.backward", color: Diseno.verde) {
                                            Task {
                                                if elemento.type == "radar" {
                                                    // Un radar se recupera volviendo a capturarlo en su sitio
                                                    if await almacen.restaurarRadarDeLaPapelera(elemento) {
                                                        AvisosFlotantes.compartido.bien("Radar recuperado")
                                                    } else {
                                                        AvisosFlotantes.compartido.mal("No pude recuperar el radar")
                                                    }
                                                } else {
                                                    await almacen.restaurar(elemento)
                                                }
                                            }
                                        }
                                    ],
                                    derecha: [
                                        AccionFila(titulo: "Borrar", icono: "trash.slash.fill", color: Diseno.peligro) {
                                            Task { await almacen.borrarDelTodo(elemento) }
                                        }
                                    ]
                                ) {
                                    ContenidoFilaGenerica(
                                        titulo: elemento.name,
                                        subtitulo: "Borrado el \(fecha(elemento.deletedAt))",
                                        icono: elemento.type == "radar" ? "camera.fill" : "mappin.circle.fill",
                                        colorIcono: Diseno.apagado,
                                        chips: [(textoDeCaducidad(elemento), colorDeCaducidad(elemento))]
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 20)
                    }
                    .simultaneousGesture(TapGesture().onEnded { FilasAbiertas.compartida.cerrarTodas() })
                    .cerrarFilasAlDesplazar()
                    .bloqueaScrollAlDeslizarFila()
                }
            }
            .navigationTitle("Papelera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { cerrar() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Vaciar") { vaciando = true }
                        .disabled(almacen.papelera.isEmpty)
                }
            }
            .alert("¿Vaciar la papelera?", isPresented: $vaciando) {
                Button("Cancelar", role: .cancel) {}
                Button("Vaciar", role: .destructive) {
                    Task { await almacen.vaciarPapelera() }
                }
            } message: {
                Text("Se borrarán \(almacen.papelera.count) elementos para siempre.")
            }
        }
    }

    private func fecha(_ milisegundos: Double) -> String {
        let formato = DateFormatter()
        formato.dateFormat = "dd/MM/yyyy HH:mm"
        return formato.string(from: Date(timeIntervalSince1970: milisegundos / 1000))
    }

    /* CUÁNTOS DÍAS LE QUEDAN ANTES DE BORRARSE SOLO
       (la papelera se vacía sola al mes, igual que en la web) */
    private static let diasEnLaPapelera = 30.0

    private func diasQueQuedan(_ elemento: Basura) -> Int {
        let borrado = Date(timeIntervalSince1970: elemento.deletedAt / 1000)
        let seVa = borrado.addingTimeInterval(PantallaPapelera.diasEnLaPapelera * 24 * 3600)
        let dias = Calendar.current.dateComponents([.day], from: Date(), to: seVa).day ?? 0
        return max(0, dias)
    }

    private func textoDeCaducidad(_ elemento: Basura) -> String {
        let dias = diasQueQuedan(elemento)
        if dias <= 0 { return "se borra hoy" }
        if dias == 1 { return "queda 1 día" }
        return "quedan \(dias) días"
    }

    private func colorDeCaducidad(_ elemento: Basura) -> Color {
        let dias = diasQueQuedan(elemento)
        if dias <= 3 { return Diseno.peligro }
        if dias <= 10 { return Diseno.naranja }
        return Diseno.apagado
    }
}
