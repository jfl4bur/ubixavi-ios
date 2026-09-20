/* LA LISTA DE UBICACIONES (la pantalla principal de la app).

   Lo mismo que la web pero nativo: buscar, ordenar (A-Z, más cerca, fijadas), filtrar
   por categoría, ver la distancia, fijar y borrar con el dedo (deslizando la fila),
   abrir la ficha y añadir una nueva.
*/
import SwiftUI
import CoreLocation

struct PantallaUbicaciones: View {
    @ObservedObject var estado: Estado
    @ObservedObject var almacen: Almacen
    var irAlMapa: () -> Void

    @State private var consulta = ""
    @State private var orden: Orden = .nombre
    @State private var categoriaElegida: String?
    @State private var ficha: Ubicacion?
    @State private var editor: Ubicacion?
    @State private var creando = false
    @State private var borrando: Ubicacion?

    /// Ajustes de vista (los mismos que en Ajustes)
    @AppStorage("mostrarDireccion") private var mostrarDireccion = true
    @AppStorage("mostrarTiempoDistancia") private var mostrarTiempoDistancia = true
    @AppStorage("mostrarEtiquetas") private var mostrarEtiquetas = true

    /// Etiquetas elegidas para filtrar
    @State private var etiquetasElegidas: Set<String> = []
    /// ¿Está abierto el filtro de etiquetas? (lo abre el botón del tag)
    @State private var filtroEtiquetasAbierto = false

