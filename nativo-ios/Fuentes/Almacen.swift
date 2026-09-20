/* EL ALMACÉN: los datos de la app y su sincronización con el servidor.

   Los datos son LOS MISMOS que los de la web (el fichero compartido del servidor):
     GET /api/data   -> { locations, categories, lists, tags, trash }
     PUT /api/data   -> se guarda el documento entero

   IMPORTANTE (para no romper nada): al guardar se mantiene el documento CRUDO que se
   leyó y sólo se cambian las claves que se tocan. Así no se pierde ningún campo que la
   app no conozca (hay fotos, rutas, ajustes…).
*/
import Foundation
import Combine
import CoreLocation

// ── Modelos ───────────────────────────────────────────────────────────────────
struct Foto: Codable, Hashable {
    var id: String?
    var type: String?
    var url: String?
    var link: String?
    var label: String?
}

struct Ubicacion: Identifiable, Hashable {
    var id: String
    var name: String
    var address: String
    var code: String
    var notes: String
    var lat: Double
    var lng: Double
    var categoryId: String
    var tagIds: [String]
    var pinned: Bool
    var photos: [Foto]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var tieneCoordenadas: Bool { lat != 0 || lng != 0 }

    static func nueva() -> Ubicacion {
        Ubicacion(
            id: "loc-\(Int(Date().timeIntervalSince1970 * 1000))",
            name: "",
            address: "",
            code: "",
            notes: "",
            lat: 0,
            lng: 0,
            categoryId: "",
            tagIds: [],
            pinned: false,
            photos: []
        )
    }
}

struct Categoria: Identifiable, Hashable {
    var id: String
    var name: String
    var color: String
}

struct Etiqueta: Identifiable, Hashable {
    var id: String
    var name: String
    var color: String
}

struct RutaGuardada: Identifiable, Hashable {
    var id: String
    var name: String
    var locationIds: [String]
    /// Fijada arriba del todo (como en la web)
    var pinned: Bool = false
}

struct Basura: Identifiable, Hashable {
    var id: String
    var type: String // "location" | "radar"
    var name: String
    var deletedAt: Double
}

// ── Ayudas para convertir de JSON a modelos y al revés ────────────────────────
private func texto(_ valor: Any?) -> String {
    if let s = valor as? String { return s }
    return ""
}

private func numero(_ valor: Any?) -> Double {
    if let d = valor as? Double { return d }
    if let i = valor as? Int { return Double(i) }
    if let n = valor as? NSNumber { return n.doubleValue }
    return 0
}

private func booleano(_ valor: Any?) -> Bool {
    if let b = valor as? Bool { return b }
    if let n = valor as? NSNumber { return n.boolValue }
    return false
}

func ubicacionDesde(_ dict: [String: Any]) -> Ubicacion {
    let fotosCrudas = (dict["photos"] as? [[String: Any]]) ?? []
    let fotos = fotosCrudas.map { f in
        Foto(
            id: f["id"] as? String,
            type: f["type"] as? String,
            url: f["url"] as? String,
            link: f["link"] as? String,
            label: f["label"] as? String
        )
    }
    return Ubicacion(
        id: texto(dict["id"]),
        name: texto(dict["name"]),
        address: texto(dict["address"]),
        code: texto(dict["code"]),
        notes: texto(dict["notes"]),
        lat: numero(dict["lat"]),
        lng: numero(dict["lng"]),
        categoryId: texto(dict["categoryId"]),
        tagIds: (dict["tagIds"] as? [String]) ?? [],
        pinned: booleano(dict["pinned"]),
        photos: fotos
    )
}

func diccionario(de ubicacion: Ubicacion) -> [String: Any] {
    [
        "id": ubicacion.id,
        "name": ubicacion.name,
        "address": ubicacion.address,
        "code": ubicacion.code,
        "notes": ubicacion.notes,
        "lat": ubicacion.lat,
        "lng": ubicacion.lng,
        "categoryId": ubicacion.categoryId,
        "tagIds": ubicacion.tagIds,
        "pinned": ubicacion.pinned,
        "photos": ubicacion.photos.map { foto -> [String: Any] in
            var d: [String: Any] = [:]
            if let id = foto.id { d["id"] = id }
            if let type = foto.type { d["type"] = type }
            if let url = foto.url { d["url"] = url }
            if let link = foto.link { d["link"] = link }
            if let label = foto.label { d["label"] = label }
            return d
        },
    ]
}

