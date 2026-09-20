/* LA FICHA DE UNA UBICACIÓN y el EDITOR (añadir / modificar).

   La ficha: foto de la calle, dirección, notas, categoría, etiquetas y los botones de
   siempre (navegar, llamar, copiar, compartir, abrir en Apple Maps, editar, borrar).
   El editor: todo lo que se puede cambiar, con «usar mi posición» y la dirección sacada
   del propio servidor (geocodificación inversa), como en la web.
*/
import SwiftUI
import MapKit
import UIKit

/* LA VISTA PREVIA DEL SITIO: un mapa pequeño y FIJO (no se puede mover ni acercar), el
   mismo papel que hace el mapa incrustado de la web debajo del resultado del enlace. */
struct MiniMapaFijo: UIViewRepresentable {
    let lat: Double
    let lng: Double

    func makeUIView(context: Context) -> MKMapView {
        let mapa = MKMapView(frame: .zero)
        mapa.isZoomEnabled = false
        mapa.isScrollEnabled = false
        mapa.isRotateEnabled = false
        mapa.isPitchEnabled = false
        mapa.isUserInteractionEnabled = false
        mapa.pointOfInterestFilter = .excludingAll
        mapa.overrideUserInterfaceStyle = .dark
        return mapa
    }

    func updateUIView(_ mapa: MKMapView, context: Context) {
        let centro = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        mapa.setRegion(
            MKCoordinateRegion(center: centro, latitudinalMeters: 320, longitudinalMeters: 320),
            animated: false
        )
        mapa.removeAnnotations(mapa.annotations)
        let pin = MKPointAnnotation()
        pin.coordinate = centro
        mapa.addAnnotation(pin)
    }
}

