/* OPTIMIZAR LA RUTA: el mismo algoritmo que usa la web.

   Es un problema del viajante (TSP) sobre las paradas de una ruta:
     · Con 8 paradas o menos se busca la mejor combinación posible (búsqueda exacta).
     · Con más, se prueban varios arranques con «vecino más cercano» y luego se
       descruzan los tramos (2-Opt) hasta que ya no se puede mejorar.
   Se respetan:
     · Las paradas ya hechas al principio (las que van en orden desde el principio).
     · La ruta circular (si empieza y acaba en el mismo sitio, se queda igual).
     · Las paradas sin coordenadas se quedan al final, sin tocar.
   El coste de cada tramo es km por carretera + 0,4 minutos, igual que la web: así no
   sólo se acorta la distancia, también el tiempo.
*/
import Foundation
import CoreLocation

enum OptimizarRuta {

    /// Distancia en línea recta (Haversine), en km — la misma fórmula que la web
    static func distanciaKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let r = 6371.0
        let rad = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * rad
        let dLng = (b.longitude - a.longitude) * rad
        let h = pow(sin(dLat / 2), 2)
            + cos(a.latitude * rad) * cos(b.latitude * rad) * pow(sin(dLng / 2), 2)
        return r * 2 * atan2(sqrt(h), sqrt(1 - h))
    }

    /// Los km de carretera: la línea recta es ~28 % más corta (igual que la web)
    static func kmCarretera(_ rectaKm: Double) -> Double { rectaKm * 1.28 }

    /// Los minutos que se tardan, según la misma tabla de velocidades que la web
    static func minutosEstimados(_ rectaKm: Double, perfil: String = "coche") -> Double {
        guard rectaKm > 0 else { return 1 }
        let km = kmCarretera(rectaKm)
        if perfil == "pie" { return max(1, (km / 4.8) * 60) }
        let velocidad: Double
        if rectaKm < 2 { velocidad = 25 }
        else if rectaKm < 10 { velocidad = 38 }
        else if rectaKm < 30 { velocidad = 55 }
        else if rectaKm < 80 { velocidad = 75 }
        else { velocidad = 90 }
        return (km / velocidad) * 60
    }

    /// El coste de un tramo: km por carretera + 0,4 min (el tiempo también cuenta)
    private static func coste(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let recta = distanciaKm(a, b)
        return kmCarretera(recta) + minutosEstimados(recta) * 0.4
    }

    /* El orden optimizado de las paradas.
       · `ids`: el orden actual.
       · `coordenadas`: la lat/lng de cada parada (las que no la tengan se quedan al final).
       · `hechas`: los índices ya completados al principio, que no se mueven.
       · `desde`: tu posición, si estás cerca del arranque (así se sale por donde toca). */
    static func ordenar(
        ids: [String],
        coordenadas: [String: CLLocationCoordinate2D],
        hechas: Set<Int> = [],
        desde: CLLocationCoordinate2D? = nil
    ) -> [String] {
        guard ids.count > 2 else { return ids }

        // 1) Las paradas ya hechas, seguidas desde el principio, no se tocan
        var prefijoFijo = 0
        while prefijoFijo < ids.count && hechas.contains(prefijoFijo) { prefijoFijo += 1 }
        let prefijo = Array(ids.prefix(prefijoFijo))
        var aOptimizar = Array(ids.dropFirst(prefijoFijo))
        if aOptimizar.count <= 1 { return ids }

        // 2) ¿Es una ruta circular? (empieza y acaba en el mismo sitio)
        var sufijo: [String] = []
        var cabeza: [String] = prefijo
        if prefijoFijo == 0, aOptimizar.count >= 4, aOptimizar.first == aOptimizar.last {
            cabeza.append(aOptimizar[0])
            sufijo = [aOptimizar[aOptimizar.count - 1]]
            aOptimizar = Array(aOptimizar.dropFirst().dropLast())
        }

        // 3) Se separan las que tienen coordenadas de las que no
        var validas: [(id: String, c: CLLocationCoordinate2D)] = []
        var sinCoordenadas: [String] = []
        for id in aOptimizar {
            if let c = coordenadas[id] { validas.append((id, c)) } else { sinCoordenadas.append(id) }
        }
        if validas.count <= 1 {
            return cabeza + validas.map(\.id) + sinCoordenadas + sufijo
        }

        let n = validas.count

        // 4) La tabla de costes entre todas las paradas
        var costes = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                let c = coste(validas[i].c, validas[j].c)
                costes[i][j] = c
                costes[j][i] = c
            }
        }

        // 5) Desde dónde se arranca: la última parada hecha, o tu posición si estás cerca
        var referencia: CLLocationCoordinate2D?
        if let ultima = cabeza.last, let c = coordenadas[ultima] {
            referencia = c
        } else if let aqui = desde {
            let minimo = validas.map { distanciaKm(aqui, $0.c) }.min() ?? .greatestFiniteMagnitude
            if minimo < 50 { referencia = aqui }
        }
        var costeArranque = [Double](repeating: 0, count: n)
        if let r = referencia {
            for i in 0..<n { costeArranque[i] = coste(r, validas[i].c) }
        }
        var costeFinal = [Double](repeating: 0, count: n)
        if let ultima = sufijo.first, let c = coordenadas[ultima] {
            for i in 0..<n { costeFinal[i] = coste(validas[i].c, c) }
        }

        var mejorOrden: [Int]?
        var mejorCoste = Double.greatestFiniteMagnitude

        /* BÚSQUEDA EXACTA hasta 10 paradas (antes 8): con la poda de «si ya cuesta más que
           lo mejor, se corta» 10 paradas se resuelven al instante, y así el resultado es EL
           MEJOR POSIBLE sin depender de heurísticas. */
        if n <= 10 {
            // ── Búsqueda exacta: se prueba todo y se queda lo mejor ──────────
            var usado = [Bool](repeating: false, count: n)
            var actual = [Int](repeating: 0, count: n)

            func buscar(_ profundidad: Int, _ acumulado: Double) {
                if acumulado >= mejorCoste { return }
                if profundidad == n {
                    let total = acumulado + (sufijo.isEmpty ? 0 : costeFinal[actual[n - 1]])
                    if total < mejorCoste {
                        mejorCoste = total
                        mejorOrden = actual
                    }
                    return
                }
                for i in 0..<n where !usado[i] {
                    usado[i] = true
                    actual[profundidad] = i
                    let paso = profundidad == 0
                        ? (referencia != nil ? costeArranque[i] : 0)
                        : costes[actual[profundidad - 1]][i]
                    buscar(profundidad + 1, acumulado + paso)
                    usado[i] = false
                }
            }
            buscar(0, 0)
        } else {
            // ── Vecino más cercano desde varios arranques + 2-Opt ────────────
            var arranques: [Int] = []
            if referencia != nil {
                arranques = (0..<n).sorted { costeArranque[$0] < costeArranque[$1] }
                arranques = Array(arranques.prefix(min(4, n)))
            } else {
                arranques = Array(0..<n)
            }
            // Si son pocas, se prueban TODOS los arranques posibles: así hay más
            // posibilidades de dar con el mejor recorrido
            if n <= 16 { arranques = Array(0..<n) }

            for inicio in arranques {
                var recorrido = [inicio]
                var visitado = [Bool](repeating: false, count: n)
                visitado[inicio] = true
                while recorrido.count < n {
                    let actual = recorrido[recorrido.count - 1]
                    var mejor = -1
                    var mejorD = Double.greatestFiniteMagnitude
                    for j in 0..<n where !visitado[j] && costes[actual][j] < mejorD {
                        mejorD = costes[actual][j]
                        mejor = j
                    }
                    if mejor == -1 { break }
                    visitado[mejor] = true
                    recorrido.append(mejor)
                }

                // 2-Opt: se descruzan los tramos hasta que ya no se puede mejorar
                var mejorado = true
                var pasadas = 0
                while mejorado && pasadas < 80 {
                    mejorado = false
                    pasadas += 1
                    for i in 0..<(n - 1) {
                        for j in (i + 1)..<n {
                            let viejo =
                                (i > 0 ? costes[recorrido[i - 1]][recorrido[i]]
                                       : (referencia != nil ? costeArranque[recorrido[i]] : 0))
                                + (j < n - 1 ? costes[recorrido[j]][recorrido[j + 1]]
                                             : (sufijo.isEmpty ? 0 : costeFinal[recorrido[j]]))
                            let nuevo =
                                (i > 0 ? costes[recorrido[i - 1]][recorrido[j]]
                                       : (referencia != nil ? costeArranque[recorrido[j]] : 0))
                                + (j < n - 1 ? costes[recorrido[i]][recorrido[j + 1]]
                                             : (sufijo.isEmpty ? 0 : costeFinal[recorrido[i]]))
                            if nuevo < viejo - 1e-6 {
                                recorrido[i...j].reverse()
                                mejorado = true
                            }
                        }
                    }
                }

                // OR-OPT: se mueven trozos de 1 a 3 paradas a otro sitio si sale mejor
                recorrido = orOpt(recorrido, n: n, costes: costes, arranque: costeArranque,
                                  final: costeFinal, hayReferencia: referencia != nil,
                                  haySufijo: !sufijo.isEmpty)

                var costeTotal = referencia != nil ? costeArranque[recorrido[0]] : 0
                for i in 0..<(n - 1) { costeTotal += costes[recorrido[i]][recorrido[i + 1]] }
                if !sufijo.isEmpty { costeTotal += costeFinal[recorrido[n - 1]] }
                if costeTotal < mejorCoste {
                    mejorCoste = costeTotal
                    mejorOrden = recorrido
                }
            }
        }

        guard let orden = mejorOrden else { return ids }
        let optimizadas = orden.map { validas[$0].id }
        return cabeza + optimizadas + sinCoordenadas + sufijo
    }

    /* OR-OPT: coge un trocito de 1, 2 o 3 paradas seguidas y lo prueba en TODAS las demás
       posiciones; si alguna sale más barata, se queda ahí. Es el refinamiento clásico que
       va con el 2-Opt: con muchas paradas, el 2-Opt solo no llega a todas las mejoras y el
       recorrido queda peor de lo que podría estar. */
    private static func orOpt(
        _ recorrido: [Int],
        n: Int,
        costes: [[Double]],
        arranque: [Double],
        final: [Double],
        hayReferencia: Bool,
        haySufijo: Bool
    ) -> [Int] {
        var mejor = recorrido
        var mejorCoste = costeDe(mejor, costes: costes, arranque: arranque, final: final,
                                 hayReferencia: hayReferencia, haySufijo: haySufijo)
        var mejora = true
        var vueltas = 0
        while mejora && vueltas < 40 {
            mejora = false
            vueltas += 1
            for largo in 1...3 {
                guard largo < n else { continue }
                for inicio in 0...(n - largo) {
                    var sinTrozo = mejor
                    let trozo = Array(sinTrozo[inicio..<(inicio + largo)])
                    sinTrozo.removeSubrange(inicio..<(inicio + largo))
                    for destino in 0...sinTrozo.count {
                        if destino == inicio { continue }
                        var prueba = sinTrozo
                        prueba.insert(contentsOf: trozo, at: destino)
                        let coste = costeDe(prueba, costes: costes, arranque: arranque, final: final,
                                            hayReferencia: hayReferencia, haySufijo: haySufijo)
                        if coste < mejorCoste - 1e-9 {
                            mejorCoste = coste
                            mejor = prueba
                            mejora = true
                        }
                    }
                }
            }
        }
        return mejor
    }

    /// El coste de un recorrido entero (con el arranque y el final, si los hay)
    private static func costeDe(
        _ recorrido: [Int],
        costes: [[Double]],
        arranque: [Double],
        final: [Double],
        hayReferencia: Bool,
        haySufijo: Bool
    ) -> Double {
        guard !recorrido.isEmpty else { return 0 }
        var total = hayReferencia ? arranque[recorrido[0]] : 0
        for i in 0..<(recorrido.count - 1) { total += costes[recorrido[i]][recorrido[i + 1]] }
        if haySufijo { total += final[recorrido[recorrido.count - 1]] }
        return total
    }
}