func colorDeHex(_ hex: String) -> (Double, Double, Double) {
    var limpio = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if limpio.hasPrefix("#") { limpio.removeFirst() }
    guard limpio.count == 6, let valor = UInt32(limpio, radix: 16) else { return (0.5, 0.5, 0.5) }
    return (
        Double((valor & 0xFF0000) >> 16) / 255.0,
        Double((valor & 0x00FF00) >> 8) / 255.0,
        Double(valor & 0x0000FF) / 255.0
    )
}

// ── El almacén ────────────────────────────────────────────────────────────────
@MainActor
final class Almacen: ObservableObject {
    @Published var ubicaciones: [Ubicacion] = []
    @Published var categorias: [Categoria] = []
    @Published var etiquetas: [Etiqueta] = []
    @Published var rutas: [RutaGuardada] = []
    @Published var papelera: [Basura] = []
    @Published var cargando = false
    @Published var guardando = false
    @Published var fallo: String?
    @Published var ultimaCarga: Date?
    /// ¿Se puede deshacer el último borrado? (la web tiene «Deshacer»)
    @Published var puedeDeshacer = false
    private var ultimaBorrada: (ubicacion: Ubicacion, indice: Int)?

    /// El documento tal cual se leyó del servidor: al guardar sólo se cambian las claves
    /// que se tocan, así no se pierde nada de lo que la app no conoce.
    private var crudo: [String: Any] = [:]
    /* SEGURO ANTI-BORRADO: hasta que no se hayan leído los datos del servidor NO se
       guarda nada. Si no, con la carga a medias (por ejemplo sin cobertura) un guardado
       subiría un documento vacío y se llevaría por delante todas tus ubicaciones. */
    private var cargado = false

    // ── Leer ─────────────────────────────────────────────────────────────────
    func cargar() async {
        cargando = true
        defer { cargando = false }
        do {
            let datos = try await Servidor.documento()
            crudo = datos
            ubicaciones = ((datos["locations"] as? [[String: Any]]) ?? []).map(ubicacionDesde)
            categorias = ((datos["categories"] as? [[String: Any]]) ?? []).map {
                Categoria(id: texto($0["id"]), name: texto($0["name"]), color: texto($0["color"]))
            }
            etiquetas = ((datos["tags"] as? [[String: Any]]) ?? []).map {
                Etiqueta(id: texto($0["id"]), name: texto($0["name"]), color: texto($0["color"]))
            }
            rutas = ((datos["lists"] as? [[String: Any]]) ?? []).map {
                RutaGuardada(
                    id: texto($0["id"]),
                    name: texto($0["name"]),
                    locationIds: ($0["locationIds"] as? [String]) ?? [],
                    pinned: booleano($0["pinned"])
                )
            }
            papelera = ((datos["trash"] as? [[String: Any]]) ?? []).map {
                Basura(
                    id: texto($0["id"]),
                    type: texto($0["type"]),
                    name: texto($0["name"]),
                    deletedAt: numero($0["deletedAt"])
                )
            }
            ultimaCarga = Date()
            cargado = true
            fallo = nil
        } catch {
            fallo = "No pude leer los datos: \(error.localizedDescription)"
        }
    }

    // ── Guardar ──────────────────────────────────────────────────────────────
    func guardar() async {
        guard cargado else {
            let texto = "No se guarda nada todavía: primero hay que leer los datos del servidor (así no se borra nada)."
            fallo = texto
            AvisosFlotantes.compartido.mal(texto)
            return
        }
        guardando = true
        defer { guardando = false }
        do {
            try await Servidor.guardarDocumento(crudo)
            ultimaCarga = Date()
            fallo = nil
        } catch {
            fallo = "No pude guardar: \(error.localizedDescription)"
            AvisosFlotantes.compartido.mal(fallo ?? "No pude guardar")
        }
    }

