/* LO QUE HABLA CON EL SERVIDOR (el mismo de siempre: ubixavi.duckdns.org).

   La app es NATIVA, pero los datos siguen siendo los mismos: las ubicaciones que
   gestionas en la web, los radares y las rutas. Así no hay dos bases de datos que
   mantener y sigues editando desde donde ya lo hacías.

   Endpoints que usa:
     GET /api/data                    -> ubicaciones, categorías, rutas…
     GET /api/radars?lat&lng&r&limit  -> radares cerca de un punto
     GET /api/ruta-leg?a&b&perfil     -> la ruta con alternativas (OSRM por el servidor)
     GET /api/traffic-status?…        -> color del tiempo de llegada (tráfico)
*/
import Foundation
import CoreLocation

/* Los modelos de Ubicación, Categoría, Etiqueta, Ruta… están en Almacen.swift: son los
   mismos datos que se leen y se guardan en el servidor. Aquí sólo van los de rutas y
   radares, que son de sólo lectura. */

struct Radar: Identifiable, Decodable, Hashable {
    let id: String
    let lat: Double
    let lng: Double
    let kind: String?
    let speed: Double?
    let dir: Double?
    /// Distancia al punto por el que se preguntó (la calcula el servidor)
    let dist: Double?
    let src: String?
    let label: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var titulo: String {
        switch kind ?? "" {
        case "fixed": return "Radar fijo"
        case "mobile": return "Radar móvil"
        case "tunnel": return "Radar de túnel"
        case "redlight": return "Radar de semáforo"
        case "section": return "Radar de tramo"
        case "belt": return "Cámara de infracciones"
        default: return "Radar"
        }
    }
}

private struct RespuestaRadares: Decodable {
    let items: [Radar]?
}

struct Ruta: Decodable, Hashable {
    let principal: Bool?
    let distKm: Double
    let durationMins: Double
    let puntos: [[Double]]
    /// LAS INDICACIONES PASO A PASO (giro a giro), si el motor de rutas las da
    var pasos: [Paso]? = nil

    var coordenadas: [CLLocationCoordinate2D] {
        puntos.compactMap { par in
            guard par.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: par[0], longitude: par[1])
        }
    }
}

/// UNA INDICACIÓN de las de «Gira a la derecha por…» (la lista paso a paso de Apple Maps)
struct Paso: Decodable, Hashable, Identifiable {
    let id: String
    let instruccion: String
    var distKm: Double = 0
    var minutos: Double = 0
    /// El tipo de maniobra de Valhalla (giro, rotonda…), para elegir el icono
    var tipo: Int? = nil
}

private struct RespuestaRuta: Decodable {
    let perfil: String?
    let rutas: [Ruta]?
}

enum Servidor {
    static let base = URL(string: "https://ubixavi.duckdns.org")!

    private static func pedir<T: Decodable>(_ ruta: String, _ consulta: [URLQueryItem] = [], metodo: String = "GET") async throws -> T {
        var comp = URLComponents(url: base.appendingPathComponent(ruta), resolvingAgainstBaseURL: false)!
        if !consulta.isEmpty { comp.queryItems = consulta }
        guard let url = comp.url else { throw URLError(.badURL) }
        var peticion = URLRequest(url: url)
        peticion.httpMethod = metodo
        peticion.timeoutInterval = 15
        let (datos, _) = try await URLSession.shared.data(for: peticion)
        return try JSONDecoder().decode(T.self, from: datos)
    }

    /// Radares cerca de un punto (los oficiales y los tuyos)
    static func radares(lat: Double, lng: Double, radioKm: Double = 8) async throws -> [Radar] {
        let respuesta: RespuestaRadares = try await pedir("api/radars", [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
            URLQueryItem(name: "r", value: String(radioKm)),
            URLQueryItem(name: "limit", value: "150"),
        ])
        return respuesta.items ?? []
    }

