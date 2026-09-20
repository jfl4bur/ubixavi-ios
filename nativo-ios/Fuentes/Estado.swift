/* EL ESTADO DE LA APP: tu posición, las ubicaciones, la ruta, los radares y los avisos.

   Aquí está todo lo que en la versión anterior vivía repartido entre la web y el puente.
   Ahora es una sola cosa: la app sabe dónde estás, qué radares tienes cerca y por dónde
   vas, y decide ella misma cuándo avisar.
*/
import Foundation
import Combine
import CoreLocation
// SwiftUI: lo necesita el `move(fromOffsets:toOffset:)` de las paradas del viaje
import SwiftUI

@MainActor
final class Estado: NSObject, ObservableObject, CLLocationManagerDelegate {
    // ── Datos ────────────────────────────────────────────────────────────────
    @Published var destino: Ubicacion?
    /// Un tramo del viaje (de una parada a la siguiente): lo que tarda y cómo está el
    /// tráfico, como los paneles de tramos de la web
    struct Tramo: Identifiable, Hashable {
        let id: String
        let desde: String
        let hasta: String
        var distKm: Double
        var durationMins: Double
        var trafico: String?
        var retrasoMin: Int?
        /// La hora de llegada A ESA PARADA (encadenada, no «ahora + este tramo»)
        var llegada: Date?
    }

    /// El viaje: varias paradas en orden (como el «Ir a» de la web)
    @Published var paradas: [Ubicacion] = []
    @Published var hechas: Set<Int> = []
    @Published var tramos: [Tramo] = []
    @Published var cargandoTramos = false
    @Published var rutas: [Ruta] = []
    @Published var elegida: Int = 0
    @Published var radares: [Radar] = []
    @Published var navegando = false
    @Published var perfil = "coche"
    @Published var aviso: String?
    @Published var cargando = false
    @Published var fallo: String?
    /// Estado del tráfico del tramo y cuánto queda (para la llegada y la barra)
    @Published var trafico: Servidor.Trafico?
    @Published var quedaKm: Double?
    @Published var totalKm: Double?

    // ── De tu posición ───────────────────────────────────────────────────────
    @Published var posicion: CLLocation?
    @Published var velocidadKmh: Int?
    @Published var rumbo: Double = -1
    @Published var radarAvisando: String?

    private let gestor = CLLocationManager()
    private let avisos = Avisos()
    private var ultimaCargaRadares = Date.distantPast
    /// Dónde has terminado la parada anterior A MANO: la ruta hasta la siguiente sale de ahí
    @Published var origenManual: CLLocationCoordinate2D?
    var ultimoAvisado: String?
    var ultimoAviso = Date.distantPast
    var ultimoPitido = Date.distantPast

    override init() {
        super.init()
        gestor.delegate = self
        gestor.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        gestor.activityType = .automotiveNavigation
        gestor.distanceFilter = kCLDistanceFilterNone
        gestor.headingFilter = 2
        /* SEGUIR CON EL GPS AUNQUE BLOQUEES EL MÓVIL (como Google Maps, Radarbot o Waze):
           · `allowsBackgroundLocationUpdates`: sin esto iOS corta el GPS al salir de la app
             o al bloquear el teléfono, y entonces no hay avisos de radar.
           · `showsBackgroundLocationIndicator`: enseña el INDICADOR AZUL de iOS (la píldora
             azul de la barra de estado con la hora) mientras la app usa tu ubicación en
             segundo plano. Es el aviso que da el sistema y no se puede quitar.
           · `pausesLocationUpdatesAutomatically = false`: que iOS no pare el GPS solo.
           El Info.plist ya lleva `UIBackgroundModes: location` (si no, iOS ignoraría todo
           esto) y el permiso «Siempre» se pide más abajo. */
        gestor.allowsBackgroundLocationUpdates = true
        gestor.showsBackgroundLocationIndicator = true
        gestor.pausesLocationUpdatesAutomatically = false
        gestor.requestWhenInUseAuthorization()
        gestor.startUpdatingLocation()
        gestor.startUpdatingHeading()
    }