// ── La ficha ──────────────────────────────────────────────────────────────────
struct FichaUbicacion: View {
    @ObservedObject var estado: Estado
    @ObservedObject var almacen: Almacen
    let ubicacion: Ubicacion
    var irAlMapa: () -> Void
    var editar: (Ubicacion) -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var confirmarBorrado = false
    @State private var aviso: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // ── Fotos (todas, se pueden deslizar y abrir) ─────────────
                    if !ubicacion.photos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(ubicacion.photos.enumerated()), id: \.offset) { _, foto in
                                    if let url = foto.url, let enlace = URL(string: url) {
                                        Button {
                                            if let link = foto.link, let destino = URL(string: link) {
                                                UIApplication.shared.open(destino)
                                            } else {
                                                UIApplication.shared.open(enlace)
                                            }
                                        } label: {
                                            AsyncImage(url: enlace) { imagen in
                                                imagen.resizable().scaledToFill()
                                            } placeholder: {
                                                Rectangle().fill(Color.white.opacity(0.06))
                                            }
                                            .frame(width: 300, height: 200)
                                            .clipped()
                                            .cornerRadius(18)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.horizontal, -20)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(ubicacion.name)
                                .font(.system(size: 26, weight: .heavy))
                            if ubicacion.pinned {
                                Image(systemName: "pin.fill").foregroundColor(.orange)
                            }
                        }
                        if let categoria = almacen.categoria(ubicacion.categoryId) {
                            Text(categoria.name)
                                .font(.system(size: 13, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(hex: categoria.color).opacity(0.25), in: Capsule())
                                .foregroundColor(Color(hex: categoria.color))
                        }
                        if !ubicacion.address.isEmpty {
                            Text(ubicacion.address)
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                        }
                        if !ubicacion.tagIds.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(ubicacion.tagIds.compactMap { almacen.etiqueta($0) }) { etiqueta in
                                    Text(etiqueta.name)
                                        .font(.system(size: 12, weight: .bold))
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(Color(hex: etiqueta.color).opacity(0.25), in: Capsule())
                                        .foregroundColor(Color(hex: etiqueta.color))
                                }
                            }
                        }
                        if !ubicacion.notes.isEmpty {
                            Text(ubicacion.notes)
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                        }
                        if ubicacion.tieneCoordenadas {
                            Text(String(format: "%.5f, %.5f", ubicacion.lat, ubicacion.lng))
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        if let distancia = almacen.distancia(ubicacion, desde: estado.posicion) {
                            Label(
                                distancia < 1000
                                    ? "\(Int(distancia.rounded())) m de ti"
                                    : String(format: "%.1f km de ti", distancia / 1000),
                                systemImage: "location.fill"
                            )
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                        }
                    }

                    // ── Acciones ─────────────────────────────────────────────
                    VStack(spacing: 10) {
                        BotonFicha(titulo: "Ir aquí", icono: "location.north.line.fill", color: Color(red: 0.18, green: 0.76, blue: 0.49)) {
                            Task {
                                await estado.elegirDestino(ubicacion)
                                cerrar()
                                irAlMapa()
                            }
                        }
                        BotonFicha(titulo: "Abrir en Apple Maps", icono: "map", color: .blue) {
                            abrirEnAppleMaps()
                        }
                        if !ubicacion.address.isEmpty {
                            BotonFicha(titulo: "Copiar dirección", icono: "doc.on.doc", color: .gray) {
                                UIPasteboard.general.string = ubicacion.address
                                aviso = "Dirección copiada"
                            }
                        }
                        if let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(ubicacion.lat),\(ubicacion.lng)"),
                           ubicacion.tieneCoordenadas {
                            BotonFicha(titulo: "Ver en Google Maps", icono: "globe", color: .gray) {
                                UIApplication.shared.open(url)
                            }
                        }
                        BotonFicha(
                            titulo: ubicacion.pinned ? "Quitar de fijadas" : "Fijar arriba",
                            icono: ubicacion.pinned ? "pin.slash" : "pin",
                            color: .orange
                        ) {
                            Task {
                                await almacen.alternarFijada(ubicacion)
                                cerrar()
                            }
                        }

                        // Compartir: nombre + dirección + enlace al mapa
                        ShareLink(item: textoParaCompartir) {
                            Label("Compartir", systemImage: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 14)
                                .padding(.horizontal, 16)
                                .background(Color.blue.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.blue.opacity(0.5)))
                                .foregroundColor(.primary)
                        }

                        BotonFicha(titulo: "Editar", icono: "square.and.pencil", color: .gray) {
                            editar(ubicacion)
                        }
                        BotonFicha(titulo: "Borrar (a la papelera)", icono: "trash", color: .red) {
                            confirmarBorrado = true
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Ficha")
            .navigationBarTitleDisplayMode(.inline)
            .background(FondoMidnight())
            .toolbarBackground(Diseno.fondo, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { cerrar() }
                }
            }
            .alert("¿Borrar «\(ubicacion.name)»?", isPresented: $confirmarBorrado) {
                Button("Cancelar", role: .cancel) {}
                Button("Borrar", role: .destructive) {
                    Task {
                        await almacen.borrarUbicacion(ubicacion)
                        cerrar()
                    }
                }
            } message: {
                Text("Se mueve a la Papelera: podrás recuperarla.")
            }
            .alert(aviso ?? "", isPresented: Binding(
                get: { aviso != nil },
                set: { if !$0 { aviso = nil } }
            )) {
                Button("Vale") { aviso = nil }
            }
        }
    }

    /// Lo que se manda al compartir: nombre, dirección y enlace al mapa
    private var textoParaCompartir: String {
        var lineas = [ubicacion.name]
        if !ubicacion.address.isEmpty { lineas.append(ubicacion.address) }
        if ubicacion.tieneCoordenadas {
            lineas.append("https://www.google.com/maps/search/?api=1&query=\(ubicacion.lat),\(ubicacion.lng)")
        }
        return lineas.joined(separator: "\n")
    }

    private func abrirEnAppleMaps() {        var items: [URLQueryItem] = []
        if ubicacion.tieneCoordenadas {
            items.append(URLQueryItem(name: "ll", value: "\(ubicacion.lat),\(ubicacion.lng)"))
        }
        items.append(URLQueryItem(name: "q", value: ubicacion.name))
        var comp = URLComponents(string: "http://maps.apple.com/")!
        comp.queryItems = items
        if let url = comp.url { UIApplication.shared.open(url) }
    }
}