    enum Orden: String, CaseIterable, Identifiable {
        case nombre = "A-Z"
        case cerca = "Más cerca"
        case ultimas = "Últimas"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    cabecera
                    if !almacen.categorias.isEmpty { chipsCategorias }
                    if !almacen.etiquetas.isEmpty && (filtroEtiquetasAbierto || !etiquetasElegidas.isEmpty) { chipsEtiquetas }
                    if almacen.cargando && almacen.ubicaciones.isEmpty {
                        Spacer()
                        ProgressView("Cargando…").tint(Diseno.acento)
                        Spacer()
                    } else if filtradas.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "mappin.slash")
                                .font(.system(size: 40))
                                .foregroundColor(Diseno.apagado)
                            Text(almacen.ubicaciones.isEmpty ? "Todavía no hay ubicaciones" : "No hay ubicaciones que coincidan")
                                .font(.disSubtitulo)
                                .foregroundColor(Diseno.texto)
                                .multilineTextAlignment(.center)
                            Text(almacen.ubicaciones.isEmpty ? "Añade la primera con el botón dorado." : "Prueba a quitar el filtro o a buscar otra cosa.")
                                .font(.disSecundario)
                                .foregroundColor(Diseno.apagado)
                                .multilineTextAlignment(.center)
                            if almacen.ubicaciones.isEmpty {
                                BotonApp(titulo: "Añadir ubicación", icono: "plus", compacto: true) { creando = true }
                                    .frame(maxWidth: 240)
                            } else {
                                BotonApp(titulo: "Quitar filtros", icono: "xmark", tipo: .fantasma, compacto: true) {
                                    consulta = ""
                                    categoriaElegida = nil
                                    etiquetasElegidas = []
                                }
                                .frame(maxWidth: 240)
                            }
                        }
                        .padding(.horizontal, 30)
                        Spacer()
                    } else {
                        lista
                    }
                }
                // Cerrando las filas al tocar fuera (fuera de una fila abierta)
                .simultaneousGesture(
                    TapGesture().onEnded { FilasAbiertas.compartida.cerrarTodas() }
                )
                .cerrarFilasAlDesplazar()
                    .bloqueaScrollAlDeslizarFila()

                // EL BOTÓN DORADO de añadir, como el FAB de la web
                FabDorado(icono: "plus") { creando = true }
                    .padding(.trailing, 20)
                    .padding(.bottom, 18)
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(FondoMidnight())
            .toolbarBackground(Diseno.fondo, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("\(almacen.ubicaciones.count)")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundColor(Diseno.acento)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Ordenar", selection: $orden) {
                            ForEach(Orden.allCases) { opcion in
                                Text(opcion.rawValue).tag(opcion)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .tint(Diseno.acento)
                }
                if almacen.puedeDeshacer {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await almacen.deshacerBorrado() }
                        } label: {
                            Label("Deshacer", systemImage: "arrow.uturn.backward")
                        }
                        .tint(Diseno.naranja)
                    }
                }
            }
            .sheet(item: $ficha) { ubicacion in
                FichaUbicacion(
                    estado: estado,
                    almacen: almacen,
                    ubicacion: ubicacion,
                    irAlMapa: irAlMapa,
                    editar: { actual in
                        ficha = nil
                        editor = actual
                    }
                )
            }
            .sheet(item: $editor) { ubicacion in
                EditorUbicacion(almacen: almacen, original: ubicacion, cerrar: { editor = nil })
            }
            .sheet(isPresented: $creando) {
                EditorUbicacion(almacen: almacen, original: nil, cerrar: { creando = false })
            }
            .alert("¿Borrar «\(borrando?.name ?? "")»?", isPresented: Binding(
                get: { borrando != nil },
                set: { if !$0 { borrando = nil } }
            )) {
                Button("Cancelar", role: .cancel) { borrando = nil }
                Button("Borrar", role: .destructive) {
                    if let ubicacion = borrando {
                        Task { await almacen.borrarUbicacion(ubicacion) }
                    }
                    borrando = nil
                }
            } message: {
                Text("Se mueve a la Papelera: podrás recuperarla.")
            }
            .refreshable { await almacen.cargar() }
        }
    }

    // ── La cabecera con el logo, los contadores, el buscador y el filtro ─────
    private var cabecera: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Ubicaciones")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundColor(Diseno.acento)
                    HStack(spacing: 6) {
                        Pastilla(texto: "\(almacen.ubicaciones.count) sitios", color: Diseno.acento)
                        Pastilla(texto: "\(almacen.categorias.count) categorías", color: Diseno.verde)
                        Pastilla(texto: "\(almacen.rutas.count) rutas", color: Diseno.morado)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                buscador
                // El botón del filtro por etiquetas (como el de la web)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        filtroEtiquetasAbierto.toggle()
                    }
                } label: {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(filtroEtiquetasAbierto ? .black : Diseno.acento)
                        .frame(width: 46, height: 46)
                        .background(
                            filtroEtiquetasAbierto ? Diseno.acento : Diseno.fondoTarjeta,
                            in: RoundedRectangle(cornerRadius: Diseno.radioSm)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Diseno.radioSm)
                                .stroke(filtroEtiquetasAbierto ? .clear : Diseno.linea, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    // ── Buscador ─────────────────────────────────────────────────────────────
    private var buscador: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(Diseno.apagado)
            TextField("Buscar por nombre o dirección…", text: $consulta)
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

    // ── Filtro por categorías ────────────────────────────────────────────────
    private var chipsCategorias: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(texto: "Todas", color: Diseno.acento, activo: categoriaElegida == nil) {
                    categoriaElegida = nil
                }
                ForEach(almacen.categorias) { categoria in
                    Chip(texto: categoria.name, color: Color(hex: categoria.color), activo: categoriaElegida == categoria.id) {
                        categoriaElegida = categoriaElegida == categoria.id ? nil : categoria.id
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 10)
    }

    /// Filtro por ETIQUETAS (se pueden combinar varias)
    private var chipsEtiquetas: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(texto: "Sin filtro", color: Diseno.acento, activo: etiquetasElegidas.isEmpty) {
                    etiquetasElegidas = []
                }
                ForEach(almacen.etiquetas) { etiqueta in
                    Chip(texto: etiqueta.name, color: Color(hex: etiqueta.color), activo: etiquetasElegidas.contains(etiqueta.id)) {
                        if etiquetasElegidas.contains(etiqueta.id) {
                            etiquetasElegidas.remove(etiqueta.id)
                        } else {
                            etiquetasElegidas.insert(etiqueta.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 10)
    }

    // ── La lista ─────────────────────────────────────────────────────────────
    private var lista: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filtradas) { ubicacion in
                    FilaDeslizable(
                        izquierda: accionesIzquierda(ubicacion),
                        derecha: accionesDerecha(ubicacion),
                        alTocar: { ficha = ubicacion }
                    ) {
                        ContenidoFilaUbicacion(
                            ubicacion: ubicacion,
                            categoria: almacen.categoria(ubicacion.categoryId),
                            etiquetas: mostrarEtiquetas ? ubicacion.tagIds.compactMap { almacen.etiqueta($0) } : [],
                            distancia: almacen.distancia(ubicacion, desde: estado.posicion),
                            mostrarDireccion: mostrarDireccion,
                            mostrarTiempoDistancia: mostrarTiempoDistancia
                        )
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 20)
        }
    }

    private func accionesDerecha(_ ubicacion: Ubicacion) -> [AccionFila] {
        [
            AccionFila(titulo: ubicacion.pinned ? "Quitar" : "Fijar", icono: "pin.fill", color: Diseno.naranjaPin) {
                Task { await almacen.alternarFijada(ubicacion) }
            },
            AccionFila(titulo: "Borrar", icono: "trash.fill", color: Diseno.peligro) {
                borrando = ubicacion
            },
        ]
    }

    private func accionesIzquierda(_ ubicacion: Ubicacion) -> [AccionFila] {
        [
            AccionFila(titulo: "Ir", icono: "location.north.line.fill", color: Diseno.verde) {
                Task {
                    await estado.elegirDestino(ubicacion)
                    irAlMapa()
                }
            },
            AccionFila(titulo: "Añadir", icono: "plus", color: Diseno.acento) {
                Task { await estado.anadirParada(ubicacion) }
            },
        ]
    }

    private var filtradas: [Ubicacion] {
        let texto = consulta.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var base = almacen.ubicaciones
        if let categoria = categoriaElegida {
            base = base.filter { $0.categoryId == categoria }
        }
        if !texto.isEmpty {
            base = base.filter {
                "\($0.name) \($0.address) \($0.code) \($0.notes)".lowercased().contains(texto)
            }
        }
        if !etiquetasElegidas.isEmpty {
            base = base.filter { !etiquetasElegidas.isDisjoint(with: Set($0.tagIds)) }
        }
        /* LAS FIJADAS VAN SIEMPRE ARRIBA, con cualquier orden y con cualquier filtro: así no
           hay que cambiar de orden para encontrarlas (y se ha quitado el orden «Fijadas»).
           «Últimas» es por orden de creación: las nuevas se añaden al final del documento,
           así que se le da la vuelta (la última añadida, la primera). */
        switch orden {
        case .nombre:
            return ordenadasPorFijadas(base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        case .cerca:
            return ordenadasPorFijadas(base.sorted {
                let a = almacen.distancia($0, desde: estado.posicion) ?? .greatestFiniteMagnitude
                let b = almacen.distancia($1, desde: estado.posicion) ?? .greatestFiniteMagnitude
                return a < b
            })
        case .ultimas:
            return ordenadasPorFijadas(base.reversed())
        }
    }

    /// Las fijadas primero y, dentro de cada grupo, el orden que ya trae la lista
    private func ordenadasPorFijadas(_ lista: [Ubicacion]) -> [Ubicacion] {
        lista.filter { $0.pinned } + lista.filter { !$0.pinned }
    }
}
