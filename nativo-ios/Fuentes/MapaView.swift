/* EL MAPA: MapKit tal cual, con SUS GESTOS.

   Aquí está la diferencia de fondo con la versión anterior: acercar y alejar, girar con
   dos dedos y arrastrar los lleva EL SISTEMA (Apple). No hay ni una línea midiendo dedos,
   ni puentes, ni CSS. Por eso va fino y no hay saltos.

   · «Siguiendo con rumbo» (userTrackingMode = .followWithHeading): el mapa se centra en
     ti y GIRA con la brújula, como al navegar en Google Maps. MapKit mantiene el zoom que
     tú elijas y no se desactiva solo.
   · El zoom de navegación se pone una vez al empezar (unos 360 m de ancho, el zoom 17 de
     Google Maps) y a partir de ahí manda el dedo.
   · La brújula de arriba (showsCompass) la pone MapKit: tocándola vuelve a orientarse
     hacia el norte.
*/
import SwiftUI
import MapKit

/// Línea de ruta con SU color y SU grosor (MKPolyline no admite datos propios)
final class LineaRuta: MKPolyline {
    var color: UIColor = .systemBlue
    var grosor: CGFloat = 8
    var elegida = true
}

/* EL CONTROL DEL MAPA: LA CÁMARA, CON LOS TRES TAMAÑOS DE CUALQUIER APP DE NAVEGACIÓN.

   · AL ABRIR LA APP .......... ~1,5 km (vista normal, se ve el barrio y las calles)
   · AL VER LAS RUTAS ......... se encuadra la ruta entera (se deja de seguirte)
   · AL EMPEZAR A NAVEGAR ..... ~300 m (SE ACRECA para ver por dónde vas)
   · AL SALIR DE NAVEGAR ...... vuelve a ~1,5 km
   Google Maps, Apple Maps y Waze hacen exactamente esto: al darle a Iniciar se ACRECA el
   mapa al nivel de calle, y al salir vuelve a la vista normal.

   POR QUÉ LA CÁMARA LA LLEVA LA APP Y NO `userTrackingMode`:
   `MKMapView.setUserTrackingMode(.followWithHeading)` está pensado para «sígueme», pero
   **impone su propia altitud de cámara**: por más que le pongas la tuya antes, después o
   por `didChange`, MapKit la reescribe al terminar SU animación. El resultado es justo el
   que has visto: «hace un salto y vuelve al mismo tamaño». Es un comportamiento conocido y
   por eso las apps de navegación NO usan ese modo: mantienen la cámara ellas, con
   `MKMapCamera` y una ALTITUD FIJA (`centerCoordinateDistance`), centrada en la posición y
   con el rumbo. Eso es lo que se hace aquí, y así el zoom es EXACTO y no hay saltos.

   Y TUS DEDOS MANDAN: si haces pinza, se adopta TU zoom y se sigue usando; si arrastras y
   el mapa se va de tu posición, se deja de seguir y sale el botón de centrar. */
@MainActor
final class ControladorMapa: ObservableObject {
    weak var mapa: MKMapView?

    /* LAS CAPAS DEL MAPA: qué quieres ver encima del mapa y de qué color va la ruta.
       Se eligen con el botón de capas del mapa y se guardan (son persistentes). */
    struct Capas: Equatable {
        var ubicaciones = true
        var radares = true
        var puntosInteres = false
        /// Las capas que da MapKit: tráfico, edificios en 3D, mapa apagado y satélite
        var trafico = false
        var edificios = false
        var mapaApagado = false
        var satelite = false
        /// El color de la ruta elegida (las alternativas van en azul)
        var colorRuta = "#d4a843"

        /// El color de la ruta, en UIColor
        var colorDeLaRuta: UIColor { ControladorMapa.colorDesde(colorRuta) }

        init(
            ubicaciones: Bool = true,
            radares: Bool = true,
            puntosInteres: Bool = false,
            trafico: Bool = false,
            edificios: Bool = false,
            mapaApagado: Bool = false,
            satelite: Bool = false,
            colorRuta: String = "#d4a843"
        ) {
            self.ubicaciones = ubicaciones
            self.radares = radares
            self.puntosInteres = puntosInteres
            self.trafico = trafico
            self.edificios = edificios
            self.mapaApagado = mapaApagado
            self.satelite = satelite
            self.colorRuta = colorRuta
        }
    }

    /// Un color a partir de su código (#rrggbb)
    nonisolated static func colorDesde(_ hex: String) -> UIColor {
        var texto = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if texto.hasPrefix("#") { texto.removeFirst() }
        guard texto.count == 6, let valor = UInt64(texto, radix: 16) else { return .systemBlue }
        return UIColor(
            red: CGFloat((valor & 0xFF0000) >> 16) / 255,
            green: CGFloat((valor & 0x00FF00) >> 8) / 255,
            blue: CGFloat(valor & 0x0000FF) / 255,
            alpha: 1
        )
    }