struct BotonFicha: View {
    let titulo: String
    let icono: String
    let color: Color
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 12) {
                Image(systemName: icono)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 30)
                Text(titulo)
                    .font(.system(size: 16.5, weight: .bold))
                    .foregroundColor(Diseno.texto)
                Spacer()
            }
            .padding(.vertical, 15)
            .padding(.horizontal, 16)
            .background(Diseno.fondoTarjeta, in: RoundedRectangle(cornerRadius: Diseno.radioSm))
            .overlay(RoundedRectangle(cornerRadius: Diseno.radioSm).stroke(color.opacity(0.35), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

/* UN PUNTO DE GPS Y YA: se pide la posición una vez y se devuelve. Lo usa el botón «poner
   mi posición actual» del editor, que no depende de la ubicación continua de la app. */
@MainActor
final class LocalizadorUnPunto: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var buscando = false
    private let gestor = CLLocationManager()
    private var alTener: ((CLLocationCoordinate2D) -> Void)?

    override init() {
        super.init()
        gestor.delegate = self
        gestor.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func pedir(_ completar: @escaping (CLLocationCoordinate2D) -> Void) {
        alTener = completar
        buscando = true
        gestor.requestWhenInUseAuthorization()
        gestor.requestLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordenada = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.buscando = false
            self.alTener?(coordenada)
            self.alTener = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.buscando = false }
    }
}

// ── Elegir el punto en el mapa (con la cruz en el centro) ─────────────────────
struct SelectorDePunto: View {
    @Environment(\.dismiss) private var cerrar
    @State private var region: MKCoordinateRegion
    var alElegir: (CLLocationCoordinate2D) -> Void

    init(inicial: CLLocationCoordinate2D?, alElegir: @escaping (CLLocationCoordinate2D) -> Void) {
        let centro = inicial ?? CLLocationCoordinate2D(latitude: 41.387, longitude: 2.17)
        _region = State(initialValue: MKCoordinateRegion(
            center: centro,
            latitudinalMeters: inicial == nil ? 6000 : 600,
            longitudinalMeters: inicial == nil ? 6000 : 600
        ))
        self.alElegir = alElegir
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Map(coordinateRegion: $region, interactionModes: .all)
                    .ignoresSafeArea(edges: .bottom)

                // La cruz: el punto que se va a elegir es el del centro
                VStack(spacing: 0) {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 12))
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 30, weight: .bold))
                }
                .foregroundColor(Diseno.peligro)
                .shadow(color: .black.opacity(0.6), radius: 3)
                .offset(y: -14)

                VStack {
                    Spacer()
                    Button {
                        alElegir(region.center)
                        cerrar()
                    } label: {
                        Label("Usar este punto", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 17, weight: .heavy))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Diseno.verde, in: RoundedRectangle(cornerRadius: Diseno.radioSm))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                }
            }
            .navigationTitle("Elegir el punto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { cerrar() }
                }
            }
        }
    }
}
// ── El editor (añadir y modificar) ────────────────────────────────────────────
struct EditorUbicacion: View {
    @ObservedObject var almacen: Almacen
    let original: Ubicacion?
    var cerrar: () -> Void

    @State private var borrador: Ubicacion = .nueva()
    @State private var buscandoDireccion = false
    @State private var buscandoFoto = false
    @State private var buscandoEnlace = false
    @State private var enlaceFoto = ""
    @State private var enlaceMapa = ""
    @State private var eligiendoEnMapa = false
    @State private var aviso: String?
    @State private var guardando = false
    /// Para «poner mi posición actual» sin depender del resto de la app
    @StateObject private var localizador = LocalizadorUnPunto()
    /// Lo que ha sacado el resolutor del enlace: se enseña en su tarjeta (como la web)
    @State private var lugarResuelto: Servidor.LugarResuelto?
    @State private var errorEnlace: String?

    private var esNueva: Bool { original == nil }