    // ── Ubicaciones ──────────────────────────────────────────────────────────
    func anadirUbicacion(_ ubicacion: Ubicacion) async {
        var lista = (crudo["locations"] as? [[String: Any]]) ?? []
        lista.append(diccionario(de: ubicacion))
        crudo["locations"] = lista
        ubicaciones.append(ubicacion)
        AvisosFlotantes.compartido.bien("Ubicación añadida: \(ubicacion.name)")
        await guardar()
    }

    func actualizarUbicacion(_ ubicacion: Ubicacion) async {
        var lista = (crudo["locations"] as? [[String: Any]]) ?? []
        if let indice = lista.firstIndex(where: { texto($0["id"]) == ubicacion.id }) {
            lista[indice] = diccionario(de: ubicacion)
        } else {
            lista.append(diccionario(de: ubicacion))
        }
        crudo["locations"] = lista
        if let indice = ubicaciones.firstIndex(where: { $0.id == ubicacion.id }) {
            ubicaciones[indice] = ubicacion
        }
        AvisosFlotantes.compartido.bien("Guardado: \(ubicacion.name)")
        await guardar()
    }

    /// A la PAPELERA (se puede recuperar), como en la web
    func borrarUbicacion(_ ubicacion: Ubicacion) async {
        var lista = (crudo["locations"] as? [[String: Any]]) ?? []
        guard let indice = lista.firstIndex(where: { texto($0["id"]) == ubicacion.id }) else { return }
        let datos = lista.remove(at: indice)
        crudo["locations"] = lista
        ubicaciones.removeAll { $0.id == ubicacion.id }

        var basura = (crudo["trash"] as? [[String: Any]]) ?? []
        let idBasura = "trash-\(Int(Date().timeIntervalSince1970 * 1000))-\(Int.random(in: 1000...9999))"
        basura.append([
            "id": idBasura,
            "type": "location",
            "name": ubicacion.name,
            "deletedAt": Int(Date().timeIntervalSince1970 * 1000),
            "data": datos,
        ])
        crudo["trash"] = basura
        papelera.append(
            Basura(id: idBasura, type: "location", name: ubicacion.name, deletedAt: Date().timeIntervalSince1970 * 1000)
        )
        AvisosFlotantes.compartido.info("«\(ubicacion.name)» a la Papelera")
        ultimaBorrada = (ubicacion, indice)
        puedeDeshacer = true
        await guardar()
    }

    /// UN RADAR BORRADO VA A LA PAPELERA (antes se perdía para siempre)
    /* El radar se guarda en la papelera con todos sus datos (tipo, posición, límite, rol,
       sentido y confirmaciones), así se puede RESTAURAR: al recuperarlo se vuelve a capturar
       en el mismo sitio con `POST /api/radars/user`. */
    func radarALaPapelera(_ radar: Servidor.RadarPropio) async {
        var basura = (crudo["trash"] as? [[String: Any]]) ?? []
        let idBasura = "trash-\(Int(Date().timeIntervalSince1970 * 1000))-\(Int.random(in: 1000...9999))"
        var datos: [String: Any] = [
            "id": "radar-\(radar.id)",
            "type": radar.type ?? "fixed",
            "lat": radar.lat,
            "lng": radar.lng,
            "src": "user",
        ]
        if let velocidad = radar.speed { datos["speed"] = velocidad }
        if let rol = radar.role { datos["role"] = rol }
        if let sentido = radar.dir { datos["dir"] = sentido }
        basura.append([
            "id": idBasura,
            "type": "radar",
            "name": tipoTexto(radar.type),
            "deletedAt": Int(Date().timeIntervalSince1970 * 1000),
            "data": datos,
        ])
        crudo["trash"] = basura
        papelera.append(
            Basura(
                id: idBasura,
                type: "radar",
                name: tipoTexto(radar.type),
                deletedAt: Date().timeIntervalSince1970 * 1000
            )
        )
        await guardar()
    }