    /* EL MOTOR DE RUTAS ES VALHALLA, con OSRM de reserva.
       ¿Por qué? Porque Valhalla respeta MUCHO mejor los giros prohibidos y las medianas:
       OSRM nos estaba metiendo en giros de golpe y en cambios de sentido que en la calle
       están prohibidos. Valhalla además soporta `use_tolls: 0` para los peajes.
       El orden es:
         1) VALHALLA (coche o a pie, y sin peajes si está marcado).
         2) OSRM (el mismo servicio que usa el servidor).
         3) El servidor de siempre.
       Así nunca te quedas sin ruta. */
    static func rutas(
        desde: CLLocationCoordinate2D,
        hasta: CLLocationCoordinate2D,
        perfil: String,
        evitarPeajes: Bool = false
    ) async throws -> [Ruta] {
        if let lista = try? await rutasDeValhalla(desde: desde, hasta: hasta, perfil: perfil, sinPeajes: evitarPeajes),
           !lista.isEmpty {
            return lista
        }
        if let lista = try? await rutasDeOSRM(desde: desde, hasta: hasta, perfil: perfil, sinPeajes: evitarPeajes),
           !lista.isEmpty {
            return lista
        }
        if evitarPeajes, perfil != "pie" {
            // No se ha podido evitar: se avisa para que no te lleves la sorpresa
            await AvisosFlotantes.compartido.mal("No he encontrado ruta sin peajes: te doy la normal")
        }
        var consulta = [
            URLQueryItem(name: "a", value: "\(desde.latitude),\(desde.longitude)"),
            URLQueryItem(name: "b", value: "\(hasta.latitude),\(hasta.longitude)"),
            URLQueryItem(name: "perfil", value: perfil),
        ]
        if evitarPeajes { consulta.append(URLQueryItem(name: "peajes", value: "0")) }
        let respuesta: RespuestaRuta = try await pedir("api/ruta-leg", consulta)
        return respuesta.rutas ?? []
    }

    // ── VALHALLA: el que evita los peajes de verdad (`use_tolls: 0`) ──────────
    private struct RespuestaValhalla: Decodable {
        struct Resumen: Decodable {
            let length: Double   // km, porque se piden kilómetros
            let time: Double     // segundos
        }
        struct Tramo: Decodable {
            let shape: String
            let maneuvers: [Maniobra]?
        }
        /// Una indicación de VALHALLA: el texto del giro y cuánto dura ese paso
        struct Maniobra: Decodable {
            let instruction: String?
            let length: Double?     // km
            let time: Double?       // segundos
            let type: Int?          // el tipo de maniobra (giro, rotonda…), para el icono
            let street_names: [String]?
        }
        struct Viaje: Decodable {
            let legs: [Tramo]
            let summary: Resumen
        }
        let trip: Viaje?
        let alternates: [Alterno]?

        struct Alterno: Decodable { let trip: Viaje }
    }