    /// ¿El mapa te está siguiendo? Si lo arrastras, pasa a false y sale el botón de centrar
    @Published var siguiendo = true
    /// ¿Está el mapa girado?
    @Published var girado = false
    /// La ubicación cuyo pin has tocado (para abrir su ficha)
    @Published var ubicacionTocada: String?
    /// La última posición conocida
    var ultimaPosicion: CLLocationCoordinate2D?

    /// LA VISTA NORMAL (al abrir la app): 1,5 km
    static let distanciaNormal: CLLocationDistance = 1500
    /* EL ZOOM DE NAVEGACIÓN, COMO APPLE MAPS: unos 450 m de distancia de cámara (se ve la calle
       por la que vas y las siguientes) y el mapa INCLINADO unos 50°, que es como lo pone Apple
       al darle a «IR»: la carretera se ve en perspectiva y tú quedas en la parte de abajo. */
    static let distanciaNavegacion: CLLocationDistance = 450
    /// La inclinación al navegar, como Apple Maps
    static let inclinacionNavegacion: Double = 50

    /* EL ICONO DEL FINAL DE LA RUTA: una gota ROJA y MUY PUNTEAGUDA.
       No se usa la chincheta de MapKit porque su punta es corta y redondeada: aquí se
       dibuja a mano (un círculo arriba y una punta afilada y larga abajo) para que quede
       como pediste. Se dibuja una vez y se reutiliza. */
    static let imagenDestino: UIImage = {
        let ancho: CGFloat = 60
        let alto: CGFloat = 84
        let radio: CGFloat = ancho / 2 - 2
        let centroCirculo = CGPoint(x: ancho / 2, y: radio + 2)
        let formato = UIGraphicsImageRendererFormat.default()
        formato.opaque = false
        let render = UIGraphicsImageRenderer(size: CGSize(width: ancho, height: alto), format: formato)
        return render.image { contexto in
            let ctx = contexto.cgContext
            // La gota: círculo + punta afilada (la punta llega hasta abajo del todo)
            let punta = CGPoint(x: ancho / 2, y: alto - 1)
            let camino = UIBezierPath()
            camino.addArc(
                withCenter: centroCirculo,
                radius: radio,
                startAngle: .pi * 0.86,
                endAngle: .pi * 0.14,
                clockwise: true
            )
            camino.addLine(to: punta)
            camino.close()
            ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 6, color: UIColor.black.withAlphaComponent(0.55).cgColor)
            UIColor.systemRed.setFill()
            camino.fill()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            // El borde blanco, para que se vea sobre cualquier mapa
            UIColor.white.setStroke()
            camino.lineWidth = 3
            camino.stroke()
            // El centro blanco (el «ojo» del pin)
            let ojo = UIBezierPath(ovalIn: CGRect(
                x: centroCirculo.x - radio * 0.42,
                y: centroCirculo.y - radio * 0.42,
                width: radio * 0.84,
                height: radio * 0.84
            ))
            UIColor.white.setFill()
            ojo.fill()
        }
    }()

    /// La altura que manda la app ahora mismo. Cambia al navegar y con tu pinza.
    var distanciaDeseada: CLLocationDistance = ControladorMapa.distanciaNormal
    /// La última altura que hemos pedido nosotros (para distinguir tu pinza de lo nuestro)
    private(set) var ultimaPedida: CLLocationDistance = ControladorMapa.distanciaNormal
    /// Poner la cámara aunque no haya cambiado nada (al iniciar, al salir, al centrar)
    var forzarCamara = true
    /// ¿Está el 3D activo? Entonces al navegar el mapa va inclinado (y en 2D, plano)
    @Published var mapa3DActivo = false
    /// El rumbo que lleva el mapa, para que la brújula gire
    @Published var rumboActual: Double = 0
    /// ¿Está puesta la capa de EDIFICIOS EN 3D? Entonces la cámara va inclinada (si no, los
    /// edificios se ven planos y parece que la capa no hace nada)
    var inclinacion3D: Double = 0

    /// EL COCHE Y LA PERSONA: las dos imágenes de navegación (sin fondo, de `recursos/`).
    /// El coche va mirando hacia arriba, así que apunta hacia donde vas (el mapa es el que
    /// gira). La persona se usa cuando el perfil de la ruta es «A pie».
    static func imagenDeNavegacion(aPie: Bool) -> UIImage? {
        UIImage(named: aPie ? "PersonaNav" : "CocheNav")
            ?? UIImage(named: aPie ? "CocheNav" : "PersonaNav")
            ?? UIImage(named: "Logo")
    }

    /// PONE LA CÁMARA: centrada en ti, con la ALTURA pedida y mirando hacia tu rumbo
    /* `inclinacion` (pitch) es lo que hace que se vean LOS EDIFICIOS EN 3D: con la cámara
       plana (0°) los edificios se pintan como manchas en el suelo y parece que la capa no
       hace nada. Con 45° se levantan y se ven de verdad (y hacen falta edificios cerca:
       al acercar el mapa aparecen). */
    func ponerCamara(
        centro: CLLocationCoordinate2D,
        distancia: CLLocationDistance,
        rumbo: Double,
        animada: Bool,
        inclinacion: Double = 0,
        en mapa: MKMapView
    ) {
        distanciaDeseada = distancia
        ultimaPedida = distancia
        forzarCamara = false
        let camara = MKMapCamera(lookingAtCenter: centro, fromDistance: distancia, pitch: inclinacion, heading: rumbo)
        if animada {
            /* LA ANIMACIÓN VA DESPACIO A PROPÓSITO: la de MapKit dura 0,3 s y se ve de golpe.
               Envolviéndola en `UIView.animate` se controla la duración (1,4 s), y con la curva
               suave el acercamiento al Iniciar y el alejamiento al Salir se ven bien. */
            UIView.animate(withDuration: 1.4, delay: 0, options: [.curveEaseInOut]) {
                mapa.camera = camara
            }
        } else {
            mapa.setCamera(camara, animated: false)
        }
    }

    /// PONE EL MAPA MIRANDO AL NORTE (el botón de la brújula)
    func ponerNorte() {
        guard let mapa = mapa else { return }
        var camara = mapa.camera
        camara.heading = 0
        UIView.animate(withDuration: 0.6, delay: 0, options: [.curveEaseInOut]) {
            mapa.camera = camara
        }
    }

    /// ACRCA O ALEJA a la altura que toca, sin mover el centro (lo usan los botones)
    func ponerAltura(_ distancia: CLLocationDistance, en mapa: MKMapView) {
        distanciaDeseada = distancia
        ultimaPedida = distancia
        var camara = mapa.camera
        camara.centerCoordinateDistance = distancia
        mapa.setCamera(camara, animated: true)
    }

    /// Apunta la altura que se ha pedido (para distinguir tu pinza de lo nuestro)
    func anotarPedida(_ distancia: CLLocationDistance) {
        ultimaPedida = distancia
    }

    /// Volver a la vista del modo actual (el botón de centrar)
    func volverAlTamanoQueToca(navegando: Bool) {
        siguiendo = true
        distanciaDeseada = navegando ? ControladorMapa.distanciaNavegacion : ControladorMapa.distanciaNormal
        forzarCamara = true
    }

    /* LA CÁMARA A MANO, sólo para la DEMO: ahí la posición es simulada y MapKit seguiría tu
       posición de verdad, así que el seguimiento se apaga y la cámara la mueve la app. */
    func ponerCamaraDeDemo(_ centro: CLLocationCoordinate2D) {
        guard let mapa = mapa else { return }
        mapa.userTrackingMode = .none
        mapa.camera = MKMapCamera(
            lookingAtCenter: centro,
            fromDistance: ControladorMapa.distanciaNavegacion,
            pitch: inclinacion3D,
            heading: 0
        )
    }

    /// Ver la ruta entera de un vistazo (deja de seguirte)
    /* EL ENCUADRE ES RESPONSIVE: los márgenes se calculan con el TAMAÑO DE LA PANTALLA (un
       12 % arriba, un 30 % abajo —donde van los paneles— y un 6 % a los lados), no con
       píxeles fijos. Así la ruta se ve SIEMPRE lo más grande posible, aprovechando el ancho
       de la pantalla, y no se queda pequeña en una ruta corta como la de Vilanova. */
    func encuadrarRuta() {
        guard let mapa = mapa,
              let linea = mapa.overlays.compactMap({ $0 as? LineaRuta }).first(where: { $0.elegida }) else { return }
        mapa.userTrackingMode = .none
        siguiendo = false
        let ancho = max(mapa.bounds.width, 320)
        let alto = max(mapa.bounds.height, 480)
        // Si la ruta es muy corta (casi un punto), se le da un mínimo: así no se acerca tanto
        // que acabas viendo una sola calle
        var rect = linea.boundingMapRect
        let minimo = MKMapRect(
            x: rect.midX - 250,
            y: rect.midY - 250,
            width: 500,
            height: 500
        )
        if rect.size.width < 500 || rect.size.height < 500 { rect = rect.union(minimo) }
        let margenes = UIEdgeInsets(
            top: alto * 0.12,
            left: ancho * 0.06,
            bottom: alto * 0.30,
            right: ancho * 0.06
        )
        // Al SALIR, el alejamiento va igual de despacio que el acercamiento al iniciar
        UIView.animate(withDuration: 1.4, delay: 0, options: [.curveEaseInOut]) {
            mapa.setVisibleMapRect(rect, edgePadding: margenes, animated: false)
        }
    }

    // ══ LA CÁMARA DEL MAPA SE RECUERDA ══════════════════════════════════════════
    /* Al cerrar la app se guarda dónde estabas mirando (centro, zoom y giro) y al volver
       se abre ahí mismo, no en el sitio por defecto. */
    private static let claveCamara = "ubixavi_nativo_camara"

    func guardarCamara(_ mapa: MKMapView) {
        let region = mapa.region
        let datos: [String: Double] = [
            "lat": region.center.latitude,
            "lng": region.center.longitude,
            "latDelta": region.span.latitudeDelta,
            "lngDelta": region.span.longitudeDelta,
            "heading": mapa.camera.heading,
        ]
        UserDefaults.standard.set(datos, forKey: ControladorMapa.claveCamara)
    }

    static func camaraGuardada() -> (centro: CLLocationCoordinate2D, span: MKCoordinateSpan, heading: Double)? {
        guard let datos = UserDefaults.standard.dictionary(forKey: claveCamara),
              let lat = datos["lat"] as? Double,
              let lng = datos["lng"] as? Double,
              let latDelta = datos["latDelta"] as? Double,
              let lngDelta = datos["lngDelta"] as? Double,
              latDelta > 0, lngDelta > 0 else { return nil }
        return (
            CLLocationCoordinate2D(latitude: lat, longitude: lng),
            MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta),
            datos["heading"] as? Double ?? 0
        )
    }
}