    /// Restaurar un radar de la papelera: se vuelve a capturar en su sitio
    func restaurarRadar(_ datos: [String: Any]) async -> Bool {
        guard let lat = datos["lat"] as? Double, let lng = datos["lng"] as? Double else { return false }
        let tipo = (datos["type"] as? String) ?? "fixed"
        let velocidad = datos["speed"] as? Double
        let rol = datos["role"] as? String
        let sentido = datos["dir"] as? Double
        let resultado = try? await Servidor.capturarRadar(
            type: tipo,
            lat: lat,
            lng: lng,
            speed: velocidad,
            role: rol,
            dir: sentido
        )
        return resultado?.ok == true
    }

    /// Restaurar un radar de la papelera: se vuelve a capturar en su sitio
    func restaurarRadarDeLaPapelera(_ elemento: Basura) async -> Bool {
        var basura = (crudo["trash"] as? [[String: Any]]) ?? []
        guard let indice = basura.firstIndex(where: { texto($0["id"]) == elemento.id }),
              let datos = basura[indice]["data"] as? [String: Any] else { return false }
        guard await restaurarRadar(datos) else { return false }
        basura.remove(at: indice)
        crudo["trash"] = basura
        papelera.removeAll { $0.id == elemento.id }
        await guardar()
        return true
    }

    /// DESHACER el último borrado: la ubicación vuelve a su sitio (y sale de la papelera)
    func deshacerBorrado() async {
        guard let ultimo = ultimaBorrada else { return }
        var basura = (crudo["trash"] as? [[String: Any]]) ?? []
        guard let posicionBasura = basura.lastIndex(where: {
            texto($0["type"]) == "location" &&
            texto((($0["data"] as? [String: Any])?["id"])) == ultimo.ubicacion.id
        }) else {
            puedeDeshacer = false
            ultimaBorrada = nil
            AvisosFlotantes.compartido.mal("Ya no se puede deshacer")
            return
        }
        let entrada = basura.remove(at: posicionBasura)
        crudo["trash"] = basura
        // (papelera es una lista de Basura, no de diccionarios: se compara por id)
        let idEntrada = texto(entrada["id"])
        papelera.removeAll { $0.id == idEntrada }

        if let datos = entrada["data"] as? [String: Any] {
            var lista = (crudo["locations"] as? [[String: Any]]) ?? []
            let indice = min(max(ultimo.indice, 0), lista.count)
            lista.insert(datos, at: indice)
            crudo["locations"] = lista
            ubicaciones.insert(ubicacionDesde(datos), at: min(indice, ubicaciones.count))
        }
        ultimaBorrada = nil
        puedeDeshacer = false
        AvisosFlotantes.compartido.bien("Deshecho: «\(ultimo.ubicacion.name)» vuelve a su sitio")
        await guardar()
    }

    func alternarFijada(_ ubicacion: Ubicacion) async {
        var copia = ubicacion
        copia.pinned.toggle()
        await actualizarUbicacion(copia)
    }

    // ── Categorías y etiquetas ───────────────────────────────────────────────
    func anadirCategoria(nombre: String, color: String) async {
        let nueva = Categoria(id: "cat-\(Int(Date().timeIntervalSince1970 * 1000))", name: nombre, color: color)
        var lista = (crudo["categories"] as? [[String: Any]]) ?? []
        lista.append(["id": nueva.id, "name": nueva.name, "color": nueva.color])
        crudo["categories"] = lista
        categorias.append(nueva)
        AvisosFlotantes.compartido.bien("Categoría creada: \(nombre)")
        await guardar()
    }

    func actualizarCategoria(_ categoria: Categoria) async {
        var lista = (crudo["categories"] as? [[String: Any]]) ?? []
        if let indice = lista.firstIndex(where: { texto($0["id"]) == categoria.id }) {
            lista[indice] = ["id": categoria.id, "name": categoria.name, "color": categoria.color]
        }
        crudo["categories"] = lista
        if let indice = categorias.firstIndex(where: { $0.id == categoria.id }) {
            categorias[indice] = categoria
        }
        AvisosFlotantes.compartido.bien("Categoría guardada: \(categoria.name)")
        await guardar()
    }