    var body: some View {
        NavigationStack {
            Form {
                seccionEnlace
                seccionDatos
                seccionSituacion
                seccionCategoria
                seccionEtiquetas
                seccionFotos
            }
            .navigationTitle(esNueva ? "Nueva ubicación" : "Editar ubicación")
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
            .sheet(isPresented: $eligiendoEnMapa) {
                SelectorDePunto(
                    inicial: borrador.tieneCoordenadas ? borrador.coordinate : nil,
                    alElegir: { coordenada in
                        borrador.lat = coordenada.latitude
                        borrador.lng = coordenada.longitude
                        Task { await sacarDireccion() }
                    }
                )
            }
            .onAppear {
                if let original = original { borrador = original }
            }
        }
    }

    // ── El bloque del enlace, arriba del todo (como la web) ─────────────────
    private var seccionEnlace: some View {
        Section {
            bloqueEnlaceMapa
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
        }
    }

    private var seccionDatos: some View {
        Section("Datos") {
            TextField("Nombre", text: $borrador.name)
            TextField("Dirección", text: $borrador.address, axis: .vertical)
                .lineLimit(1...4)
            TextField("Código / nota corta", text: $borrador.code)
            TextField("Notas", text: $borrador.notes, axis: .vertical)
                .lineLimit(1...6)
        }
    }