    static func rutasDeValhalla(
        desde: CLLocationCoordinate2D,
        hasta: CLLocationCoordinate2D,
        perfil: String = "coche",
        sinPeajes: Bool = false
    ) async throws -> [Ruta] {
        guard let url = URL(string: "https://valhalla1.openstreetmap.de/route") else { return [] }
        let cuerpo: [String: Any] = [
            "locations": [
                ["lat": desde.latitude, "lon": desde.longitude],
                ["lat": hasta.latitude, "lon": hasta.longitude],
            ],
            "costing": perfil == "pie" ? "pedestrian" : "auto",
            // ESTO es lo que evita los peajes (y también los giros raros: Valhalla respeta
            // mucho mejor los giros prohibidos y las medianas que OSRM)
            "costing_options": perfil == "pie" ? [:] : ["auto": ["use_tolls": sinPeajes ? 0 : 1]],
            "alternates": 2,
            "directions_options": ["units": "kilometers", "language": "es-ES"],
        ]
        var peticion = URLRequest(url: url)
        peticion.httpMethod = "POST"
        peticion.setValue("application/json", forHTTPHeaderField: "Content-Type")
        peticion.httpBody = try JSONSerialization.data(withJSONObject: cuerpo)
        peticion.timeoutInterval = 15

        let (datos, _) = try await URLSession.shared.data(for: peticion)
        let respuesta = try JSONDecoder().decode(RespuestaValhalla.self, from: datos)
        var viajes: [RespuestaValhalla.Viaje] = []
        if let principal = respuesta.trip { viajes.append(principal) }
        for alterno in respuesta.alternates ?? [] { viajes.append(alterno.trip) }
        return viajes.prefix(3).enumerated().map { indice, viaje in
            var puntos: [[Double]] = []
            for tramo in viaje.legs { puntos.append(contentsOf: decodificarPolilinea(tramo.shape)) }
            // Se recortan los puntos (el mapa no necesita uno por metro)
            var recortados: [[Double]] = []
            let salto = max(1, Int(ceil(Double(puntos.count) / 2000.0)))
            var k = 0
            while k < puntos.count {
                recortados.append(puntos[k])
                k += salto
            }
            if let ultimo = puntos.last { recortados.append(ultimo) }
            recortados = limpiarPuntos(recortados)
            // Las maniobras de Valhalla son LAS INDICACIONES giro a giro
            let pasos: [Paso] = (viaje.legs.first?.maneuvers ?? []).compactMap { maniobra in
                guard let texto = maniobra.instruction, !texto.isEmpty else { return nil }
                return Paso(
                    id: "\(texto)-\(maniobra.length ?? 0)",
                    instruccion: texto,
                    distKm: ((maniobra.length ?? 0) * 10).rounded() / 10,
                    minutos: ((maniobra.time ?? 0) / 60 * 10).rounded() / 10,
                    tipo: maniobra.type
                )
            }
            return Ruta(
                principal: indice == 0,
                distKm: (viaje.summary.length * 10).rounded() / 10,
                durationMins: max(1, (viaje.summary.time / 60).rounded()),
                puntos: recortados,
                pasos: pasos.isEmpty ? nil : pasos
            )
        }
    }

    /* LIMPIAR LOS PUNTOS DE UNA RUTA antes de pintarla:
         · quita los puntos repetidos (dos iguales seguidos, que dan saltos raros);
         · y quita los «pinchos»: un punto al que entras y del que sales casi por el mismo
           sitio en muy pocos metros (eso es lo que hace esas especies de lazadas/giros de
           golpe al pintar la línea). Un giro de verdad ocupa bastantes más metros, así que
           no se toca. */
    static func limpiarPuntos(_ puntos: [[Double]]) -> [[Double]] {
        /* ¡OJO, AQUÍ ESTABA EL FALLO DE «LA RUTA NO SIGUE LA CARRETERA»!: antes se quitaban
           los puntos que apenas se desviaban de la recta anterior-siguiente, y al hacerlo
           una y otra vez la línea se iba ENDEREZANDO: las curvas se convertían en rectas
           largas y la ruta cruzaba las manzanas en diagonal.
           Ahora SÓLO se quitan los puntos REPETIDOS y los que están a menos de metro y medio
           del anterior. Nada más: la forma de la carretera se respeta entera. */
        guard puntos.count > 2 else { return puntos }
        var salida: [[Double]] = []
        for punto in puntos {
            guard punto.count >= 2 else { continue }
            if let ultimo = salida.last, ultimo.count >= 2 {
                let iguales = abs(ultimo[0] - punto[0]) < 1e-7 && abs(ultimo[1] - punto[1]) < 1e-7
                let muyCerca = CLLocation(latitude: ultimo[0], longitude: ultimo[1])
                    .distance(from: CLLocation(latitude: punto[0], longitude: punto[1])) < 1.5
                if iguales || muyCerca { continue }
            }
            salida.append(punto)
        }
        return salida
    }
    /// La «polyline6» de Valhalla (y de Google): se descodifica al revés de como se codifica
    static func decodificarPolilinea(_ texto: String, precision: Double = 1e6) -> [[Double]] {
        var coordenadas: [[Double]] = []
        var indice = texto.startIndex
        var lat = 0
        var lng = 0
        while indice < texto.endIndex {
            for cual in 0..<2 {
                var resultado = 0
                var desplazamiento = 0
                var byte = 0
                repeat {
                    guard indice < texto.endIndex, let valor = texto[indice].asciiValue else { break }
                    indice = texto.index(after: indice)
                    byte = Int(valor) - 63
                    resultado |= (byte & 0x1f) << desplazamiento
                    desplazamiento += 5
                } while byte >= 0x20
                let delta = (resultado & 1) != 0 ? ~(resultado >> 1) : (resultado >> 1)
                if cual == 0 { lat += delta } else { lng += delta }
            }
            coordenadas.append([Double(lat) / precision, Double(lng) / precision])
        }
        return coordenadas
    }