    func borrarCategoria(_ categoria: Categoria) async {
        var lista = (crudo["categories"] as? [[String: Any]]) ?? []
        lista.removeAll { texto($0["id"]) == categoria.id }
        crudo["categories"] = lista
        categorias.removeAll { $0.id == categoria.id }
        AvisosFlotantes.compartido.info("Categoría borrada: \(categoria.name)")
        await guardar()
    }

    func anadirEtiqueta(nombre: String, color: String) async {
        let nueva = Etiqueta(id: "tag-\(Int(Date().timeIntervalSince1970 * 1000))", name: nombre, color: color)
        var lista = (crudo["tags"] as? [[String: Any]]) ?? []
        lista.append(["id": nueva.id, "name": nueva.name, "color": nueva.color])
        crudo["tags"] = lista
        etiquetas.append(nueva)
        AvisosFlotantes.compartido.bien("Etiqueta creada: \(nombre)")
        await guardar()
    }

    func actualizarEtiqueta(_ etiqueta: Etiqueta) async {
        var lista = (crudo["tags"] as? [[String: Any]]) ?? []
        if let indice = lista.firstIndex(where: { texto($0["id"]) == etiqueta.id }) {
            lista[indice] = ["id": etiqueta.id, "name": etiqueta.name, "color": etiqueta.color]
        }
        crudo["tags"] = lista
        if let indice = etiquetas.firstIndex(where: { $0.id == etiqueta.id }) {
            etiquetas[indice] = etiqueta
        }
        await guardar()
    }

    func borrarEtiqueta(_ etiqueta: Etiqueta) async {
        var lista = (crudo["tags"] as? [[String: Any]]) ?? []
        lista.removeAll { texto($0["id"]) == etiqueta.id }
        crudo["tags"] = lista
        etiquetas.removeAll { $0.id == etiqueta.id }
        await guardar()
    }

    // ── Rutas guardadas ──────────────────────────────────────────────────────
    /// Guarda el viaje actual como una ruta de verdad (aparece en la pestaña Rutas y en
    /// la web, porque va al mismo documento)
    func guardarRuta(nombre: String, locationIds: [String]) async -> RutaGuardada {
        let nueva = RutaGuardada(
            id: "list-\(Int(Date().timeIntervalSince1970 * 1000))",
            name: nombre,
            locationIds: locationIds
        )
        var lista = (crudo["lists"] as? [[String: Any]]) ?? []
        var dict: [String: Any] = ["id": nueva.id, "name": nueva.name]
        dict["locationIds"] = nueva.locationIds
        lista.append(dict)
        crudo["lists"] = lista
        rutas.append(nueva)
        AvisosFlotantes.compartido.bien("Ruta guardada: \(nueva.name)")
        await guardar()
        return nueva
    }

    /// Cambiar el orden de las paradas de una ruta (se guarda en el servidor)
    /* Se cambia SÓLO el orden dentro del JSON de siempre: así no se pierde nada de lo
       que haya puesto la web en esa ruta (la chincheta de fijada, por ejemplo). */
    func actualizarRuta(_ ruta: RutaGuardada) async {
        var lista = (crudo["lists"] as? [[String: Any]]) ?? []
        if let indice = lista.firstIndex(where: { texto($0["id"]) == ruta.id }) {
            var dict = lista[indice]
            dict["name"] = ruta.name
            dict["locationIds"] = ruta.locationIds
            dict["pinned"] = ruta.pinned
            lista[indice] = dict
        }
        crudo["lists"] = lista
        if let indice = rutas.firstIndex(where: { $0.id == ruta.id }) {
            rutas[indice] = ruta
        }
        AvisosFlotantes.compartido.bien("Ruta actualizada")
        await guardar()
    }

