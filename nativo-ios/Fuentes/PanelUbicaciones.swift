/* EL PANEL DE UBICACIONES, como el de Apple Maps (imágenes 2 y 3).

   · Sale desde abajo con el GUION arriba: se arrastra hacia abajo para cerrarlo.
   · Las CUATRO esquinas redondeadas y un poco de aire a los lados.
   · Arriba, el buscador.
   · Debajo, TRES SITIOS fijos (Casa, Trabajo y Añadir): se eligen una vez y quedan ahí.
   · Y «MIS UBICACIONES» con tu lista: al tocar una, se pone como destino.
   · Arrastrando el guion HACIA ARRIBA se expande (se ve la lista entera); hacia abajo, se
     encoge; y si lo tiras del todo, se cierra.
*/
import SwiftUI
import MapKit

struct PanelUbicaciones: View {
    @ObservedObject var estado: Estado
    @ObservedObject var almacen: Almacen
    var cerrar: () -> Void

    /// Los dos sitios fijos (se guardan por su identificador)
    @AppStorage("sitioCasa") private var casaId = ""
    @AppStorage("sitioTrabajo") private var trabajoId = ""

    @State private var consulta = ""
    /// Qué sitio se está eligiendo (Casa o Trabajo)
    @State private var eligiendoSitio: String?
    /// El filtro de búsqueda que está puesto
    @State private var filtro: FiltroBusqueda = .ubicaciones
    /// Los resultados de buscar en el MAPA (direcciones y puntos de interés, con MKLocalSearch)
    @State private var resultados: [ResultadoMapa] = []
    @State private var buscando = false
    /// Para que el teclado salga solo al abrir el panel
    @FocusState private var enElBuscador: Bool

    /// LOS TRES FILTROS DE BÚSQUEDA (como Apple Maps)
    enum FiltroBusqueda: String, CaseIterable {
        case ubicaciones = "Ubicaciones"
        case direcciones = "Direcciones"
        case interes = "Puntos de interés"
    }

    /// Un resultado que viene del mapa de Apple (dirección o punto de interés)
    struct ResultadoMapa: Identifiable {
        let id = UUID()
        let nombre: String
        let direccion: String
        let lat: Double
        let lng: Double
    }

    /// BUSCA EN EL MAPA (Apple): direcciones o puntos de interés, con MKLocalSearch
    private func buscarFuera() async {
        let texto = consulta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard filtro != .ubicaciones, texto.count >= 3 else {
            resultados = []
            return
        }
        buscando = true
        defer { buscando = false }
        let peticion = MKLocalSearch.Request()
        peticion.naturalLanguageQuery = texto
        peticion.resultTypes = filtro == .direcciones ? .address : .pointOfInterest
        // Se busca alrededor de donde estás (o de lo que estés mirando)
        if let pos = estado.posicion?.coordinate {
            peticion.region = MKCoordinateRegion(
                center: pos,
                span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
            )
        }
        guard let respuesta = try? await MKLocalSearch(request: peticion).start() else { return }
        resultados = respuesta.mapItems.prefix(25).compactMap { item in
            let coord = item.placemark.coordinate
            let nombre = item.name ?? "Sin nombre"
            let direccion = [item.placemark.thoroughfare, item.placemark.locality]
                .compactMap { $0 }
                .joined(separator: ", ")
            return ResultadoMapa(nombre: nombre, direccion: direccion, lat: coord.latitude, lng: coord.longitude)
        }
    }

    /// Ir a un resultado del mapa (se crea la parada con ese nombre y esas coordenadas)
    private func irA(_ resultado: ResultadoMapa) {
        let ubicacion = Ubicacion(
            id: "busqueda-\(resultado.lat)-\(resultado.lng)",
            name: resultado.nombre,
            address: resultado.direccion,
            code: "",
            notes: "",
            lat: resultado.lat,
            lng: resultado.lng,
            categoryId: "",
            tagIds: [],
            pinned: false,
            photos: []
        )
        Task {
            if estado.paradas.isEmpty {
                await estado.elegirDestino(ubicacion)
            } else {
                await estado.anadirParada(ubicacion)
            }
            cerrar()
        }
    }

    private let altoGrande: CGFloat = 700