    // ── OSRM directamente (para lo que el servidor todavía no sabe: evitar peajes) ──
    private struct RespuestaOSRM: Decodable {
        struct RutaOSRM: Decodable {
            struct Geometria: Decodable { let coordinates: [[Double]] }
            let distance: Double
            let duration: Double
            let geometry: Geometria
        }
        let code: String
        let routes: [RutaOSRM]?
    }

    static func rutasDeOSRM(
        desde: CLLocationCoordinate2D,
        hasta: CLLocationCoordinate2D,
        perfil: String,
        sinPeajes: Bool
    ) async throws -> [Ruta] {
        let base = perfil == "pie"
            ? "https://routing.openstreetmap.de/routed-foot/route/v1/foot/"
            : "https://routing.openstreetmap.de/routed-car/route/v1/driving/"
        // OSRM espera lng,lat (al revés que todo lo demás)
        let a = "\(desde.longitude),\(desde.latitude)"
        let b = "\(hasta.longitude),\(hasta.latitude)"
        let exclusion = sinPeajes && perfil != "pie" ? "&exclude=toll" : ""
        guard let url = URL(string: "\(base)\(a);\(b)?overview=full&geometries=geojson&alternatives=3&steps=false\(exclusion)") else {
            return []
        }
        var peticion = URLRequest(url: url)
        peticion.timeoutInterval = 12
        let (datos, _) = try await URLSession.shared.data(for: peticion)
        let respuesta = try JSONDecoder().decode(RespuestaOSRM.self, from: datos)
        guard respuesta.code == "Ok", let rutas = respuesta.routes, !rutas.isEmpty else { return [] }
        return rutas.prefix(3).enumerated().map { indice, ruta in
            let coords = ruta.geometry.coordinates
            // Se recortan los puntos (el mapa no necesita uno por metro)
            let salto = max(1, Int(ceil(Double(coords.count) / 2000.0)))
            var puntos: [[Double]] = []
            var k = 0
            while k < coords.count {
                puntos.append([coords[k][1], coords[k][0]])
                k += salto
            }
            if let ultimo = coords.last { puntos.append([ultimo[1], ultimo[0]]) }
            puntos = limpiarPuntos(puntos)
            return Ruta(
                principal: indice == 0,
                distKm: (ruta.distance / 100).rounded() / 10,
                durationMins: max(1, (ruta.duration / 60).rounded()),
                puntos: puntos
            )
        }
    }

    // ── Resolver un enlace de Google Maps (nombre, dirección y coordenadas) ──
    struct LugarResuelto: Decodable {
        let name: String?
        let address: String?
        let lat: Double?
        let lng: Double?
        /// De dónde salieron las coordenadas (google-place, url-pin, url-coords…): es lo
        /// que dice si son EXACTAS o aproximadas, como en la web
        let source: String?
        let error: String?
    }

    static func resolverEnlace(_ enlace: String) async throws -> LugarResuelto {
        try await pedir("api/resolve-map", [URLQueryItem(name: "url", value: enlace)])
    }

    // ── Resolver una foto desde un enlace (Telegram, etc.) ───────────────────
    struct FotoResuelta: Decodable {
        let url: String?
        let isImage: Bool?
        let error: String?
    }

    static func resolverFoto(_ enlace: String) async throws -> FotoResuelta {
        try await pedir("api/photo-resolve", [URLQueryItem(name: "url", value: enlace)])
    }