    /// Fijar o desfijar una ruta arriba del todo (como la chincheta de la web)
    func fijarRuta(_ ruta: RutaGuardada) async {
        var copia = ruta
        copia.pinned.toggle()
        await actualizarRuta(copia)
    }

    /* ORDENAR LAS RUTAS A MANO (arrastrando de las rayitas)
       Se guarda el orden en el MISMO documento (la posición dentro de `lists`), con las
       fijadas siempre delante, igual que hace la web al soltar. */
    func moverRutas(de origen: IndexSet, a destino: Int, visibles: [RutaGuardada]) async {
        var orden = visibles
        orden.move(fromOffsets: origen, toOffset: destino)
        // Las fijadas primero (no pierden su sitio de arriba) y después el resto
        let fijadas = orden.filter { $0.pinned }.map { $0.id }
        let resto = orden.filter { !$0.pinned }.map { $0.id }
        await guardarOrdenDeRutas(fijadas + resto)
    }

    /// Ordenar todas las rutas por nombre (A-Z o Z-A), con las fijadas delante
    func ordenarRutas(ascendente: Bool) async {
        let ordenadas = rutas.sorted {
            ascendente
                ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending
        }
        let fijadas = ordenadas.filter { $0.pinned }.map { $0.id }
        let resto = ordenadas.filter { !$0.pinned }.map { $0.id }
        await guardarOrdenDeRutas(fijadas + resto)
    }

    /// Guarda el orden de las rutas en el documento (y en la lista local)
    private func guardarOrdenDeRutas(_ ids: [String]) async {
        var lista = (crudo["lists"] as? [[String: Any]]) ?? []
        var porId: [String: [String: Any]] = [:]
        for dict in lista {
            let id = texto(dict["id"])
            if !id.isEmpty { porId[id] = dict }
        }
        lista = ids.compactMap { porId[$0] }
        crudo["lists"] = lista
        rutas = ids.compactMap { id in rutas.first { $0.id == id } }
        await guardar()
    }

    func borrarRuta(_ ruta: RutaGuardada) async {
        var lista = (crudo["lists"] as? [[String: Any]]) ?? []
        lista.removeAll { texto($0["id"]) == ruta.id }
        crudo["lists"] = lista
        rutas.removeAll { $0.id == ruta.id }
        await guardar()
    }

    // ── Papelera ─────────────────────────────────────────────────────────────
    func restaurar(_ elemento: Basura) async {
        var basura = (crudo["trash"] as? [[String: Any]]) ?? []
        guard let indice = basura.firstIndex(where: { texto($0["id"]) == elemento.id }) else { return }
        let entrada = basura.remove(at: indice)
        crudo["trash"] = basura
        papelera.removeAll { $0.id == elemento.id }

        if elemento.type == "location", let datos = entrada["data"] as? [String: Any] {
            var lista = (crudo["locations"] as? [[String: Any]]) ?? []
            lista.append(datos)
            crudo["locations"] = lista
            ubicaciones.append(ubicacionDesde(datos))
        }
        await guardar()
    }

    func borrarDelTodo(_ elemento: Basura) async {
        var basura = (crudo["trash"] as? [[String: Any]]) ?? []
        basura.removeAll { texto($0["id"]) == elemento.id }
        crudo["trash"] = basura
        papelera.removeAll { $0.id == elemento.id }
        await guardar()
    }

    func vaciarPapelera() async {
        crudo["trash"] = []
        papelera = []
        await guardar()
    }

    // ── Ayudas para la interfaz ──────────────────────────────────────────────
    /* EL RESPALDO EN EL SERVIDOR: los ajustes y el viaje se guardan TAMBIÉN en el mismo
       documento del servidor (bajo la clave «nativo»). Así, si desinstalas la app o la
       actualizas y el iPhone se lleva por delante sus datos, al volver a abrirla se
       recuperan solos. Es lo que pediste: «si la cierro y la abro, y al actualizarla
       también, que se acuerde». */
    var respaldo: [String: Any] { (crudo["nativo"] as? [String: Any]) ?? [:] }