    private var ubicaciones: [Ubicacion] {
        let texto = consulta.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = almacen.ubicaciones.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let lista = texto.isEmpty ? base : base.filter {
            "\($0.name) \($0.address) \($0.code)".lowercased().contains(texto)
        }
        return lista.filter { $0.pinned } + lista.filter { !$0.pinned }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── El buscador (con los TRES filtros) ──────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(Diseno.apagado)
                TextField("Buscar", text: $consulta)
                    .focused($enElBuscador)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(Diseno.texto)
                    .submitLabel(.search)
                    .onSubmit { Task { await buscarFuera() } }
                if !consulta.isEmpty {
                    Button { consulta = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(Diseno.apagado)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            // NEGRO TRANSPARENTE SIN DIFUMINADO: se ve el fondo por detrás
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: Diseno.radioSm))
            .overlay(RoundedRectangle(cornerRadius: Diseno.radioSm).stroke(Diseno.lineaFuerte, lineWidth: 1))
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            /* LOS TRES FILTROS DE BÚSQUEDA, como Apple Maps: tus ubicaciones, direcciones
               del mapa y puntos de interés (bares, tiendas, gasolineras…). */
            HStack(spacing: 8) {
                ForEach(FiltroBusqueda.allCases, id: \.self) { opcion in
                    Button {
                        filtro = opcion
                        Task { await buscarFuera() }
                    } label: {
                        Text(opcion.rawValue)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(filtro == opcion ? .black : Diseno.texto)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(filtro == opcion ? Diseno.acento : Color.white.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // ── SITIOS › (el título de la sección, como Apple Maps) ──
                    HStack(spacing: 6) {
                        Text("Sitios")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundColor(Diseno.texto)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Diseno.apagado)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)

                    // ── Los tres sitios (Casa / Trabajo / Añadir) ───────────
                    HStack(spacing: 12) {
                        botonDeSitio("Casa", icono: "house.fill", color: Diseno.azul, id: casaId, clave: "casa")
                        botonDeSitio("Trabajo", icono: "briefcase.fill", color: Diseno.naranja, id: trabajoId, clave: "trabajo")
                        Button {
                            eligiendoSitio = casaId.isEmpty ? "casa" : "trabajo"
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 29, weight: .bold))
                                    .foregroundColor(Diseno.acento)
                                    .frame(width: 70, height: 70)
                                    .background(Diseno.fondoTarjetaAlta, in: Circle())
                                    .overlay(Circle().stroke(Diseno.lineaFuerte, lineWidth: 1))
                                Text("Añadir")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Diseno.texto)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)

                    // ── Mis ubicaciones ─────────────────────────────────────
                    HStack(spacing: 6) {
                        Text("Mis ubicaciones")
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundColor(Diseno.texto)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Diseno.apagado)
                        Text("\(ubicaciones.count)")
                            .font(.disEtiqueta)
                            .foregroundColor(Diseno.apagado)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)

                    /* LOS RESULTADOS DEL MAPA (direcciones y puntos de interés, con el mapa
                       de Apple): se listan igual que los tuyos y al tocar uno se va allí. */
                    if filtro != .ubicaciones {
                        if buscando {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Buscando…").foregroundColor(Diseno.apagado)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                        } else if consulta.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 {
                            Text("Escribe al menos 3 letras para buscar en el mapa.")
                                .font(.disSecundario)
                                .foregroundColor(Diseno.apagado)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 16)
                        } else if resultados.isEmpty {
                            Text("Nada que coincida con «\(consulta)».")
                                .font(.disSecundario)
                                .foregroundColor(Diseno.apagado)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 16)
                        } else {
                            ForEach(resultados) { resultado in
                                Button {
                                    irA(resultado)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: filtro == .direcciones ? "signpost.right.fill" : "mappin.and.ellipse")
                                            .font(.system(size: 22))
                                            .foregroundColor(Diseno.acento)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(resultado.nombre)
                                                .font(.disCuerpo.weight(.semibold))
                                                .foregroundColor(Diseno.texto)
                                                .lineLimit(1)
                                            if !resultado.direccion.isEmpty {
                                                Text(resultado.direccion)
                                                    .font(.disEtiqueta)
                                                    .foregroundColor(Diseno.apagado)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "arrow.up.left")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(Diseno.acento)
                                    }
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 14)
                                    .background(Diseno.fondoFila, in: RoundedRectangle(cornerRadius: Diseno.radioSm))
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 14)
                            }
                        }
                    } else if ubicaciones.isEmpty {
                        Text("No hay ninguna ubicación que coincida.")
                            .font(.disSecundario)
                            .foregroundColor(Diseno.apagado)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(ubicaciones) { ubicacion in
                            Button {
                                Task {
                                    // Si ya hay un viaje, se AÑADE como parada; si no, es el destino
                                    if estado.paradas.isEmpty {
                                        await estado.elegirDestino(ubicacion)
                                    } else {
                                        await estado.anadirParada(ubicacion)
                                    }
                                    cerrar()
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 25))
                                        .foregroundColor(almacen.categoria(ubicacion.categoryId).map { Color(hex: $0.color) } ?? Diseno.acento)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ubicacion.name)
                                            .font(.disCuerpo.weight(.semibold))
                                            .foregroundColor(Diseno.texto)
                                            .lineLimit(1)
                                        if !ubicacion.address.isEmpty {
                                            Text(ubicacion.address)
                                                .font(.disEtiqueta)
                                                .foregroundColor(Diseno.apagado)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    if ubicacion.pinned {
                                        Image(systemName: "pin.fill")
                                            .font(.system(size: 13))
                                            .foregroundColor(Diseno.naranjaPin)
                                    }
                                    Image(systemName: "arrow.up.left")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(Diseno.acento)
                                }
                                .padding(.vertical, 14)
                                .padding(.horizontal, 12)
                                .background(Diseno.fondoFila, in: RoundedRectangle(cornerRadius: Diseno.radioSm))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 14)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
        /* El alto, el guion y el fondo los pone el PANEL NATIVO de iOS (el que se estira y
           se cierra con el dedo). Aquí sólo va el contenido. */
        .sheet(item: Binding(
            get: { eligiendoSitio.map { TextoIdentificable(id: $0, texto: $0) } },
            set: { if $0 == nil { eligiendoSitio = nil } }
        )) { cual in
            ElegirSitioFijo(almacen: almacen, cual: cual.id) { ubicacion in
                if cual.id == "casa" { casaId = ubicacion.id } else { trabajoId = ubicacion.id }
                eligiendoSitio = nil
            }
        }
    }

    // ── Un sitio fijo (Casa o Trabajo) ──────────────────────────────────────
    private func botonDeSitio(_ titulo: String, icono: String, color: Color, id: String, clave: String) -> some View {
        let ubicacion = id.isEmpty ? nil : almacen.ubicacion(id)
        return Button {
            if let ubicacion = ubicacion {
                Task {
                    await estado.elegirDestino(ubicacion)
                    cerrar()
                }
            } else {
                eligiendoSitio = clave
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: ubicacion == nil ? icono : "\(icono.dropLast(5)).fill")
                    .font(.system(size: 29, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 70, height: 70)
                    .background(color, in: Circle())
                Text(titulo)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Diseno.texto)
                Text(ubicacion?.name ?? "Sin elegir")
                    .font(.system(size: 13))
                    .foregroundColor(Diseno.apagado)
                    .lineLimit(1)
                    .frame(width: 104)
            }
        }
        .buttonStyle(.plain)
    }

}