    // ── Estado del tráfico (para el color y el retraso de la llegada) ────────
    struct Trafico: Decodable {
        let status: String?
        let delaySec: Double?
        let delayMin: Int?
        let travelSec: Double?
        let travelMin: Int?
        let distanceMeters: Double?
    }

    static func trafico(desde: CLLocationCoordinate2D, hasta: CLLocationCoordinate2D) async throws -> Trafico {
        try await pedir("api/traffic-status", [
            URLQueryItem(name: "lat1", value: String(desde.latitude)),
            URLQueryItem(name: "lng1", value: String(desde.longitude)),
            URLQueryItem(name: "lat2", value: String(hasta.latitude)),
            URLQueryItem(name: "lng2", value: String(hasta.longitude)),
        ])
    }

    // ── Editar un radar propio (tipo, límite, inicio/final y posición) ───────
    static func editarRadar(id: String, type: String?, speed: Double?, role: String?, lat: Double?, lng: Double?) async throws -> ResultadoCaptura {
        var cuerpo: [String: Any] = ["id": id]
        if let type = type { cuerpo["type"] = type }
        if let speed = speed { cuerpo["speed"] = speed }
        if let role = role { cuerpo["role"] = role }
        if let lat = lat { cuerpo["lat"] = lat }
        if let lng = lng { cuerpo["lng"] = lng }
        return try await enviar("api/radars/user/editar", metodo: "POST", cuerpo: cuerpo)
    }

    // ── Radares propios (los que captura la app) ─────────────────────────────
    struct RadarPropio: Identifiable, Decodable, Hashable {
        let id: String
        let type: String?
        let lat: Double
        let lng: Double
        let speed: Double?
        let role: String?
        let dir: Double?
        let confirmations: Int?
        let createdAt: Double?
        let updatedAt: Double?

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
    }

    struct ResumenRadares: Decodable {
        let total: Int?
        let porTipo: [String: Int]?
        let quitados: Int?
        let updatedAt: Double?
        let items: [RadarPropio]?
    }

    static func misRadares() async throws -> ResumenRadares {
        try await pedir("api/radars/user", [URLQueryItem(name: "lista", value: "1")])
    }

    struct ResultadoCaptura: Decodable {
        let ok: Bool?
        let created: Bool?
        let error: String?
        let item: RadarPropio?
    }

    /// Guarda un radar capturado (si ya había uno del mismo tipo cerca, lo confirma)
    static func capturarRadar(type: String, lat: Double, lng: Double, speed: Double?, role: String?, dir: Double?) async throws -> ResultadoCaptura {
        var cuerpo: [String: Any] = ["type": type, "lat": lat, "lng": lng]
        if let speed = speed { cuerpo["speed"] = speed }
        if let role = role, !role.isEmpty { cuerpo["role"] = role }
        if let dir = dir, dir >= 0 { cuerpo["dir"] = dir }
        return try await enviar("api/radars/user", metodo: "POST", cuerpo: cuerpo)
    }