    /// Guarda los ajustes y el viaje en el servidor (junto a las ubicaciones)
    func guardarRespaldo(ajustes: [String: Any], viaje: [String: Any]) async {
        crudo["nativo"] = [
            "ajustes": ajustes,
            "viaje": viaje,
            "actualizado": Date().timeIntervalSince1970 * 1000,
        ]
        await guardar()
    }

    /// ¿Es la primera vez que se abre la app después de instalarla o actualizarla?
    var esPrimeraVez: Bool {
        get { !UserDefaults.standard.bool(forKey: "ubixavi_nativo_ya_abierta") }
        set { UserDefaults.standard.set(!newValue, forKey: "ubixavi_nativo_ya_abierta") }
    }

    /// El viaje guardado en el servidor (para recuperarlo si el móvil ya no lo tiene)
    var viajeDelRespaldo: [String: Any] {
        (respaldo["viaje"] as? [String: Any]) ?? [:]
    }

    /// Los ajustes guardados en el servidor: se copian a este móvil SÓLO si no los tiene
    func restaurarAjustesDelRespaldo() {
        guard let ajustes = respaldo["ajustes"] as? [String: Any], !ajustes.isEmpty else { return }
        for (clave, valor) in ajustes {
            // Si este móvil ya tiene ese ajuste, manda el suyo
            if UserDefaults.standard.object(forKey: clave) == nil {
                UserDefaults.standard.set(valor, forKey: clave)
            }
        }
    }

    /// Los ajustes de este móvil, para mandarlos al servidor
    static func ajustesLocales() -> [String: Any] {
        let claves = [
            "modoOscuro", "tamanoLetra", "mostrarTiempoDistancia", "mostrarDireccion",
            "mostrarEtiquetas", "avisosFlotantes", "avisosRadares", "soloRadaresEnRuta",
            "capturarRadaresSiempre", "pestanaElegida", "mapaUbicaciones", "mapaRadares",
            "mapaPuntosInteres", "colorRuta", "evitarPeajes", "mapaTrafico", "mapaEdificios", "mapaApagado", "mapaSatelite",
        ]
        var datos: [String: Any] = [:]
        for clave in claves {
            if let valor = UserDefaults.standard.object(forKey: clave) { datos[clave] = valor }
        }
        return datos
    }

    /// Importa un documento JSON completo (una copia de seguridad pegada en Ajustes)
    @discardableResult
    func importar(_ texto: String) async -> Bool {
        guard let datos = texto.data(using: .utf8),
              let objeto = try? JSONSerialization.jsonObject(with: datos),
              let documento = objeto as? [String: Any],
              documento["locations"] != nil else {
            AvisosFlotantes.compartido.mal("Ese texto no es una copia válida (no encuentro «locations»)")
            return false
        }
        crudo = documento
        cargado = true
        await guardar()
        await cargar()
        let cuantas = ((documento["locations"] as? [[String: Any]]) ?? []).count
        AvisosFlotantes.compartido.bien("Importado: \(cuantas) ubicaciones")
        return true
    }

    /// Todo el documento en texto (para copia de seguridad desde Ajustes)
    func documentoJSON() -> String {
        guard let datos = try? JSONSerialization.data(withJSONObject: crudo, options: [.prettyPrinted, .sortedKeys]),
              let texto = String(data: datos, encoding: .utf8) else { return "{}" }
        return texto
    }

    func categoria(_ id: String) -> Categoria? {
        categorias.first { $0.id == id }
    }

    func etiqueta(_ id: String) -> Etiqueta? {
        etiquetas.first { $0.id == id }
    }

    func ubicacion(_ id: String) -> Ubicacion? {
        ubicaciones.first { $0.id == id }
    }

    func distancia(_ ubicacion: Ubicacion, desde posicion: CLLocation?) -> CLLocationDistance? {
        guard let posicion = posicion, ubicacion.tieneCoordenadas else { return nil }
        return CLLocation(latitude: ubicacion.lat, longitude: ubicacion.lng).distance(from: posicion)
    }
}