    private var seccionSituacion: some View {
        Section("Situación") {
            HStack {
                Text("Latitud")
                Spacer()
                TextField("0", value: $borrador.lat, format: .number.precision(.fractionLength(0...6)))
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text("Longitud")
                Spacer()
                TextField("0", value: $borrador.lng, format: .number.precision(.fractionLength(0...6)))
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
            }
            Button {
                eligiendoEnMapa = true
            } label: {
                Label("Elegir el punto en el mapa", systemImage: "map")
            }
            Button {
                localizador.pedir { coordenada in
                    borrador.lat = coordenada.latitude
                    borrador.lng = coordenada.longitude
                }
            } label: {
                Label(
                    localizador.buscando ? "Buscando tu posición…" : "Poner mi posición actual",
                    systemImage: "location.fill"
                )
            }
            .disabled(localizador.buscando)
            Button {
                Task { await sacarDireccion() }
            } label: {
                Label(
                    buscandoDireccion ? "Buscando la dirección…" : "Sacar la dirección de estas coordenadas",
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .disabled(buscandoDireccion || (borrador.lat == 0 && borrador.lng == 0))
        }
    }

    @ViewBuilder private var seccionCategoria: some View {
        Section("Categoría") {
            Picker("Categoría", selection: $borrador.categoryId) {
                Text("Sin categoría").tag("")
                ForEach(almacen.categorias) { categoria in
                    Text(categoria.name).tag(categoria.id)
                }
            }
        }
    }

    @ViewBuilder private var seccionEtiquetas: some View {
        if !almacen.etiquetas.isEmpty {
            Section("Etiquetas") {
                ForEach(almacen.etiquetas) { etiqueta in
                    Button {
                        alternarEtiqueta(etiqueta.id)
                    } label: {
                        HStack {
                            Text(etiqueta.name).foregroundColor(.primary)
                            Spacer()
                            if borrador.tagIds.contains(etiqueta.id) {
                                Image(systemName: "checkmark").foregroundColor(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var seccionFotos: some View {
        Section("Foto de la calle") {
            if let foto = borrador.photos.first, let url = foto.url, let enlace = URL(string: url) {
                AsyncImage(url: enlace) { imagen in
                    imagen.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Color.white.opacity(0.06))
                }
                .frame(height: 150)
                .clipped()
                .cornerRadius(12)
            }
            Button {
                Task { await sacarFoto() }
            } label: {
                Label(buscandoFoto ? "Buscando la foto…" : "Buscar la foto de la calle", systemImage: "camera.fill")
            }
            .disabled(buscandoFoto)
        }

        Section {
            TextField("Pega un enlace (Telegram, web…)", text: $enlaceFoto)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button {
                Task { await resolverFoto() }
            } label: {
                Label("Añadir la foto de ese enlace", systemImage: "link")
            }
            .disabled(buscandoFoto || enlaceFoto.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("Foto por enlace")
        } footer: {
            Text("Se resuelve el enlace en el servidor (los enlaces de Telegram son páginas, no fotos).")
        }
    }

    private func alternarEtiqueta(_ id: String) {
        if let indice = borrador.tagIds.firstIndex(of: id) {
            borrador.tagIds.remove(at: indice)
        } else {
            borrador.tagIds.append(id)
        }
    }

    private func sacarDireccion() async {
        buscandoDireccion = true
        defer { buscandoDireccion = false }
        do {
            let direccion = try await Servidor.direccion(lat: borrador.lat, lng: borrador.lng)
            if let texto = direccion.address ?? direccion.display_name {
                borrador.address = texto
                if borrador.name.trimmingCharacters(in: .whitespaces).isEmpty, let nombre = direccion.name {
                    borrador.name = nombre
                }
            } else {
                aviso = "No encontré la dirección de ese punto"
            }
        } catch {
            aviso = "No pude sacar la dirección: \(error.localizedDescription)"
        }
    }

    private func sacarFoto() async {
        buscandoFoto = true
        defer { buscandoFoto = false }
        do {
            let pano = try await Servidor.panoramica(lat: borrador.lat, lng: borrador.lng)
            guard pano.available == true, let imagen = pano.imageUrl else {
                aviso = "No hay foto de la calle en ese punto"
                return
            }
            borrador.photos = [
                Foto(
                    id: "ph-sv-\(Int(Date().timeIntervalSince1970 * 1000))",
                    type: "streetview",
                    url: imagen,
                    link: pano.link,
                    label: pano.address.map { "Street View · \($0)" } ?? "Street View"
                )
            ]
        } catch {
            aviso = "No pude buscar la foto: \(error.localizedDescription)"
        }
    }

    private func resolverFoto() async {
        buscandoFoto = true
        defer { buscandoFoto = false }
        let enlace = enlaceFoto.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let resuelta = try await Servidor.resolverFoto(enlace)
            guard let url = resuelta.url, resuelta.isImage == true else {
                aviso = "Ese enlace no es una foto"
                return
            }
            borrador.photos.append(
                Foto(
                    id: "ph-\(Int(Date().timeIntervalSince1970 * 1000))",
                    type: "enlace",
                    url: url,
                    link: enlace,
                    label: "Foto"
                )
            )
            enlaceFoto = ""
            AvisosFlotantes.compartido.bien("Foto añadida")
        } catch {
            aviso = "No pude resolver el enlace: \(error.localizedDescription)"
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // AÑADIR DESDE UN ENLACE DE GOOGLE MAPS (el bloque de la web, tal cual)
    // ══════════════════════════════════════════════════════════════════════════
    /* La web lo pone LO PRIMERO del formulario, con su título, su barra de pegar y
       resolver, y su tarjeta de resultado con la vista previa del mapa y el aviso de
       «coordenadas exactas / aproximadas». Aquí es igual. */
    private var bloqueEnlaceMapa: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("🔗")
                    .font(.system(size: 18))
                Text("Añadir desde enlace de Google Maps")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundColor(Diseno.texto)
            }

            HStack(spacing: 8) {
                TextField("Pega el enlace o la dirección… https://maps.app.goo.gl/…", text: $enlaceMapa)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .foregroundColor(Diseno.texto)
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(Diseno.fondoTarjetaAlta, in: RoundedRectangle(cornerRadius: Diseno.radioSm))
                    .overlay(RoundedRectangle(cornerRadius: Diseno.radioSm).stroke(Diseno.lineaFuerte, lineWidth: 1))
                    .disabled(buscandoEnlace)

                BotonApp(
                    titulo: buscandoEnlace ? "…" : "Resolver",
                    icono: buscandoEnlace ? nil : "link",
                    tipo: .principal,
                    compacto: true
                ) {
                    Task { await resolverEnlaceMapa() }
                }
                .frame(width: 140)
                .disabled(buscandoEnlace || enlaceMapa.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let error = errorEnlace {
                Text(error)
                    .font(.disEtiqueta.weight(.semibold))
                    .foregroundColor(Diseno.peligro)
            }

            if let lugar = lugarResuelto, let lat = lugar.lat, let lng = lugar.lng {
                VStack(alignment: .leading, spacing: 8) {
                    Text(lugar.name?.isEmpty == false ? lugar.name! : "Ubicación")
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundColor(Diseno.texto)
                    if let direccion = lugar.address, !direccion.isEmpty {
                        Text(direccion)
                            .font(.disSecundario)
                            .foregroundColor(Diseno.apagado)
                    }
                    Text("📍 \(String(format: "%.5f", lat)), \(String(format: "%.5f", lng)) · \(esExacta(lugar) ? "✅ exacta" : "⚠️ aproximada")")
                        .font(.disEtiqueta.weight(.semibold))
                        .foregroundColor(esExacta(lugar) ? Diseno.verde : Diseno.naranja)

                    // La vista previa del sitio (como el mapa incrustado de la web)
                    MiniMapaFijo(lat: lat, lng: lng)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: Diseno.radioSm))
                        .overlay(RoundedRectangle(cornerRadius: Diseno.radioSm).stroke(Diseno.lineaFuerte, lineWidth: 1))

                    Text(
                        esExacta(lugar)
                            ? "Coordenadas exactas de Google Maps. Si quieres, ajusta el pin."
                            : "Coordenadas aproximadas: comprueba el pin y ajústalo si no es el sitio."
                    )
                    .font(.disEtiqueta)
                    .foregroundColor(Diseno.apagado)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Diseno.fondoTarjetaAlta, in: RoundedRectangle(cornerRadius: Diseno.radioSm))
                .overlay(RoundedRectangle(cornerRadius: Diseno.radioSm).stroke(Diseno.lineaFuerte, lineWidth: 1))
            }
        }
        .padding(.vertical, 6)
    }

    /// Las coordenadas que vienen de Google (pin, sitio o URL) son exactas; el resto, no
    private func esExacta(_ lugar: Servidor.LugarResuelto) -> Bool {
        let fuente = lugar.source ?? ""
        return fuente == "google-place" || fuente == "url-pin" || fuente == "url-coords" || fuente.hasPrefix("url-pin")
    }

    private func resolverEnlaceMapa() async {
        buscandoEnlace = true
        defer { buscandoEnlace = false }
        let enlace = enlaceMapa.trimmingCharacters(in: .whitespacesAndNewlines)
        errorEnlace = nil
        lugarResuelto = nil
        do {
            let lugar = try await Servidor.resolverEnlace(enlace)
            guard let lat = lugar.lat, let lng = lugar.lng else {
                errorEnlace = lugar.error ?? "No pude sacar la ubicación de ese enlace"
                return
            }
            borrador.lat = lat
            borrador.lng = lng
            if let nombre = lugar.name, !nombre.isEmpty { borrador.name = nombre }
            if let direccion = lugar.address, !direccion.isEmpty {
                borrador.address = direccion
            } else {
                /* Si el enlace no traía dirección, se saca de las coordenadas: es lo que
                   hace la web (geocodificación inversa inmediata). */
                if let sacada = try? await Servidor.direccion(lat: lat, lng: lng) {
                    if let direccion = sacada.address, !direccion.isEmpty { borrador.address = direccion }
                    if borrador.name.isEmpty, let nombre = sacada.name, !nombre.isEmpty {
                        borrador.name = nombre
                    }
                }
            }
            lugarResuelto = lugar
            AvisosFlotantes.compartido.bien("Ubicación sacada del enlace")
        } catch {
            errorEnlace = "No pude resolver el enlace: \(error.localizedDescription)"
        }
    }

    private func guardar() async {
        guardando = true
        defer { guardando = false }
        var aGuardar = borrador
        aGuardar.name = aGuardar.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if esNueva {
            await almacen.anadirUbicacion(aGuardar)
        } else {
            await almacen.actualizarUbicacion(aGuardar)
        }
        cerrar()
    }
}