struct MapaView: UIViewRepresentable {
    @ObservedObject var estado: Estado
    @ObservedObject var controlador: ControladorMapa
    /// Todas tus ubicaciones: se pintan como chinchetas (como la pestaña Mapa de la web)
    var ubicaciones: [Ubicacion] = []
    /// Qué capas quieres ver (ubicaciones, radares, puntos de interés) y el color de la ruta
    var capas: ControladorMapa.Capas = ControladorMapa.Capas()
    /// El color de la categoría de cada una, para pintar la chincheta
    var colorDeCategoria: (String) -> UIColor = { _ in .systemTeal }

    func makeCoordinator() -> Coordinador { Coordinador(controlador: controlador) }

    func makeUIView(context: Context) -> MKMapView {
        let mapa = MKMapView(frame: .zero)
        mapa.delegate = context.coordinator
        mapa.showsUserLocation = true
        mapa.showsCompass = false
        mapa.showsScale = false
        // Inclinar con dos dedos (el «3D»): sólo tiene sentido si quieres ver los edificios
        mapa.isPitchEnabled = true
        // La brújula del sistema va arriba a la derecha y estorba: se quita y se pone un botón
        mapa.isRotateEnabled = true // girar con dos dedos: lo hace MapKit
        mapa.isZoomEnabled = true // acercar/alejar: lo hace MapKit
        mapa.isScrollEnabled = true // arrastrar: lo hace MapKit
        mapa.pointOfInterestFilter = .excludingAll
        controlador.mapa = mapa
        // Si tenías el 3D puesto, el mapa arranca inclinado
        controlador.inclinacion3D = UserDefaults.standard.bool(forKey: "mapa3D") ? 60 : 0
        /* ARRANQUE: se abre en la zona donde lo dejaste SÓLO como primer fotograma (para
           no empezar en Barcelona). En cuanto llega tu posición, la cámara salta a ti con
           el zoom de calle: es lo que hace Google Maps al abrir. */
        if let camara = ControladorMapa.camaraGuardada() {
            mapa.setRegion(MKCoordinateRegion(center: camara.centro, span: camara.span), animated: false)
            controlador.ultimaPosicion = camara.centro
        } else {
            mapa.setRegion(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 41.387, longitude: 2.17),
                    latitudinalMeters: 4000,
                    longitudinalMeters: 4000
                ),
                animated: false
            )
        }
        return mapa
    }

    func updateUIView(_ mapa: MKMapView, context: Context) {
        context.coordinator.colorDeCategoria = colorDeCategoria
        context.coordinator.actualizar(mapa: mapa, estado: estado, ubicaciones: ubicaciones, capas: capas)
    }

    final class Coordinador: NSObject, MKMapViewDelegate {
        private let controlador: ControladorMapa
        var colorDeCategoria: (String) -> UIColor = { _ in .systemTeal }

        init(controlador: ControladorMapa) {
            self.controlador = controlador
        }

        /// Chinchetas de TUS ubicaciones (con el color de su categoría)
        private var pinesUbicacion: [String: MKPointAnnotation] = [:]
        private var firmaUbicaciones = ""
        private var colorPorPin: [ObjectIdentifier: UIColor] = [:]
        private var idPorPin: [ObjectIdentifier: String] = [:]
        private var firmaRutas = ""
        private var firmaRadares = ""
        private var firmaDestino = ""
        /// ¿Ya se ha puesto la cámara de arranque? (sólo la primera vez)
        private var siguiendoAlArrancar = false
        /// ¿Vas navegando? (entonces el mapa se acerca al nivel de calle)
        private var navegando = false
        /// ¿Ya ibas navegando en la actualización anterior? (para detectar el momento de
        /// darle a «Iniciar» y ACERCAR el mapa y el de «Salir» y volver a la vista normal)
        private var navegandoAntes = false
        /// ¿Está en marcha la DEMO? (entonces el mapa sigue la posición simulada)
        private var enDemo = false
        /// ¿Están puestos los puntos de interés del sistema? (para no repetirlo)
        private var mostrandoPuntosInteres = false
        /// La configuración del mapa que hay puesta (para no repetirla en cada repintado)
        private var mapaApagadoPuesto = false
        private var satelitePuesto = false
        /// Lo último que le hemos pedido a la cámara (para no repetirlo en cada repintado)
        private var camaraCentro: CLLocationCoordinate2D?
        private var camaraDistancia: CLLocationDistance = 0
        private var camaraRumbo: Double = -999
        /// La inclinación (pitch) que hay puesta, para los edificios en 3D
        private var camaraInclinacion: Double = 0
        /// ¿Vas a pie? (entonces tu posición es la PERSONA, no el coche)
        private var aPie = false
        /// La vista de tu posición (para cambiar coche/persona sin recrearla)
        private weak var vistaDeMiPosicion: MKAnnotationView?
        private var pines: [String: MKPointAnnotation] = [:]
        private var pinDestino: MKPointAnnotation?

        func actualizar(
            mapa: MKMapView,
            estado: Estado,
            ubicaciones: [Ubicacion] = [],
            capas: ControladorMapa.Capas = ControladorMapa.Capas()
        ) {
            // La posición que se recuerda para centrar y para guardar la cámara
            if let pos = estado.posicion?.coordinate { controlador.ultimaPosicion = pos }

            /* ── LAS CAPAS DEL MAPA ──────────────────────────────────────────────
               · puntos de interés (bares, tiendas…): los del sistema
               · TRÁFICO: los colores de las carreteras según cómo están
               · EDIFICIOS en 3D (aparecen al acercar)
               · MAPA APAGADO: en gris, para que resalte tu ruta
               · SATÉLITE: foto con las etiquetas encima                              */
            if capas.puntosInteres != mostrandoPuntosInteres {
                mostrandoPuntosInteres = capas.puntosInteres
                mapa.pointOfInterestFilter = capas.puntosInteres ? .includingAll : .excludingAll
            }
            if mapa.showsTraffic != capas.trafico { mapa.showsTraffic = capas.trafico }
            if mapa.showsBuildings != capas.edificios {
                mapa.showsBuildings = capas.edificios
                // Al encender/apagar el 3D hay que volver a poner la cámara: con la cámara
                // plana los edificios se ven como manchas y parece que no hace nada
                controlador.inclinacion3D = capas.edificios ? 45 : 0
                controlador.forzarCamara = true
            }
            if capas.mapaApagado != mapaApagadoPuesto || capas.satelite != satelitePuesto {
                mapaApagadoPuesto = capas.mapaApagado
                satelitePuesto = capas.satelite
                if capas.satelite {
                    mapa.preferredConfiguration = MKHybridMapConfiguration()
                } else {
                    let configuracion = MKStandardMapConfiguration()
                    configuracion.emphasisStyle = capas.mapaApagado ? .muted : .default
                    configuracion.pointOfInterestFilter = capas.puntosInteres ? .includingAll : .excludingAll
                    mapa.preferredConfiguration = configuracion
                }
            }

            // ── 0) TUS UBICACIONES como chinchetas (cuando NO vas navegando) ──
            let firmaU = (estado.navegando || !capas.ubicaciones)
                ? ""
                : ubicaciones.filter { $0.tieneCoordenadas }.map { "\($0.id)-\($0.categoryId)" }.joined(separator: ",")
            if firmaU != firmaUbicaciones {
                firmaUbicaciones = firmaU
                for (_, pin) in pinesUbicacion {
                    mapa.removeAnnotation(pin)
                }
                pinesUbicacion.removeAll()
                colorPorPin.removeAll()
                idPorPin.removeAll()
                if !estado.navegando && capas.ubicaciones {
                    for ubicacion in ubicaciones where ubicacion.tieneCoordenadas {
                        let pin = MKPointAnnotation()
                        pin.coordinate = ubicacion.coordinate
                        pin.title = ubicacion.name
                        pin.subtitle = "ubicacion"
                        mapa.addAnnotation(pin)
                        pinesUbicacion[ubicacion.id] = pin
                        colorPorPin[ObjectIdentifier(pin)] = colorDeCategoria(ubicacion.categoryId)
                        idPorPin[ObjectIdentifier(pin)] = ubicacion.id
                    }
                }
            }
            // ── 1) Las rutas ────────────────────────────────────────────────────
            /* ANTES DE INICIAR: la ELEGIDA en tu color con funda blanca, y las ALTERNATIVAS
                 en azul brillante, más finas y sin funda.
               AL NAVEGAR: SOLO la ruta que llevas, más ANCHA (casi lo que ocupa un carril en
                 pantalla, un poquito menos) y SIN funda blanca: así se ve limpia por dónde
                 vas, como en Google Maps. */
            let alNavegar = estado.navegando
            let firma = estado.rutas.map { "\(Int($0.distKm * 100))-\($0.puntos.count)" }.joined(separator: "|")
                + "#\(estado.elegida)-\(capas.colorRuta)-\(alNavegar)"
            if firma != firmaRutas {
                firmaRutas = firma
                mapa.removeOverlays(mapa.overlays)
                for (indice, ruta) in estado.rutas.enumerated() {
                    let esElegida = indice == estado.elegida
                    // Al navegar, las alternativas no se pintan: sólo la que llevas
                    if alNavegar && !esElegida { continue }
                    let coordenadas = ruta.coordenadas
                    guard coordenadas.count > 1 else { continue }
                    // La funda blanca, sólo en la vista previa (al navegar no se quiere)
                    if esElegida && !alNavegar {
                        var puntosFunda = coordenadas
                        let funda = LineaRuta(coordinates: &puntosFunda, count: puntosFunda.count)
                        funda.elegida = true
                        funda.color = UIColor.white.withAlphaComponent(0.85)
                        funda.grosor = 13
                        mapa.addOverlay(funda, level: .aboveRoads)
                    }
                    var puntos = coordenadas
                    let linea = LineaRuta(coordinates: &puntos, count: puntos.count)
                    linea.elegida = esElegida
                    linea.color = esElegida
                        ? capas.colorDeLaRuta
                        : UIColor(red: 0.18, green: 0.52, blue: 0.98, alpha: 1) // #2e85fa
                    // El ancho de siempre; al navegar sólo cambia que no lleva funda blanca
                    linea.grosor = esElegida ? 8 : 5
                    mapa.addOverlay(linea, level: .aboveRoads)
                }
                /* MIENTRAS LA RUTA NO ESTÁ INICIADA se encuadra la RUTA ENTERA (el tamaño de
                   «elegir destino»), con el encuadre RESPONSIVE de `encuadrarRuta`. Si YA vas
                   navegando NO se toca: ahí manda el zoom que se pone al darle a Iniciar. */
                if !estado.navegando { controlador.encuadrarRuta() }
            }

            // ── 2) Los radares (sólo si quieres verlos: capas.radares) ───────────
            let firmaRadar = (capas.radares ? estado.radares.map { $0.id }.joined(separator: ",") : "sin-radares")
                + "#\(estado.radarAvisando ?? "")"
            if firmaRadar != firmaRadares {
                firmaRadares = firmaRadar
                var vistos = Set<String>()
                for radar in estado.radares where capas.radares {
                    vistos.insert(radar.id)
                    let pin: MKPointAnnotation
                    if let existente = pines[radar.id] {
                        pin = existente
                    } else {
                        pin = MKPointAnnotation()
                        pines[radar.id] = pin
                        mapa.addAnnotation(pin)
                    }
                    pin.coordinate = radar.coordinate
                    pin.title = radar.titulo
                    pin.subtitle = radar.id == estado.radarAvisando ? "avisando" : nil
                }
                for (id, pin) in pines where !vistos.contains(id) {
                    mapa.removeAnnotation(pin)
                    pines.removeValue(forKey: id)
                }
            }

            // ── 3) El destino ───────────────────────────────────────────────────
            let firmaD = estado.destino?.id ?? ""
            if firmaD != firmaDestino {
                firmaDestino = firmaD
                if let anterior = pinDestino {
                    mapa.removeAnnotation(anterior)
                    pinDestino = nil
                }
                if let destino = estado.destino {
                    let pin = MKPointAnnotation()
                    pin.coordinate = destino.coordinate
                    pin.title = destino.name
                    mapa.addAnnotation(pin)
                    pinDestino = pin
                }
            }

            // ── 4) EL TAMAÑO DEL MAPA ───────────────────────────────────────────
            /* LOS TRES MOMENTOS:
                 · con una ruta SIN iniciar ... la RUTA ENTERA (el tamaño de «elegir destino»)
                 · al darle a INICIAR ....... SE ACRECA a ti (1,5 km) y te sigue
                 · al darle a SALIR ......... vuelve a la RUTA ENTERA
               Da igual desde dónde la inicies (una ubicación, el swipe-row, la ficha o el
               botón del panel): el zoom al iniciar es siempre el mismo.
               La cámara la pone la app con una ALTITUD FIJA (no el modo «siguiendo» de
               MapKit, que impone la suya y hacía el salto). Tus dedos mandan. */
            enDemo = estado.demoActiva

            // El punto de tu posición: el COCHE (o la PERSONA a pie) mientras la demo no
            // esté en marcha (en la demo la posición es de mentira y el punto real sobra).
            if mapa.showsUserLocation == estado.demoActiva {
                mapa.showsUserLocation = !estado.demoActiva
            }
            let perfilAPie = estado.perfil == "pie"
            if perfilAPie != aPie {
                aPie = perfilAPie
                // El coche y la persona se cambian EN EL SITIO (si no, al recrear la vista no
                // se enteraba y seguía saliendo el coche yendo a pie)
                if let vista = vistaDeMiPosicion { ponerImagenDeMiPosicion(en: vista) }
            }

            navegando = estado.navegando
            let empiezaANavegar = estado.navegando && !navegandoAntes
            let acabaDeNavegar = !estado.navegando && navegandoAntes
            navegandoAntes = estado.navegando

            if estado.demoActiva {
                if let pos = estado.posicion {
                    controlador.ponerCamaraDeDemo(pos.coordinate)
                    if !controlador.siguiendo { controlador.siguiendo = true }
                }
            } else {
                if empiezaANavegar {
                    // AL INICIAR: SE ACRECA a ti y te sigue (el tamaño de navegar)
                    controlador.siguiendo = true
                    controlador.distanciaDeseada = ControladorMapa.distanciaNavegacion
                    controlador.forzarCamara = true
                    siguiendoAlArrancar = true
                }
                if acabaDeNavegar {
                    // AL SALIR: vuelve a verse la RUTA ENTERA
                    controlador.encuadrarRuta()
                }
                if !siguiendoAlArrancar, estado.destino == nil, mejorPosicion(mapa, estado) != nil {
                    // AL ABRIR LA APP SIN DESTINO: vista normal, centrada en ti
                    controlador.siguiendo = true
                    controlador.distanciaDeseada = ControladorMapa.distanciaNormal
                    controlador.forzarCamara = true
                    siguiendoAlArrancar = true
                }

                // Y la cámara al tamaño que toca, centrada en ti, cuando de verdad cambia
                // algo (no en cada repintado: eso daría tirones)
                if controlador.siguiendo, let pos = mejorPosicion(mapa, estado) {
                    let rumbo = estado.rumbo >= 0 ? estado.rumbo : mapa.camera.heading
                    aplicarCamaraSiToca(mapa, pos: pos, distancia: controlador.distanciaDeseada, rumbo: rumbo)
                }
            }
        }

        /// La cámara, sólo si cambia la posición, el zoom o el rumbo (o si se pide a la fuerza)
        private func aplicarCamaraSiToca(
            _ mapa: MKMapView,
            pos: CLLocationCoordinate2D,
            distancia: CLLocationDistance,
            rumbo: Double
        ) {
            let seMueve = camaraCentro.map {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                    .distance(from: CLLocation(latitude: pos.latitude, longitude: pos.longitude)) > 8
            } ?? true
            let cambiaElZoom = abs(camaraDistancia - distancia) > 1
            let cambiaElRumbo = abs(camaraRumbo - rumbo) > 5
            let cambiaLaInclinacion = abs(camaraInclinacion - controlador.inclinacion3D) > 2
            if cambiaLaInclinacion { camaraInclinacion = controlador.inclinacion3D }
            guard controlador.forzarCamara || seMueve || cambiaElZoom || cambiaElRumbo || cambiaLaInclinacion else { return }
            // Si el salto es grande (te habías ido lejos), mejor sin animación: una animación
            // larga entre dos sitios lejanos se ve rara
            let saltoGrande = camaraCentro.map {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                    .distance(from: CLLocation(latitude: pos.latitude, longitude: pos.longitude)) > 300
            } ?? false
            camaraCentro = pos
            camaraDistancia = distancia
            camaraRumbo = rumbo
            controlador.ponerCamara(
                centro: pos,
                distancia: distancia,
                rumbo: rumbo,
                animada: !saltoGrande,
                /* El botón 3D/2D MANDA TAMBIÉN AL NAVEGAR: en 2D el mapa va plano, y en
                   3D se inclina. Antes al navegar siempre iba inclinado y no se podía cambiar. */
                inclinacion: navegando
                    ? (controlador.mapa3DActivo ? ControladorMapa.inclinacionNavegacion : 0)
                    : controlador.inclinacion3D,
                en: mapa
            )
        }

        /// La mejor posición que se conoce: la de la app o, si aún no hay, la del mapa
        private func mejorPosicion(_ mapa: MKMapView, _ estado: Estado) -> CLLocationCoordinate2D? {
            estado.posicion?.coordinate
                ?? mapa.userLocation.location?.coordinate
                ?? controlador.ultimaPosicion
        }

        // ── Cómo se pintan las líneas y los pines ────────────────────────────────
        /* Con la cámara en manos de la app, el modo de seguimiento de MapKit no se usa. */
        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            let girado = abs(mapView.camera.heading) > 2
            if controlador.girado != girado { controlador.girado = girado }
        }

        /* TUS DEDOS MANDAN, SIN EXCEPCIONES.
           En cuanto un dedo TOCA y mueve el mapa —da igual ARRASTRAR que ACRECAR o ALEJAR
           con la pinza, o girar— se deja de seguirte AL INSTANTE: el mapa se queda QUIETO,
           con el zoom que hayas elegido, y no vuelve solo a tu posición. Y sale el botón de
           centrar para volver cuando tú quieras.
           (Antes la pinza no soltaba el mapa: se adoptaba el zoom pero se seguía centrando
           solo, y por eso al acercar o alejar el mapa se volvía a su centro.) */
        private func hayDedoEnElMapa(_ mapView: MKMapView) -> Bool {
            for gesto in mapView.subviews.first?.gestureRecognizers ?? [] {
                if gesto.state == .began || gesto.state == .changed { return true }
            }
            return false
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            guard hayDedoEnElMapa(mapView), controlador.siguiendo else { return }
            // Has tocado el mapa: se suelta y se queda como lo dejes
            controlador.siguiendo = false
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let girado = abs(mapView.camera.heading) > 2
            if controlador.girado != girado { controlador.girado = girado }
            if !enDemo { controlador.guardarCamara(mapView) }
        }

        /// MapKit también avisa de tu posición: sirve para centrar aunque la app no tenga
        /// todavía su propio dato del GPS.
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            controlador.ultimaPosicion = userLocation.coordinate
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let linea = overlay as? LineaRuta {
                let render = MKPolylineRenderer(polyline: linea)
                render.strokeColor = linea.color
                render.lineWidth = linea.grosor
                render.lineCap = .round
                render.lineJoin = .round
                return render
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        /// La imagen de tu posición: el COCHE o la PERSONA, sin fondo, centrada en el punto
        private func ponerImagenDeMiPosicion(en vista: MKAnnotationView) {
            let lado: CGFloat = aPie ? 40 : 48
            vista.image = ControladorMapa.imagenDeNavegacion(aPie: aPie)?.withRenderingMode(.alwaysOriginal)
            vista.bounds = CGRect(x: 0, y: 0, width: lado, height: lado)
            vista.centerOffset = .zero
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            /* TU POSICIÓN ES EL COCHE (o la PERSONA si vas a pie): las imágenes de
               navegación, sin fondo ni círculo, en lugar del punto azul del sistema. Se
               dibujan siempre con la misma orientación en la pantalla y el mapa es el que
               gira, así que el coche apunta hacia donde vas. */
            if annotation is MKUserLocation {
                let vista = (mapView.dequeueReusableAnnotationView(withIdentifier: "mi-posicion")
                    as? MKAnnotationView) ?? MKAnnotationView(annotation: annotation, reuseIdentifier: "mi-posicion")
                vista.annotation = annotation
                ponerImagenDeMiPosicion(en: vista)
                vista.canShowCallout = false
                vista.displayPriority = .required
                vista.zPriority = .max // siempre por encima de las chinchetas
                vistaDeMiPosicion = vista
                return vista
            }

            let identificador = annotation.subtitle == "ubicacion" ? "ubicacion" : "pin"
            // El FINAL DE LA RUTA va con SU PROPIA vista (la gota roja punteaguda dibujada
            // a mano), no con la chincheta de MapKit
            if annotation.subtitle == nil, let destino = pinDestino, annotation === destino {
                let vistaDestino = (mapView.dequeueReusableAnnotationView(withIdentifier: "destino")
                    as? MKAnnotationView) ?? MKAnnotationView(annotation: annotation, reuseIdentifier: "destino")
                vistaDestino.annotation = annotation
                vistaDestino.image = ControladorMapa.imagenDestino
                vistaDestino.canShowCallout = true
                vistaDestino.displayPriority = .required
                vistaDestino.zPriority = .max
                // La punta de la gota queda EN EL PUNTO exacto (no el centro de la imagen)
                vistaDestino.centerOffset = CGPoint(x: 0, y: -ControladorMapa.imagenDestino.size.height / 2)
                return vistaDestino
            }

            var vista = mapView.dequeueReusableAnnotationView(withIdentifier: identificador) as? MKMarkerAnnotationView
            if vista == nil {
                vista = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identificador)
                vista?.canShowCallout = true
            } else {
                vista?.annotation = annotation
            }
            guard let marcador = vista else { return nil }

            // Tus ubicaciones: la chincheta con el color de su categoría
            if annotation.subtitle == "ubicacion" {
                marcador.markerTintColor = colorPorPin[ObjectIdentifier(annotation)] ?? .systemTeal
                marcador.glyphImage = UIImage(systemName: "mappin")
                marcador.displayPriority = .defaultLow
                return marcador
            }

            let avisando = annotation.subtitle == "avisando"
            if avisando {
                marcador.markerTintColor = .systemYellow
                marcador.glyphImage = UIImage(systemName: "exclamationmark.triangle.fill")
                marcador.displayPriority = .required
            } else {
                marcador.markerTintColor = .systemRed
                marcador.glyphImage = UIImage(systemName: "camera.fill")
                marcador.displayPriority = .defaultHigh
            }
            return marcador
        }

        /// Tocar una chincheta de tus ubicaciones abre su ficha
        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let id = idPorPin[ObjectIdentifier(annotation)] {
                controlador.ubicacionTocada = id
                mapView.deselectAnnotation(annotation, animated: false)
            }
        }
    }
}