/// Un texto con identificador (para los `sheet(item:)`)
struct TextoIdentificable: Identifiable {
    let id: String
    let texto: String
}

/// ELECCIÓN DE UN SITIO FIJO (Casa o Trabajo): se busca y se elige una ubicación
struct ElegirSitioFijo: View {
    @ObservedObject var almacen: Almacen
    let cual: String
    var alElegir: (Ubicacion) -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var consulta = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    buscador
                    ForEach(filtradas) { ubicacion in
                        Button {
                            alElegir(ubicacion)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundColor(Diseno.acento)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ubicacion.name)
                                        .font(.disCuerpo.weight(.semibold))
                                        .foregroundColor(Diseno.texto)
                                        .lineLimit(1)
                                    if !ubicacion.address.isEmpty {
                                        Text(ubicacion.address)
                                            .font(.disEtiqueta)
                                            .foregroundColor(Diseno.apagado)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 12)
                            .background(Diseno.fondoFila, in: RoundedRectangle(cornerRadius: Diseno.radioSm))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
            }
            .fondoApp()
            .navigationTitle(cual == "casa" ? "Elige tu Casa" : "Elige tu Trabajo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Diseno.fondo, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(Diseno.acento)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { cerrar() }
                }
            }
        }
    }

    private var buscador: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(Diseno.apagado)
            TextField("Buscar ubicación…", text: $consulta)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(Diseno.texto)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(Diseno.fondoTarjeta, in: RoundedRectangle(cornerRadius: Diseno.radioSm))
        .overlay(RoundedRectangle(cornerRadius: Diseno.radioSm).stroke(Diseno.linea, lineWidth: 0.5))
    }

    private var filtradas: [Ubicacion] {
        let texto = consulta.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = almacen.ubicaciones.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return texto.isEmpty ? base : base.filter { "\($0.name) \($0.address)".lowercased().contains(texto) }
    }
}