    // ── Permiso de ubicación ─────────────────────────────────────────────────
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let estado = manager.authorizationStatus
        Task { @MainActor in
            switch estado {
            case .authorizedWhenInUse:
                // Se pide el «siempre» para seguir avisando con la app en segundo plano
                manager.requestAlwaysAuthorization()
                manager.startUpdatingLocation()
            case .authorizedAlways:
                manager.startUpdatingLocation()
            case .denied, .restricted:
                self.fallo = "Sin permiso de ubicación: actívalo en Ajustes para que el mapa te siga."
            default:
                break
            }
        }
    }

    // ── Posición ─────────────────────────────────────────────────────────────
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let ultima = locations.last, ultima.horizontalAccuracy >= 0 else { return }
        Task { @MainActor in
            // Durante la DEMO manda la posición simulada, no el GPS
            guard !self.demoActiva else { return }
            self.posicion = ultima
            self.velocidadKmh = ultima.speed > 0 ? Int((ultima.speed * 3.6).rounded()) : 0
            self.actualizarProgreso()
            await self.refrescarRadaresSiToca()
            self.comprobarAviso()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let valor = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            self.rumbo = valor
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.fallo = "GPS: \(error.localizedDescription)"
        }
    }

    // ── Radares ──────────────────────────────────────────────────────────────
    private func refrescarRadaresSiToca() async {
        guard let pos = posicion else { return }
        let ahora = Date()
        guard ahora.timeIntervalSince(ultimaCargaRadares) > 20 else { return }
        ultimaCargaRadares = ahora
        if let lista = try? await Servidor.radares(lat: pos.coordinate.latitude, lng: pos.coordinate.longitude) {
            /* OJO CON LA DEMO: si la lista de radares se refresca a mitad de la demo, el
               radar de mentira desaparecía y la demo se quedaba sin aviso. Mientras la
               demo esté en marcha, su radar se conserva. */
            if demoActiva, let idDemo = demoRadarId, let radarDemo = radares.first(where: { $0.id == idDemo }) {
                radares = [radarDemo] + lista.filter { $0.id != idDemo }
            } else {
                radares = lista
            }
        }
    }

    /// El límite de la carretera por la que vas: el del radar más cercano que lo traiga
    var limiteActual: Int? {
        guard let pos = posicion else { return nil }
        var mejor: Double?
        var mejorDistancia = 700.0
        for radar in radares {
            guard let limite = radar.speed, limite > 0 else { continue }
            let distancia = CLLocation(latitude: radar.lat, longitude: radar.lng).distance(from: pos)
            if distancia < mejorDistancia {
                mejorDistancia = distancia
                mejor = limite
            }
        }
        return mejor.map { Int($0) }
    }

    var pasadoDeLimite: Bool {
        guard let limite = limiteActual, let velocidad = velocidadKmh else { return false }
        return velocidad > limite + 1
    }

    // ── El aviso de radar ────────────────────────────────────────────────────
    /* Distancia a la que se avisa: lo que se tarda 35 s a la velocidad actual, con un
       mínimo de 250 m y un máximo de 2200 m. A más velocidad, antes avisa.
       Son EXACTAMENTE los números de la web (AVISO_SEGUNDOS / AVISO_MIN_M / AVISO_MAX_M
       en src/radar-utils.js): así el aviso dura lo mismo aquí y allí. */
    private func distanciaDeAviso(_ velocidadMs: Double) -> Double {
        let v = velocidadMs > 0 ? velocidadMs : 0
        return min(max(v * 35, 250), 2200)
    }

    /// Distancia a la que empiezan los pitidos de acercamiento (6 s de recorrido)
    private func umbralPitidos(_ velocidadMs: Double) -> Double {
        let v = velocidadMs > 0 ? velocidadMs : 0
        return min(max(v * 6, 50), 260)
    }

    private func comprobarAviso() {
        /* El interruptor de Ajustes: si los avisos están apagados, no se dice nada */
        let activos = UserDefaults.standard.object(forKey: "avisosRadares") as? Bool ?? true
        guard activos else {
            radarAvisando = nil
            return
        }
        guard let pos = posicion, !radares.isEmpty else {
            radarAvisando = nil
            return
        }
        /* «Sólo los radares de la ruta»: si está activado, se avisa únicamente de los que
           están sobre la ruta que llevas (a menos de 150 m de ella). Así no te salta un
           radar de la carretera de al lado. */
        let soloRuta = UserDefaults.standard.object(forKey: "soloRadaresEnRuta") as? Bool ?? false
        let candidatos = soloRuta ? radares.filter { estaEnLaRuta($0) } : radares
        guard !candidatos.isEmpty else {
            radarAvisando = nil
            return
        }
        let umbral = distanciaDeAviso(pos.speed > 0 ? pos.speed : 0)
        let umbralPitido = umbralPitidos(pos.speed > 0 ? pos.speed : 0)
        var candidato: Radar?
        var candidataDistancia = umbral
        for radar in candidatos {
            let punto = CLLocation(latitude: radar.lat, longitude: radar.lng)
            let distancia = punto.distance(from: pos)
            if distancia < candidataDistancia {
                candidataDistancia = distancia
                candidato = radar
            }
        }
        guard let radar = candidato else {
            radarAvisando = nil
            // Al alejarse del radar avisado, se olvida para poder volver a avisar
            if let ultimo = ultimoAvisado,
               let anterior = radares.first(where: { $0.id == ultimo }) {
                let distancia = CLLocation(latitude: anterior.lat, longitude: anterior.lng).distance(from: pos)
                if distancia > umbral * 1.8 { ultimoAvisado = nil }
            }
            return
        }

        radarAvisando = radar.id
        let ahora = Date()

        // Aviso completo: voz + pitidos (una vez por radar)
        if ultimoAvisado != radar.id, ahora.timeIntervalSince(ultimoAviso) > 8 {
            ultimoAvisado = radar.id
            ultimoAviso = ahora
            avisos.activarSesion()
            avisos.decir(frase(radar))
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                self.avisos.pitidos(veces: 2, frecuencia: 780, separacionMs: 150)
            }
        } else if candidataDistancia < umbralPitido, ahora.timeIntervalSince(ultimoPitido) > 1.2 {
            // Ya cerca: un pitido cada segundo hasta pasarlo
            ultimoPitido = ahora
            avisos.pitidos(veces: 1, frecuencia: 880, separacionMs: 0, duracion: 0.08, volumen: 0.7)
        }
    }

    /// ¿Este radar está sobre la ruta que llevas? (a menos de 150 m de ella)
    private func estaEnLaRuta(_ radar: Radar) -> Bool {
        guard navegando, let ruta = rutaElegida else { return false }
        let coordenadas = ruta.coordenadas
        guard coordenadas.count > 1 else { return false }
        let punto = CLLocation(latitude: radar.lat, longitude: radar.lng)
        var minima = Double.greatestFiniteMagnitude
        // Se mira la distancia a la línea (no a los puntos): así no hay huecos entre nodos
        for indice in 0..<(coordenadas.count - 1) {
            let a = CLLocation(latitude: coordenadas[indice].latitude, longitude: coordenadas[indice].longitude)
            let b = CLLocation(latitude: coordenadas[indice + 1].latitude, longitude: coordenadas[indice + 1].longitude)
            let distancia = distanciaAlSegmento(punto: punto, a: a, b: b)
            if distancia < minima { minima = distancia }
            if minima < 150 { return true }
        }
        return minima < 150
    }

    private func distanciaAlSegmento(punto: CLLocation, a: CLLocation, b: CLLocation) -> CLLocationDistance {
        let ax = a.coordinate.latitude, ay = a.coordinate.longitude
        let bx = b.coordinate.latitude, by = b.coordinate.longitude
        let px = punto.coordinate.latitude, py = punto.coordinate.longitude
        let dx = bx - ax, dy = by - ay
        let largo = dx * dx + dy * dy
        if largo <= 0.0000001 { return punto.distance(from: a) }
        var t = ((px - ax) * dx + (py - ay) * dy) / largo
        t = min(max(t, 0), 1)
        let proyeccion = CLLocation(latitude: ax + t * dx, longitude: ay + t * dy)
        return punto.distance(from: proyeccion)
    }

    private func frase(_ radar: Radar) -> String {
        let limite = radar.speed.map { " Límite. \(Int($0))" } ?? ""
        switch radar.kind ?? "" {
        case "fixed": return "¡ATENCIÓN! Radar fijo, más adelante.\(limite)"
        case "mobile": return "¡ATENCIÓN! Posible Radar móvil, más adelante.\(limite)"
        case "tunnel": return "¡ATENCIÓN! Radar en Túnel, más adelante.\(limite)"
        case "redlight": return "¡ATENCIÓN! Rádar en Semáforo.\(limite)"
        case "section": return "¡ATENCIÓN! Inicio de Radar de Tramo.\(limite)"
        default: return "¡ATENCIÓN! Radar, más adelante.\(limite)"
        }
    }

    // ── Navegación ───────────────────────────────────────────────────────────
    var rutaElegida: Ruta? {
        guard !rutas.isEmpty else { return nil }
        return rutas[min(max(elegida, 0), rutas.count - 1)]
    }

    /// Carga los tramos del viaje (de parada a parada), con su tráfico
    func cargarTramos() async {
        guard !paradas.isEmpty, let pos = posicion else {
            tramos = []
            return
        }
        cargandoTramos = true
        defer { cargandoTramos = false }
        tramos = await Estado.calcularTramos(
            paradas: paradas,
            desde: pos.coordinate,
            perfil: perfil,
            desdeIndice: indiceActual ?? 0,
            origenManual: origenManual
        ) { parciales in
            self.tramos = parciales // se van viendo conforme llegan
        }
    }

    /// Los tramos de una lista de paradas: se usa para el viaje Y para una ruta guardada
    /* LAS HORAS DE LLEGADA VAN ENCADENADAS: la de la parada 1 es «ahora + el tramo 1», la de
       la 2 es «la hora de llegada a la 1 + el tramo 2», y así. Antes cada tramo decía «ahora
       + su duración», así que todas las paradas parecían llegarse a la misma hora.
       Se empieza a contar en la PRIMERA PARADA PENDIENTE (`desdeIndice`): las ya hechas no
       llevan hora. Y el origen del primer tramo es tu posición (o `origenManual`, que es
       donde has terminado la parada anterior a mano). */
    static func calcularTramos(
        paradas: [Ubicacion],
        desde: CLLocationCoordinate2D,
        perfil: String,
        desdeIndice: Int = 0,
        origenManual: CLLocationCoordinate2D? = nil,
        alAvanzar: (([Tramo]) -> Void)? = nil
    ) async -> [Tramo] {
        /* UN TRAMO POR PARADA: el que LLEGA a esa parada. El origen de cada uno es:
             · la parada anterior (de parada a parada, como se pide);
             · y para la parada QUE TOCA, tu POSICIÓN si acabas de finalizar la anterior a
               mano (`origenManual`): así los km, el tiempo y la hora de llegada a la
               siguiente salen de donde la has terminado, no de la parada anterior. */
        let conCoordenadas = paradas.filter { $0.tieneCoordenadas }
        guard !conCoordenadas.isEmpty else { return [] }
        let arranque = origenManual ?? desde
        var lista: [Tramo] = []
        for (indice, parada) in conCoordenadas.enumerated() {
            let desdeCoord: CLLocationCoordinate2D
            let desdeNombre: String
            if indice == 0 {
                desdeCoord = arranque
                desdeNombre = origenManual != nil ? "Donde terminaste" : "Ubicación actual"
            } else if origenManual != nil, indice == desdeIndice {
                // AQUÍ está el «finalizado a mano»: se sale desde tu GPS de ese momento
                desdeCoord = arranque
                desdeNombre = "Donde terminaste"
            } else {
                desdeCoord = conCoordenadas[indice - 1].coordinate
                desdeNombre = conCoordenadas[indice - 1].name
            }
            var tramo = Tramo(
                id: "\(indice)-\(parada.name)",
                desde: desdeNombre,
                hasta: parada.name,
                distKm: 0,
                durationMins: 0
            )
            if let rutas = try? await Servidor.rutas(
                desde: desdeCoord,
                hasta: parada.coordinate,
                perfil: perfil,
                evitarPeajes: UserDefaults.standard.bool(forKey: "evitarPeajes")
            ),
               let primera = rutas.first {
                tramo.distKm = primera.distKm
                tramo.durationMins = primera.durationMins
                if perfil == "coche",
                   let trafico = try? await Servidor.trafico(desde: desdeCoord, hasta: parada.coordinate) {
                    tramo.trafico = trafico.status
                    tramo.retrasoMin = trafico.delayMin
                }
            }
            lista.append(tramo)
            alAvanzar?(lista)
        }
        // Y ahora las horas de llegada, encadenadas desde la primera parada pendiente
        var acumulado: Double = 0
        for indice in lista.indices {
            if indice < desdeIndice {
                lista[indice].llegada = nil
                continue
            }
            acumulado += lista[indice].durationMins
            lista[indice].llegada = Date().addingTimeInterval(acumulado * 60)
        }
        return lista
    }

    func elegirDestino(_ ubicacion: Ubicacion) async {
        paradas = [ubicacion]
        hechas = []
        origenManual = nil
        navegando = false
        destino = ubicacion
        elegida = 0
        tramos = []
        guardarSesion()
        await pedirRuta()
    }

    /// Añade una parada MÁS al viaje (como el «Añadir ubicaciones» de la web)
    func anadirParada(_ ubicacion: Ubicacion) async {
        paradas.append(ubicacion)
        recalcularDestino()
        elegida = 0
        await pedirRuta()
        await cargarTramos()
        guardarSesion()
    }

    // ══════════════════════════════════════════════════════════════════════════
    // METER UNA RUTA GUARDADA ENTERA EN EL NAVEGADOR
    // ══════════════════════════════════════════════════════════════════════════
    /* Es el «Navegar» de la web: TODAS las paradas pasan al navegador (no sólo la
       primera), se marcan las que ya estaban hechas y arranca la conducción hacia la
       primera pendiente. Antes el botón sólo ponía una parada como destino y parecía que
       no hacía nada. */
    func cargarRutaEnElNavegador(paradas nuevas: [Ubicacion], hechas indicesHechos: Set<Int> = []) {
        guard !nuevas.isEmpty else { return }
        paradas = nuevas
        hechas = indicesHechos
        // El destino es la primera parada PENDIENTE (las hechas se saltan solas)
        destino = nuevas.enumerated().first { !indicesHechos.contains($0.offset) }?.element ?? nuevas[0]
        elegida = 0
        tramos = []
        navegando = true
        guardarSesion()
        AvisosFlotantes.compartido.bien("Ruta en el navegador: \(nuevas.count) parada\(nuevas.count == 1 ? "" : "s")")
        Task {
            await pedirRuta()
            await cargarTramos()
        }
    }

    func quitarParada(_ indice: Int) {
        guard paradas.indices.contains(indice) else { return }
        paradas.remove(at: indice)
        hechas = Set(hechas.compactMap { $0 == indice ? nil : ($0 > indice ? $0 - 1 : $0) })
        recalcularDestino()
        guardarSesion()
        Task {
            await pedirRuta()
            await cargarTramos()
        }
    }

    func moverParada(de origen: IndexSet, a destinoIndice: Int) {
        paradas.move(fromOffsets: origen, toOffset: destinoIndice)
        hechas = []
        recalcularDestino()
        guardarSesion()
        Task {
            await pedirRuta()
            await cargarTramos()
        }
    }

    /// Marca la parada actual como hecha y pasa a la siguiente
    /* FINALIZAR UNA PARADA. Si la marcas TÚ (a mano), la ruta hasta la SIGUIENTE sale de
       donde estás en ese momento (origenManual): así los km, el tiempo y la hora de llegada
       son los reales desde donde la has terminado. Si la DESMARCAS, se vuelve a la ruta
       normal. Y si una parada no está hecha, NO se salta a la siguiente: la que toca es
       siempre la primera pendiente. */
    func marcarHecha(_ indice: Int, aMano: Bool = true) async {
        if hechas.contains(indice) {
            hechas.remove(indice)
            origenManual = nil
        } else {
            hechas.insert(indice)
            if aMano, let pos = posicion { origenManual = pos.coordinate }
        }
        recalcularDestino()
        elegida = 0
        guardarSesion()
        await pedirRuta()
        await cargarTramos()
    }

    /// La parada que toca ahora (la primera sin hacer)
    var indiceActual: Int? {
        paradas.indices.first { !hechas.contains($0) }
    }

    private func recalcularDestino() {
        if let indice = indiceActual {
            destino = paradas[indice]
        } else {
            destino = paradas.last
        }
    }

    func limpiarViaje() {
        salirDeNavegacion()
        paradas = []
        hechas = []
        origenManual = nil
        destino = nil
        rutas = []
        elegida = 0
        trafico = nil
        quedaKm = nil
        totalKm = nil
        guardarSesion()
    }

    func pedirRuta() async {
        guard let destino = destino, let pos = posicion else { return }
        do {
            let lista = try await Servidor.rutas(
                desde: pos.coordinate,
                hasta: destino.coordinate,
                perfil: perfil,
                evitarPeajes: UserDefaults.standard.bool(forKey: "evitarPeajes")
            )
            rutas = lista
            elegida = min(elegida, max(0, lista.count - 1))
            fallo = nil
            actualizarProgreso()
            await pedirTrafico(destino: destino)
        } catch {
            fallo = "No pude calcular la ruta: \(error.localizedDescription)"
        }
    }

    /// El tráfico sólo tiene sentido en coche (a pie el tiempo es el de OSRM)
    private func pedirTrafico(destino: Ubicacion) async {
        guard perfil == "coche", let pos = posicion else {
            trafico = nil
            return
        }
        trafico = try? await Servidor.trafico(desde: pos.coordinate, hasta: destino.coordinate)
    }

    /// Cuánto queda de ruta (por la línea de la ruta, no en línea recta) y el total
    func actualizarProgreso() {
        guard let ruta = rutaElegida, let pos = posicion, ruta.puntos.count > 1 else {
            // (en el «else» del guard no se ven las variables de arriba: se usa el atajo)
            quedaKm = nil
            totalKm = rutaElegida?.distKm
            return
        }
        let coordenadas = ruta.coordenadas
        // 1) Se busca el punto de la ruta más cercano a donde estás
        var mejorIndice = 0
        var mejorDistancia = Double.greatestFiniteMagnitude
        for (indice, coordenada) in coordenadas.enumerated() {
            let distancia = CLLocation(latitude: coordenada.latitude, longitude: coordenada.longitude)
                .distance(from: pos)
            if distancia < mejorDistancia {
                mejorDistancia = distancia
                mejorIndice = indice
            }
        }
        // 2) Y se suma lo que queda desde ahí hasta el final
        var metros: Double = 0
        var anterior = CLLocation(latitude: coordenadas[mejorIndice].latitude, longitude: coordenadas[mejorIndice].longitude)
        for indice in (mejorIndice + 1)..<coordenadas.count {
            let actual = CLLocation(latitude: coordenadas[indice].latitude, longitude: coordenadas[indice].longitude)
            metros += actual.distance(from: anterior)
            anterior = actual
        }
        quedaKm = metros / 1000
        totalKm = ruta.distKm
    }

    /// De 0 a 1: lo que llevas hecho de la ruta (para la barra de progreso)
    var progreso: Double {
        guard let total = totalKm, total > 0.2, let queda = quedaKm else { return 0 }
        return min(max(1 - (queda / total), 0), 1)
    }

    /// La hora a la que llegarás (con el tiempo real de la ruta elegida)
    var horaLlegada: Date? {
        guard let minutos = rutaElegida?.durationMins else { return nil }
        return Date().addingTimeInterval(minutos * 60)
    }

    /// Volver a calcular la ruta (al cambiar de perfil o al activar «evitar peajes»)
    func recalcularRuta() async {
        guard destino != nil else { return }
        elegida = 0
        await pedirRuta()
        await cargarTramos()
    }

    func cambiarPerfil(_ nuevo: String) async {
        perfil = nuevo
        guardarSesion()
        await pedirRuta()
    }

    /// EMPEZAR A NAVEGAR: la ruta entera y la cámara de calle
    /* Se avisa con un cartelito para que se vea que ha hecho algo, y si aún no había ruta
       calculada se pide en el momento (así nunca te quedas «navegando» sin ruta). */
    func iniciarNavegacion() {
        navegando = true
        avisos.activarSesion()
        AvisosFlotantes.compartido.bien(
            paradas.count > 1 ? "Navegando · \(paradas.count) paradas" : "Navegando"
        )
        if rutas.isEmpty, destino != nil {
            Task { await pedirRuta() }
        }
        guardarSesion()
    }

    func salirDeNavegacion() {
        navegando = false
        ultimoAvisado = nil
        radarAvisando = nil
        avisos.callar()
        AvisosFlotantes.compartido.info("Has salido de la navegación")
        guardarSesion()
    }

    func quitarDestino() {
        limpiarViaje()
    }

    /// Prueba del aviso (la «demo» de la web): voz y pitidos, sin moverte
    func probarAviso() {
        avisos.activarSesion()
        avisos.decir("¡ATENCIÓN! Radar fijo, más adelante. Límite. 50")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            self.avisos.pitidos(veces: 2, frecuencia: 780, separacionMs: 150)
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // DEMO COMPLETA DEL AVISO: te lleva conduciendo sola hasta un radar
    // ══════════════════════════════════════════════════════════════════════════
    /* No es sólo un sonido: se SIMULA la conducción (el mapa se mueve, tu punto
       avanza, sale el velocímetro) y el aviso salta cuando toca, con la voz y los
       pitidos de verdad, igual que en la carretera. Al pasar el radar, la demo
       termina sola. */
    @Published var demoActiva = false
    private var demoTarea: Task<Void, Never>?
    private var demoRadarId: String?

    /// Un punto desplazado `metros` en la dirección `rumbo` (0 = norte, 90 = este)
    private func desplazar(_ c: CLLocationCoordinate2D, rumbo: Double, metros: Double) -> CLLocationCoordinate2D {
        let rad = rumbo * Double.pi / 180
        let dLat = (metros * cos(rad)) / 111_320.0
        let dLng = (metros * sin(rad)) / (111_320.0 * max(0.2, cos(c.latitude * Double.pi / 180)))
        return CLLocationCoordinate2D(latitude: c.latitude + dLat, longitude: c.longitude + dLng)
    }

    func empezarDemo() {
        if demoActiva {
            pararDemo()
            return
        }
        let base = posicion?.coordinate ?? CLLocationCoordinate2D(latitude: 41.3874, longitude: 2.1686)
        /* El radar de mentira va 1.600 m al norte. A 90 km/h el aviso salta a unos 875 m
           (35 s de viaje), o sea que primero ves acercarse el mapa y luego salta el aviso. */
        let distanciaDemo = 1_600.0
        let objetivo = desplazar(base, rumbo: 0, metros: distanciaDemo)
        let id = "demo-\(Int(Date().timeIntervalSince1970))"
        let radar = Radar(
            id: id,
            lat: objetivo.latitude,
            lng: objetivo.longitude,
            kind: "fixed",
            speed: 90,
            dir: 0,
            dist: distanciaDemo,
            src: "demo",
            label: "DEMO · radar de mentira"
        )
        demoRadarId = id
        radares = [radar] + radares.filter { $0.id != id }
        demoActiva = true
        ultimoAvisado = nil
        radarAvisando = nil
        avisos.activarSesion()

        // El destino es el radar: así el mapa te sigue y sale el velocímetro
        destino = Ubicacion(
            id: "demo-destino",
            name: "Demo · radar a 1,6 km",
            address: "Conducción simulada",
            code: "",
            notes: "",
            lat: objetivo.latitude,
            lng: objetivo.longitude,
            categoryId: "",
            tagIds: [],
            pinned: false,
            photos: []
        )
        navegando = true
        posicion = CLLocation(
            coordinate: base, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            course: 0, speed: 25, timestamp: Date()
        )
        velocidadKmh = 90
        rumbo = 0
        Task { await pedirRuta() }

        AvisosFlotantes.compartido.info("Demo: conduciendo hacia el radar a 90 km/h")

        demoTarea = Task { @MainActor in
            var aqui = base
            var restante = distanciaDemo + 250 // 250 m de más, para verlo pasar
            /* Va 4 veces más rápido que de verdad (unos 100 m/s) para que la demo dure unos
               18 s. La velocidad que se enseña y la que se usa para el aviso son los 90 km/h
               de verdad, así que el aviso salta a la distancia que toca.
               El paso es de 15 m cada 150 ms (unos 6,5 fotogramas por segundo): con pasos
               más pequeños la app se pasaba el rato repintando el mapa y se bloqueaba. */
            let paso = 15.0
            while restante > 0 && !Task.isCancelled && self.demoActiva {
                aqui = self.desplazar(aqui, rumbo: 0, metros: paso)
                self.posicion = CLLocation(
                    coordinate: aqui, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                    course: 0, speed: 25, timestamp: Date()
                )
                self.velocidadKmh = 90
                self.rumbo = 0
                self.actualizarProgreso()
                self.comprobarAviso()
                restante -= paso
                // Se le devuelve el turno al sistema: sin esto el bucle se come el hilo
                // principal y iOS acaba matando la app (que es lo que pasaba).
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            guard self.demoActiva else { return }
            AvisosFlotantes.compartido.bien("Demo terminada")
            self.pararDemo()
        }
    }

    func pararDemo() {
        demoTarea?.cancel()
        demoTarea = nil
        guard demoActiva else { return }
        demoActiva = false
        if let id = demoRadarId {
            radares.removeAll { $0.id == id }
        }
        demoRadarId = nil
        ultimoAvisado = nil
        ultimoPitido = Date.distantPast
        radarAvisando = nil
        destino = nil
        rutas = []
        navegando = false
        trafico = nil
        quedaKm = nil
        totalKm = nil
        avisos.callar()
        guardarSesion()
    }

    // ══════════════════════════════════════════════════════════════════════════
    // PERSISTENCIA: LA APP RECUERDA DÓNDE ESTABAS
    // ══════════════════════════════════════════════════════════════════════════
    /* Antes, al cerrar la app se perdía TODO: el viaje, las paradas hechas, el perfil y si
       ibas navegando. Ahora se guarda en el propio móvil (UserDefaults) cada vez que algo
       cambia y al mandar la app al fondo, y se recupera al volver a abrirla. */
    private static let claveSesion = "ubixavi_nativo_sesion"

    func guardarSesion() {
        var datos: [String: Any] = [:]
        datos["paradas"] = paradas.map { $0.id }
        datos["hechas"] = Array(hechas)
        datos["perfil"] = perfil
        datos["navegando"] = navegando
        datos["elegida"] = elegida
        datos["perfilRuta"] = perfil
        if let destino = destino { datos["destino"] = destino.id }
        UserDefaults.standard.set(datos, forKey: Estado.claveSesion)
    }

    /// El viaje, como diccionario (para mandarlo al respaldo del servidor)
    var viajeComoDiccionario: [String: Any] {
        var datos: [String: Any] = [:]
        datos["paradas"] = paradas.map { $0.id }
        datos["hechas"] = Array(hechas)
        datos["perfil"] = perfil
        datos["navegando"] = navegando
        datos["elegida"] = elegida
        if let destino = destino { datos["destino"] = destino.id }
        return datos
    }

    /// Recupera el viaje de la vez anterior (las paradas se buscan por su identificador)
    /// Si `datos` viene vacío, se usa el que hay guardado en este móvil.
    /* AL CERRAR LA APP **NO SE RECUERDA EL VIAJE**: el «Ir a» empieza siempre en blanco
       (se borra lo guardado y no se restaura). Los AJUSTES sí se recuerdan. */
    func restaurarSesion(con almacen: Almacen, datos servidos: [String: Any]? = nil) async {
        UserDefaults.standard.removeObject(forKey: Estado.claveSesion)
        return
    }

    private func restaurarSesionVieja(con almacen: Almacen, datos servidos: [String: Any]? = nil) async {
        let datos = servidos ?? UserDefaults.standard.dictionary(forKey: Estado.claveSesion)
        guard let datos = datos else { return }
        let ids = datos["paradas"] as? [String] ?? []
        let guardadas = ids.compactMap { almacen.ubicacion($0) }
        guard !guardadas.isEmpty else { return }

        paradas = guardadas
        hechas = Set(datos["hechas"] as? [Int] ?? [])
        perfil = datos["perfil"] as? String ?? "coche"
        elegida = datos["elegida"] as? Int ?? 0
        if let idDestino = datos["destino"] as? String, let ubicacion = almacen.ubicacion(idDestino) {
            destino = ubicacion
        } else {
            destino = guardadas.last
        }
        navegando = (datos["navegando"] as? Bool ?? false) && destino != nil
        // Si no ibas navegando, se queda el destino puesto pero sin arrancar la ruta
        if destino != nil {
            await pedirRuta()
            await cargarTramos()
        }
    }

    /// Distancia que queda hasta el destino por la ruta elegida
    var distanciaRestanteKm: Double? {
        guard let pos = posicion, let destino = destino else { return nil }
        return CLLocation(latitude: pos.coordinate.latitude, longitude: pos.coordinate.longitude)
            .distance(from: CLLocation(latitude: destino.lat, longitude: destino.lng)) / 1000
    }
}