    static func borrarRadar(lat: Double, lng: Double, type: String) async throws {
        /* OJO: la respuesta lleva texto además de `ok` («quitadoPropio», «marcadoComoQuitado»),
           así que NO se puede decodificar como [String: Bool]: fallaba la lectura y la app
           decía que no había podido borrar… cuando el servidor sí lo había borrado. */
        var comp = URLComponents(url: base.appendingPathComponent("api/radars/user"), resolvingAgainstBaseURL: false)!
        comp.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
            URLQueryItem(name: "type", value: type),
        ]
        guard let url = comp.url else { throw URLError(.badURL) }
        var peticion = URLRequest(url: url)
        peticion.httpMethod = "DELETE"
        peticion.timeoutInterval = 15
        let (_, respuesta) = try await URLSession.shared.data(for: peticion)
        if let http = respuesta as? HTTPURLResponse, http.statusCode >= 400 {
            throw URLError(.badServerResponse)
        }
    }

    // ── Estado de la base de radares (oficiales) ─────────────────────────────
    struct EstadoBase: Decodable {
        let updatedAt: Double?
        let count: Int?
        let sources: [String]?
    }

    static func estadoBase() async throws -> EstadoBase {
        try await pedir("api/radars")
    }

    /// Fuerza la descarga de la base oficial (tarda ~1 minuto, se hace en el servidor)
    static func refrescarBase() async throws {
        // Igual que el borrado: no se decodifica la respuesta (trae texto y números)
        var peticion = URLRequest(url: base.appendingPathComponent("api/radars/refresh"))
        peticion.httpMethod = "POST"
        peticion.timeoutInterval = 20
        let (_, respuesta) = try await URLSession.shared.data(for: peticion)
        if let http = respuesta as? HTTPURLResponse, http.statusCode >= 400 {
            throw URLError(.badServerResponse)
        }
    }

    // ── Enviar con cuerpo (POST/PUT/DELETE) ──────────────────────────────────
    private static func enviar<T: Decodable>(_ ruta: String, metodo: String, cuerpo: [String: Any]?) async throws -> T {
        var peticion = URLRequest(url: base.appendingPathComponent(ruta))
        peticion.httpMethod = metodo
        peticion.timeoutInterval = 25
        if let cuerpo = cuerpo {
            peticion.setValue("application/json", forHTTPHeaderField: "Content-Type")
            peticion.httpBody = try JSONSerialization.data(withJSONObject: cuerpo)
        }
        let (datos, _) = try await URLSession.shared.data(for: peticion)
        return try JSONDecoder().decode(T.self, from: datos)
    }

    // ── El documento compartido (leer y GUARDAR) ─────────────────────────────
    /// Se lee TAL CUAL (sin modelos): así al guardar no se pierde ningún campo que la
    /// app no conozca (fotos, rutas, ajustes…).
    static func documento() async throws -> [String: Any] {
        var peticion = URLRequest(url: base.appendingPathComponent("api/data"))
        peticion.timeoutInterval = 15
        let (datos, _) = try await URLSession.shared.data(for: peticion)
        let objeto = try JSONSerialization.jsonObject(with: datos)
        return (objeto as? [String: Any]) ?? [:]
    }

    static func guardarDocumento(_ documento: [String: Any]) async throws {
        var peticion = URLRequest(url: base.appendingPathComponent("api/data"))
        peticion.httpMethod = "PUT"
        peticion.setValue("application/json", forHTTPHeaderField: "Content-Type")
        peticion.timeoutInterval = 20
        peticion.httpBody = try JSONSerialization.data(withJSONObject: documento)
        let (_, respuesta) = try await URLSession.shared.data(for: peticion)
        if let http = respuesta as? HTTPURLResponse, http.statusCode >= 400 {
            throw URLError(.badServerResponse)
        }
    }

    // ── Geocodificación inversa y foto de la calle ───────────────────────────
    struct Direccion: Decodable {
        let address: String?
        let name: String?
        let display_name: String?
    }

    static func direccion(lat: Double, lng: Double) async throws -> Direccion {
        try await pedir("api/reverse-geocode", [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
        ])
    }

    struct Panoramica: Decodable {
        let available: Bool?
        let panoid: String?
        let imageUrl: String?
        let link: String?
        let address: String?
    }

    static func panoramica(lat: Double, lng: Double) async throws -> Panoramica {
        try await pedir("api/streetview", [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
        ])
    }
}

/* Textos con el mismo formato que en la web */
func textoDuracion(_ minutos: Double) -> String {
    let total = Int(minutos.rounded())
    if total < 60 { return "\(total) min" }
    let horas = total / 60
    let resto = total % 60
    return resto == 0 ? "\(horas) h" : "\(horas) h \(resto) min"
}

func textoDistancia(_ km: Double) -> String {
    if km < 1 { return "\(Int((km * 1000).rounded())) m" }
    return String(format: "%.1f km", km)
}

func textoHoraLlegada(_ minutos: Double) -> String {
    let llegada = Date().addingTimeInterval(minutos * 60)
    let formato = DateFormatter()
    formato.dateFormat = "HH:mm"
    return formato.string(from: llegada)
}
