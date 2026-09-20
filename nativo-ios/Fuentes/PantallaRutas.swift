/* LAS RUTAS GUARDADAS (las «listas» de la web, con sus paradas).

   · CREAR: la tarjeta «Nueva ruta» de la web, con su nombre y su botón ＋.
   · BUSCAR: un buscador que filtra las rutas por su nombre y por el de sus paradas.
   · FIJAR / COMPARTIR / EDITAR / BORRAR: deslizando la fila salen los mismos botones que
     en la web y, si deslizas de sobra, la acción se ejecuta sola.
   · Al abrir una ruta: sus paradas EN ORDEN, con LOS PANELES DE CADA TRAMO ENTRE PARADA Y
     PARADA (no todos al final): primero el tramo que llega a la parada y debajo la parada,
     con su hilo conector y su nodo, igual que la web.
   · NAVEGAR: mete TODAS las paradas en el navegador (no sólo la primera), salta las ya
     hechas y arranca la conducción.
   El progreso se guarda en el propio móvil (como en la web), así no ensucia el servidor.
*/
import SwiftUI
import CoreLocation
import UIKit

struct PantallaRutas: View {
    @ObservedObject var estado: Estado
    @ObservedObject var almacen: Almacen
    var irAlMapa: () -> Void

    @State private var abierta: RutaGuardada?
    @State private var borrando: RutaGuardada?
    @State private var consulta = ""
    @State private var compartir: Compartir?
    @State private var aviso: String?
    @State private var nombreNueva = ""
    @State private var creando = false
    /// El modo ORDENAR (arrastrar de las rayitas) y el sentido del A-Z
    @State private var ordenando = false
    @State private var ordenAscendente = true

    /// Un botón de la fila de ordenar
    private func botonDeOrden(
        titulo: String,
        icono: String,
        activo: Bool,
        accion: @escaping () -> Void
    ) -> some View {
        Button(action: accion) {
            HStack(spacing: 8) {
                Image(systemName: icono).font(.system(size: 16, weight: .bold))
                Text(titulo).font(.system(size: 16, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundColor(activo ? .black : Diseno.texto)
            .background(activo ? Diseno.acento : Diseno.fondoTarjeta, in: RoundedRectangle(cornerRadius: Diseno.radioSm))
            .overlay(RoundedRectangle(cornerRadius: Diseno.radioSm).stroke(activo ? Diseno.acento : Diseno.lineaFuerte, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    buscador
                    tarjetaNuevaRuta

                    if !almacen.rutas.isEmpty {
                        // Los contadores, como las tarjetas de la web
                        HStack(spacing: 10) {
                            tarjetaRuta(valor: "\(almacen.rutas.count)", titulo: "Rutas", icono: "arrow.triangle.turn.up.right.diamond.fill", color: Diseno.acento)
                            tarjetaRuta(valor: "\(almacen.rutas.reduce(0) { $0 + $1.locationIds.count })", titulo: "Paradas", icono: "mappin.and.ellipse", color: Diseno.verde)
                            tarjetaRuta(valor: "\(hechasTotales)", titulo: "Hechas", icono: "checkmark.circle.fill", color: Diseno.azul)
                        }
                        .padding(.bottom, 2)

                        // ── Los botones de ordenar, debajo de los paneles ─────
                        HStack(spacing: 10) {
                            botonDeOrden(
                                titulo: ordenando ? "Listo" : "Ordenar",
                                icono: ordenando ? "checkmark" : "line.3.horizontal",
                                activo: ordenando
                            ) {
                                withAnimation(.easeOut(duration: 0.2)) { ordenando.toggle() }
                            }
                            botonDeOrden(
                                titulo: ordenAscendente ? "A-Z" : "Z-A",
                                icono: "arrow.up.arrow.down",
                                activo: false
                            ) {
                                Task { await almacen.ordenarRutas(ascendente: ordenAscendente) }
                                ordenAscendente.toggle()
                            }
                        }

                        if ordenando {
                            Text("Arrastra de las rayitas de la derecha para subir o bajar una ruta. Al soltar, se queda en su sitio y se guarda.")
                                .font(.disEtiqueta)
                                .foregroundColor(Diseno.acento)
                                .padding(.vertical, 2)
                        }

                        if !consulta.isEmpty {
                            Text("\(filtradas.count) de \(almacen.rutas.count) ruta(s)")
                                .font(.disEtiqueta)
                                .foregroundColor(Diseno.apagado)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if filtradas.isEmpty {
                            Text("Ninguna ruta coincide con «\(consulta)»")
                                .font(.disSecundario)
                                .foregroundColor(Diseno.apagado)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 30)
                        } else if ordenando {
                            /* MODO ORDENAR: se cambia a una `List` con `onMove`, que es el
                               arrastre NATIVO de iOS: el tirador de la derecha (las rayitas),
                               la fila sigue al dedo y las demás se acoplan solas con la
                               animación del sistema. Es lo mismo que hace la web pero con el
                               motor de Apple. */
                            List {
                                ForEach(filtradas) { ruta in
                                    FilaOrdenableDeRuta(ruta: ruta, almacen: almacen)
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                }
                                .onMove { origen, destino in
                                    Task { await almacen.moverRutas(de: origen, a: destino, visibles: filtradas) }
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .environment(\.editMode, .constant(.active))
                            .frame(height: CGFloat(filtradas.count) * 96 + 20)
                        } else {
                            // Las fijadas van arriba, como en la web
                            ForEach(filtradas) { ruta in
                                filaRuta(ruta)
                            }
                        }
                    } else {
                        Text("Todavía no hay rutas. Escribe un nombre arriba y toca ＋ para crear la primera, o ármala desde el mapa.")
                            .font(.disSecundario)
                            .foregroundColor(Diseno.apagado)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 28)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
            }
            .simultaneousGesture(TapGesture().onEnded { FilasAbiertas.compartida.cerrarTodas() })
            .cerrarFilasAlDesplazar()
            .bloqueaScrollAlDeslizarFila()
            .navigationTitle("Rutas")
            .background(FondoMidnight())
            .toolbarBackground(Diseno.fondo, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(Diseno.acento)
            .refreshable { await almacen.cargar() }
            .sheet(item: $abierta) { ruta in
                DetalleRuta(estado: estado, almacen: almacen, ruta: ruta, irAlMapa: irAlMapa)
            }
            .hojaCompartir($compartir)
            .overlay(alignment: .bottom) {
                if let aviso = aviso {
                    Text(aviso)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Diseno.acento, in: Capsule())
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .alert("¿Borrar «\(borrando?.name ?? "")»?", isPresented: Binding(
                get: { borrando != nil },
                set: { if !$0 { borrando = nil } }
            )) {
                Button("Cancelar", role: .cancel) { borrando = nil }
                Button("Borrar", role: .destructive) {
                    if let ruta = borrando {
                        Task { await almacen.borrarRuta(ruta) }
                    }
                    borrando = nil
                }
            }
        }
    }

    // ── La tarjeta «Nueva ruta» (igual que la de la web) ─────────────────────
    private var tarjetaNuevaRuta: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Diseno.acento)
                Text("Nueva ruta")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundColor(Diseno.texto)
            }
            HStack(spacing: 8) {
                TextField("Ej. Ruta Girona, Ruta Costa Brava…", text: $nombreNueva)
                    .textInputAutocapitalization(.sentences)
                    .foregroundColor(Diseno.texto)
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(Diseno.fondoTarjetaAlta, in: RoundedRectangle(cornerRadius: Diseno.radioSm))
                    .overlay(RoundedRectangle(cornerRadius: Diseno.radioSm).stroke(Diseno.lineaFuerte, lineWidth: 1))
                    .onSubmit { crear() }
                Button {
                    crear()
                } label: {
                    Image(systemName: creando ? "ellipsis" : "plus")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundColor(.black)
                        .frame(width: 46, height: 46)
                        .background(Diseno.acento, in: RoundedRectangle(cornerRadius: Diseno.radioSm))
                }
                .buttonStyle(.plain)
                .disabled(creando)
            }
        }
        .padding(14)
        .background(Diseno.fondoTarjeta, in: RoundedRectangle(cornerRadius: Diseno.radio))
        .overlay(RoundedRectangle(cornerRadius: Diseno.radio).stroke(Diseno.linea, lineWidth: 0.5))
    }

    /// Crear una ruta nueva y abrirla para meterle paradas
    private func crear() {
        let nombre = nombreNueva.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nombre.isEmpty else {
            mostrar("Ponle un nombre a la ruta")
            return
        }
        creando = true
        Task {
            let nueva = await almacen.guardarRuta(nombre: nombre, locationIds: [])
            nombreNueva = ""
            creando = false
            abierta = nueva
        }
    }

    // ── Las rutas filtradas: las fijadas arriba y, dentro, por nombre ─────────
    private var filtradas: [RutaGuardada] {
        let q = consulta.trimmingCharacters(in: .whitespaces).lowercased()
        let lista = q.isEmpty ? almacen.rutas : almacen.rutas.filter { ruta in
            if ruta.name.lowercased().contains(q) { return true }
            return ruta.locationIds.contains { id in
                guard let u = almacen.ubicacion(id) else { return false }
                return u.name.lowercased().contains(q)
                    || u.address.lowercased().contains(q)
                    || u.code.lowercased().contains(q)
            }
        }
        /* EL ORDEN ES EL DEL DOCUMENTO, con las fijadas delante. ¡Ojo!: antes se ordenaba
           SIEMPRE por nombre aquí, así que daba igual el orden que guardaras (a mano o con
           A-Z): la lista se volvía a ordenar alfabéticamente y por eso «no ordenaba». */
        return lista.filter { $0.pinned } + lista.filter { !$0.pinned }
    }

    // ── Una fila de ruta, con los deslizamientos de la web ────────────────────
    /* DESLIZANDO HACIA LA IZQUIERDA: NAVEGAR y COMPARTIR (que es lo que más se usa al ir a
       navegar). Al OTRO lado: FIJAR, con el de BORRAR pegado al borde. */
    private func filaRuta(_ ruta: RutaGuardada) -> some View {
        FilaDeslizable(
            izquierda: [
                AccionFila(titulo: "Navegar", icono: "location.north.line.fill", color: Diseno.verde) {
                    navegarRuta(ruta)
                },
                AccionFila(titulo: "Compartir", icono: "square.and.arrow.up.fill", color: Diseno.azul) {
                    compartirRuta(ruta)
                },
            ],
            derecha: [
                AccionFila(titulo: "Fijar", icono: ruta.pinned ? "pin.slash.fill" : "pin.fill", color: Diseno.naranjaPin) {
                    Task { await almacen.fijarRuta(ruta) }
                    mostrar(ruta.pinned ? "«\(ruta.name)» desfijada" : "«\(ruta.name)» fijada arriba 📌")
                },
                AccionFila(titulo: "Borrar", icono: "trash.fill", color: Diseno.peligro) {
                    borrando = ruta
                },
            ],
            alTocar: { abierta = ruta }
        ) {
            ContenidoFilaRuta(ruta: ruta, almacen: almacen, mostrarPin: true)
        }
    }

    /// Arrancar una ruta guardada en el navegador, con todas sus paradas
    private func navegarRuta(_ ruta: RutaGuardada) {
        let paradas = ruta.locationIds.compactMap { almacen.ubicacion($0) }
        guard !paradas.isEmpty else {
            mostrar("Esta ruta no tiene paradas")
            return
        }
        let guardadas = UserDefaults.standard.array(forKey: "ubixavi_nativo_hechas_\(ruta.id)") as? [Int] ?? []
        estado.cargarRutaEnElNavegador(paradas: paradas, hechas: Set(guardadas))
        irAlMapa()
    }

    private func mostrar(_ texto: String) {
        withAnimation { aviso = texto }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation { aviso = nil }
        }
    }

    /// Comparte la ruta como la web: el nombre, las paradas numeradas y el enlace de
    /// Google Maps con todas ellas.
    private func compartirRuta(_ ruta: RutaGuardada) {
        let paradas = ruta.locationIds.compactMap { almacen.ubicacion($0) }
        guard !paradas.isEmpty else {
            mostrar("Esta ruta no tiene ubicaciones")
            return
        }
        let conCoordenadas = paradas.filter { $0.tieneCoordenadas }
        guard !conCoordenadas.isEmpty else {
            mostrar("Esta ruta no tiene ubicaciones con coordenadas")
            return
        }
        let nombres = conCoordenadas.enumerated().map { "\($0.offset + 1). \($0.element.name)" }.joined(separator: "\n")
        let texto = "Ruta: \(ruta.name) (\(conCoordenadas.count) paradas)\n\(nombres)"
        compartir = Compartir(texto: texto, url: enlaceRutaGoogleMaps(conCoordenadas))
    }

    // ── El buscador (el «Buscar ruta o ubicación…» de la web) ─────────────────
    private var buscador: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(Diseno.apagado)
            TextField("Buscar ruta o parada…", text: $consulta)
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

    // ── Los contadores de arriba (como las tarjetas de la web) ───────────────
    private var hechasTotales: Int {
        almacen.rutas.reduce(0) { total, ruta in
            total + (UserDefaults.standard.array(forKey: "ubixavi_nativo_hechas_\(ruta.id)") as? [Int] ?? []).count
        }
    }

    private func tarjetaRuta(valor: String, titulo: String, icono: String, color: Color) -> some View {
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
}

/// LA FILA DE UNA RUTA EN EL MODO ORDENAR (la usa la lista que se arrastra)
struct FilaOrdenableDeRuta: View {
    let ruta: RutaGuardada
    @ObservedObject var almacen: Almacen

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Diseno.acento)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(ruta.name)
                        .font(.disFila)
                        .foregroundColor(Diseno.texto)
                        .lineLimit(1)
                    if ruta.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Diseno.naranjaPin)
                    }
                }
                Text("\(ruta.locationIds.count) parada\(ruta.locationIds.count == 1 ? "" : "s")\(ruta.pinned ? " · fijada" : "")")
                    .font(.disEtiqueta)
                    .foregroundColor(Diseno.apagado)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(Diseno.fondoFila, in: RoundedRectangle(cornerRadius: Diseno.radio))
        .overlay(RoundedRectangle(cornerRadius: Diseno.radio).stroke(Diseno.linea, lineWidth: 0.5))
    }
}

// ── La fila de una ruta guardada (con su barra de progreso) ───────────────────
struct ContenidoFilaRuta: View {
    let ruta: RutaGuardada
    @ObservedObject var almacen: Almacen
    /// La chincheta grande de las rutas fijadas (sólo en la lista)
    var mostrarPin = false

    /// Las paradas ya hechas se guardan en el móvil, con la misma clave que la web
    private var clave: String { "ubixavi_nativo_hechas_\(ruta.id)" }

    private var hechas: Int {
        (UserDefaults.standard.array(forKey: clave) as? [Int] ?? []).count
    }

    private var total: Int { ruta.locationIds.count }

    private var progreso: Double {
        guard total > 0 else { return 0 }
        return min(Double(hechas) / Double(total), 1)
    }

    private var distanciaTotalKm: Double {
        let paradas = ruta.locationIds.compactMap { almacen.ubicacion($0) }
        guard paradas.count > 1 else { return 0 }
        var metros: Double = 0
        for indice in 0..<(paradas.count - 1) {
            let a = CLLocation(latitude: paradas[indice].lat, longitude: paradas[indice].lng)
            let b = CLLocation(latitude: paradas[indice + 1].lat, longitude: paradas[indice + 1].lng)
            metros += a.distance(from: b)
        }
        return (metros / 1000) * 1.3 // la carretera es ~30 % más larga que la línea recta
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Diseno.acento)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(ruta.name)
                            .font(.disFila)
                            .foregroundColor(Diseno.texto)
                            .lineLimit(2)
                        if mostrarPin && ruta.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Diseno.naranjaPin)
                        }
                    }
                    HStack(spacing: 6) {
                        Pastilla(texto: "\(total) parada\(total == 1 ? "" : "s")", color: Diseno.apagado)
                        if distanciaTotalKm > 0.3 {
                            Pastilla(texto: String(format: "%.0f km", distanciaTotalKm), color: Diseno.acento)
                            if let minutos = minutosEstimados(distanciaTotalKm * 1000) {
                                Pastilla(texto: "\(minutos) min", color: Diseno.verde)
                            }
                        }
                        if hechas > 0 {
                            Pastilla(texto: "\(hechas) hecha\(hechas == 1 ? "" : "s")", color: Diseno.verde)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Diseno.apagado)
            }

            // La barra de progreso de la ruta, como en la web
            HStack(spacing: 8) {
                BarraProgresoRuta(valor: progreso)
                Text("\(Int(progreso * 100))%")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(Diseno.texto)
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        .background(Diseno.fondoFila)
    }
}

// ── Una ruta abierta: sus paradas, los tramos y las acciones ─────────────────
struct DetalleRuta: View {
    @ObservedObject var estado: Estado
    @ObservedObject var almacen: Almacen
    let ruta: RutaGuardada
    var irAlMapa: () -> Void

    @Environment(\.dismiss) private var cerrar
    /// Paradas ya hechas: se guardan en el móvil, con la misma clave que usa la web
    @State private var hechas: Set<Int> = []
    /// El orden de las paradas (se puede cambiar y se guarda)
    @State private var ids: [String] = []
    /// Los tramos del recorrido (tiempo, km y tráfico de cada uno)
    @State private var tramos: [Estado.Tramo] = []
    @State private var cargandoTramos = false
    @State private var compartir: Compartir?
    @State private var aviso: String?
    @State private var renombrando = false
    @State private var nombreNuevo = ""
    /// El buscador para añadir paradas a la ruta (el «＋ Añadir ubicaciones» de la web)
    @State private var anadiendo = false
    @State private var consultaAnadir = ""
    /// El modo «Ordenar»: cada parada enseña sus flechas de subir y bajar
    @State private var ordenando = false

    private var clave: String { "ubixavi_nativo_hechas_\(ruta.id)" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    resumen
                    acciones
                    bloqueParadas
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .background(FondoMidnight())
            .simultaneousGesture(TapGesture().onEnded { FilasAbiertas.compartida.cerrarTodas() })
            .cerrarFilasAlDesplazar()
            .bloqueaScrollAlDeslizarFila()
            .navigationTitle(ruta.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Diseno.fondo, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(Diseno.acento)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { cerrar() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            nombreNuevo = ruta.name
                            renombrando = true
                        } label: {
                            Label("Cambiar el nombre", systemImage: "pencil")
                        }
                        Button {
                            compartirRuta()
                        } label: {
                            Label("Compartir la ruta", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            abrirEnGoogleMaps()
                        } label: {
                            Label("Abrir en Google Maps", systemImage: "map")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .hojaCompartir($compartir)
            .sheet(isPresented: $anadiendo) {
                ElegirParadasRuta(
                    almacen: almacen,
                    yaEnLaRuta: Set(ids),
                    alElegir: { ubicacion in anadir(ubicacion) }
                )
            }
            .alert("Nombre de la ruta", isPresented: $renombrando) {
                TextField("Nombre", text: $nombreNuevo)
                Button("Cancelar", role: .cancel) {}
                Button("Guardar") { renombrar() }
            }
            .overlay(alignment: .bottom) {
                if let aviso = aviso {
                    Text(aviso)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Diseno.acento, in: Capsule())
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear {
                if ids.isEmpty { ids = ruta.locationIds }
                let guardadas = UserDefaults.standard.array(forKey: clave) as? [Int] ?? []
                hechas = Set(guardadas)
            }
            .task { await cargarTramos() }
        }
    }

    // ── Cabecera: totales y progreso ─────────────────────────────────────────
    private var resumen: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Pastilla(texto: "\(paradas.count) parada\(paradas.count == 1 ? "" : "s")", color: Diseno.acento)
                Pastilla(texto: "\(hechas.count) hechas", color: Diseno.verde)
                if ruta.pinned { Pastilla(texto: "fijada", color: Diseno.naranjaPin) }
            }
            PanelTotalesRuta(
                kmRestantes: kmRestantes,
                kmTotales: kmTotales,
                minutosRestantes: minutosRestantes,
                minutosTotales: minutosTotales
            )
            CabeceraProgresoRuta(valor: progreso)
        }
        .padding(.vertical, 4)
    }

    // ── Las acciones de la ruta (como las filas de la web) ───────────────────
    private var acciones: some View {
        VStack(spacing: 0) {
            botonAccion("Añadir ubicaciones a la ruta", icono: "plus.circle.fill", color: Diseno.acento) {
                consultaAnadir = ""
                anadiendo = true
            }
            Divider().overlay(Diseno.linea)
            botonAccion("Optimizar la ruta", icono: "wand.and.stars", color: Diseno.verde) {
                optimizar()
            }
            Divider().overlay(Diseno.linea)
            botonAccion("Invertir el sentido", icono: "arrow.left.arrow.right", color: Diseno.azul) {
                invertir()
            }
            Divider().overlay(Diseno.linea)
            botonAccion(
                ordenando ? "Listo (dejar de ordenar)" : "Ordenar las paradas a mano",
                icono: "arrow.up.arrow.down",
                color: Diseno.azul
            ) {
                ordenando.toggle()
            }
            Divider().overlay(Diseno.linea)
            botonAccion("Reiniciar las paradas hechas", icono: "arrow.counterclockwise", color: Diseno.naranja) {
                reiniciar()
            }
            Divider().overlay(Diseno.linea)
            botonAccion("Compartir la ruta", icono: "square.and.arrow.up.fill", color: Diseno.verde) {
                compartirRuta()
            }
            Divider().overlay(Diseno.linea)
            botonAccion("Abrir en Google Maps", icono: "map.fill", color: Diseno.morado) {
                abrirEnGoogleMaps()
            }
        }
        .background(Diseno.fondoTarjeta, in: RoundedRectangle(cornerRadius: Diseno.radio))
        .overlay(RoundedRectangle(cornerRadius: Diseno.radio).stroke(Diseno.linea, lineWidth: 0.5))
    }

    private func botonAccion(_ titulo: String, icono: String, color: Color, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            HStack(spacing: 12) {
                Image(systemName: icono)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 26)
                Text(titulo)
                    .font(.disCuerpo.weight(.semibold))
                    .foregroundColor(Diseno.texto)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Las flechitas de subir y bajar de una parada (el modo «Ordenar»)
    private func botonFlecha(_ icono: String, activo: Bool, accion: @escaping () -> Void) -> some View {
        Button {
            accion()
            Tacto.seleccion()
        } label: {
            Image(systemName: icono)
                .font(.system(size: 13, weight: .heavy))
                .foregroundColor(activo ? Diseno.acento : Diseno.apagado.opacity(0.4))
                .frame(width: 30, height: 24)
                .background(Diseno.fondoTarjetaAlta, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!activo)
    }

    // ══════════════════════════════════════════════════════════════════════════
    // LAS PARADAS Y SUS TRAMOS, INTERCALADOS (como la web)
    // ══════════════════════════════════════════════════════════════════════════
    /* El orden es el de la web: primero el tramo que LLEGA a la parada (con sus dos
       paneles) y debajo la parada. Así los paneles quedan ENTRE parada y parada, no
       todos juntos al final. */
    private var bloqueParadas: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ubicaciones en la ruta (\(paradas.count))")
                .font(.disEtiqueta)
                .foregroundColor(Diseno.apagado)

            if paradas.isEmpty {
                Text("Esta ruta no tiene paradas todavía. Usa «Añadir ubicaciones a la ruta».")
                    .font(.disSecundario)
                    .foregroundColor(Diseno.apagado)
            }

            if cargandoTramos && tramos.isEmpty && paradas.count > 1 {
                HStack(spacing: 10) {
                    ProgressView().tint(Diseno.acento)
                    Text("Calculando los tramos…").foregroundColor(Diseno.apagado)
                }
                .padding(.vertical, 8)
            }

            ForEach(Array(paradas.enumerated()), id: \.offset) { indice, parada in
                VStack(alignment: .leading, spacing: 10) {
                    // 1) El tramo que llega a esta parada, con sus paneles
                    if let tramo = tramos.indices.contains(indice) ? tramos[indice] : nil {
                        conectorTramo(tramo: tramo, indice: indice)
                    }

                    // 2) La parada
                    if ordenando {
                        tarjetaParada(indice: indice, parada: parada, conFlechas: true)
                    } else {
                        FilaDeslizable(
                            izquierda: [
                                AccionFila(titulo: "Compartir", icono: "square.and.arrow.up.fill", color: Diseno.verde) {
                                    compartirParada(parada)
                                },
                                AccionFila(titulo: "Abrir", icono: "map.fill", color: Diseno.acento) {
                                    abrirParada(parada)
                                },
                            ],
                            derecha: [
                                AccionFila(titulo: "Quitar", icono: "trash.fill", color: Diseno.peligro) {
                                    quitar(indice)
                                },
                            ],
                            alTocar: { alternar(indice) }
                        ) {
                            tarjetaParada(indice: indice, parada: parada, conFlechas: false)
                        }
                    }
                }
            }

            // El botón de arrancar la navegación con la ruta entera
            BotonApp(
                titulo: "Iniciar la ruta (todas las paradas)",
                icono: "location.north.line.fill",
                tipo: .verde,
                compacto: true
            ) {
                navegar()
            }
            .disabled(paradas.isEmpty)
            .padding(.top, 4)
        }
    }

    /// El hilo conector de un tramo, con su nodo y los dos paneles (como la web)
    /* EL HILO VERTICAL, CON SU PROGRESO: la pista gris, el RELLENO CON DEGRADADO (los mismos
       colores que la barra de la parada, pero en vertical) y EL PUNTO QUE VIAJA por la línea
       según lo que llevas hecho: al empezar está arriba (pegado a la parada anterior) y al
       terminar llega abajo del todo (pegado a la siguiente). */
    private func conectorTramo(tramo: Estado.Tramo, indice: Int) -> some View {
        let completado = hechas.contains(indice)
        let activo = !completado && indice == (indiceObjetivo ?? -1)
        let progreso = completado ? 1.0 : (activo ? avanceDelTramo(indice) : 0.0)
        return HStack(alignment: .center, spacing: 14) {
            Color.clear.frame(width: 28)
            PanelesTramo(
                minutos: tramo.durationMins,
                km: tramo.distKm,
                trafico: tramo.trafico,
                retrasoMin: tramo.retrasoMin,
                hecho: completado,
                sinTrafico: estado.perfil == "pie",
                llegada: tramo.llegada
            )
        }
        .background(alignment: .topLeading) {
            GeometryReader { geo in
                HiloVertical(progreso: progreso, activo: activo, completado: completado, alto: geo.size.height)
            }
        }
        .padding(.leading, 4)
    }

    /// La tarjeta de una parada, con lo mismo que la web: su barra de progreso de fondo,
    /// el borde de la categoría, el código, las notas, el % y el botón de hecha.
    private func tarjetaParada(indice: Int, parada: Ubicacion, conFlechas: Bool) -> some View {
        let completada = hechas.contains(indice)
        let categoria = almacen.categoria(parada.categoryId)
        let colorFranja: Color = completada
            ? Color(hex: "#8a272e")
            : (categoria.map { Color(hex: $0.color) } ?? Diseno.acento)
        let avance = avanceParada(indice)

        return ZStack(alignment: .leading) {
            // La barra de progreso de fondo del item (como la web)
            GeometryReader { geo in
                Rectangle()
                    .fill(
                        completada
                            ? LinearGradient(colors: [Color(hex: "#6e2429"), Color(hex: "#6e2429")], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(
                                colors: [colorFranja, Color(hex: "#5c1e22")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                    )
                    .frame(width: geo.size.width * avance)
            }

            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(colorFranja)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(parada.name)
                                    .font(.system(size: 22, weight: .regular))
                                    .foregroundColor(completada ? Color.white.opacity(0.65) : Diseno.texto)
                                    .strikethrough(completada)
                                    .lineLimit(2)
                                if !completada && avance > 0.01 {
                                    Text("\(Int((avance * 100).rounded()))%")
                                        .font(.system(size: 13, weight: .heavy))
                                        .foregroundColor(Color(hex: "#ffe2a1"))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .overlay(
                                            Capsule().stroke(Color(hex: "#ffe0a0").opacity(0.45), lineWidth: 1)
                                        )
                                }
                            }
                            if !parada.address.isEmpty {
                                Text(parada.address)
                                    .font(.system(size: 15))
                                    .foregroundColor(Diseno.apagado)
                                    .strikethrough(completada)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)

                        if conFlechas {
                            VStack(spacing: 3) {
                                botonFlecha("chevron.up", activo: indice > 0) { mover(indice, a: indice - 1) }
                                botonFlecha("chevron.down", activo: indice < paradas.count - 1) { mover(indice, a: indice + 1) }
                            }
                        } else {
                            // El botón redondo de «hecha» (como la web)
                            Button {
                                alternar(indice)
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(completada ? Color(hex: "#7a2228") : Color.clear)
                                        .frame(width: 30, height: 30)
                                        .overlay(
                                            Circle().stroke(
                                                completada ? Color(hex: "#aa3840") : Color.white.opacity(0.25),
                                                lineWidth: 2
                                            )
                                        )
                                    if completada {
                                        Text("✓")
                                            .font(.system(size: 14, weight: .heavy))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !parada.code.isEmpty {
                        Text("🔑 \(parada.code)")
                            .font(.system(size: 17))
                            .foregroundColor(Diseno.apagado)
                            .strikethrough(completada)
                    }
                    if !parada.notes.isEmpty {
                        Text(parada.notes)
                            .font(.system(size: 17))
                            .foregroundColor(Diseno.apagado)
                            .lineLimit(1)
                            .strikethrough(completada)
                    }
                }
                .padding(.vertical, 14)
                .padding(.trailing, 14)
            }
        }
        .background(
            completada ? Color(hex: "#4e1a1d").opacity(0.45) : Diseno.fondoFila
        )
        .clipShape(RoundedRectangle(cornerRadius: Diseno.radio))
        .overlay(
            RoundedRectangle(cornerRadius: Diseno.radio)
                .stroke(completada ? Color(hex: "#a03237").opacity(0.35) : Diseno.linea, lineWidth: 0.5)
        )
    }

    // ── Los números de la ruta ───────────────────────────────────────────────
    private var paradas: [Ubicacion] { ids.compactMap { almacen.ubicacion($0) } }

    /// La primera parada que queda pendiente (la que estás yendo a hacer)
    private var indiceObjetivo: Int? {
        for (indice, _) in paradas.enumerated() where !hechas.contains(indice) { return indice }
        return nil
    }

    private var progreso: Double {
        guard !paradas.isEmpty else { return 0 }
        return min(Double(hechas.count) / Double(paradas.count), 1)
    }

    /// El avance HACIA esa parada, como la web: 100 % si ya está hecha o si estás dentro
    /// del radio de llegada; si no, la parte del tramo que llevas hecha.
    private func avanceDelTramo(_ indice: Int) -> Double { avanceParada(indice) }

    /// El avance HACIA esa parada, como la web: 100 % si ya está hecha o si estás dentro
    /// del radio de llegada; si no, la parte del tramo que llevas hecha.
    private func avanceParada(_ indice: Int) -> Double {
        if hechas.contains(indice) { return 1 }
        guard indice == indiceObjetivo, let pos = estado.posicion else { return 0 }
        guard paradas.indices.contains(indice) else { return 0 }
        let destino = paradas[indice]
        guard destino.tieneCoordenadas else { return 0 }
        let origen: CLLocationCoordinate2D = indice == 0
            ? pos.coordinate
            : (paradas[indice - 1].tieneCoordenadas ? paradas[indice - 1].coordinate : pos.coordinate)
        let hasta = CLLocation(latitude: destino.lat, longitude: destino.lng)
        let desde = CLLocation(latitude: origen.latitude, longitude: origen.longitude)
        let distToB = desde.distance(from: hasta)
        let distToA = CLLocation(latitude: origen.latitude, longitude: origen.longitude)
            .distance(from: CLLocation(latitude: pos.coordinate.latitude, longitude: pos.coordinate.longitude))
        let radio: Double = estado.perfil == "pie" ? max(6, min(20, pos.horizontalAccuracy)) : 25
        let meQueda = CLLocation(latitude: pos.coordinate.latitude, longitude: pos.coordinate.longitude)
            .distance(from: hasta)
        if meQueda <= radio { return 1 }
        /* SÓLO hay avance si estás EN EL CAMINO entre las dos paradas: si no, 0 (antes salía
           un porcentaje sin sentido, como «73%» estando a 100 km de distancia). */
        let caminoRecto = distToA + meQueda
        guard distToB > 20, caminoRecto <= distToB * 1.25 + 50 else { return 0 }
        return min(max(distToA / distToB, 0), 0.99)
    }

    private var kmTotales: Double {
        if !tramos.isEmpty { return tramos.reduce(0.0) { $0 + $1.distKm } }
        guard paradas.count > 1 else { return 0 }
        var metros: Double = 0
        for indice in 0..<(paradas.count - 1) {
            metros += CLLocation(latitude: paradas[indice].lat, longitude: paradas[indice].lng)
                .distance(from: CLLocation(latitude: paradas[indice + 1].lat, longitude: paradas[indice + 1].lng))
        }
        return (metros / 1000) * 1.3
    }

    /// Lo que queda: los tramos que llegan a una parada que aún NO está hecha
    private var kmRestantes: Double {
        if tramos.isEmpty { return kmTotales }
        return tramos.enumerated().reduce(0.0) { total, par in
            hechas.contains(par.offset) ? total : total + par.element.distKm
        }
    }

    private var minutosTotales: Int {
        if !tramos.isEmpty { return Int(tramos.reduce(0.0) { $0 + $1.durationMins }.rounded()) }
        return minutosEstimados(kmTotales * 1000) ?? 0
    }

    private var minutosRestantes: Int {
        if tramos.isEmpty { return minutosTotales }
        let suma = tramos.enumerated().reduce(0.0) { total, par in
            hechas.contains(par.offset) ? total : total + par.element.durationMins
        }
        return Int(suma.rounded())
    }

    // ── Los tramos del recorrido (de tu posición a la primera y entre paradas) ─
    private func cargarTramos() async {
        guard paradas.count > 1, let pos = estado.posicion else { return }
        cargandoTramos = true
        let lista = await Estado.calcularTramos(
            paradas: paradas,
            desde: pos.coordinate,
            perfil: estado.perfil,
            desdeIndice: indiceObjetivo ?? 0,
            origenManual: nil
        ) { parciales in
            tramos = parciales
        }
        tramos = lista
        cargandoTramos = false
    }

    private func alternar(_ indice: Int) {
        if hechas.contains(indice) { hechas.remove(indice) } else { hechas.insert(indice) }
        UserDefaults.standard.set(Array(hechas), forKey: clave)
    }

    private func quitar(_ indice: Int) {
        guard ids.indices.contains(indice) else { return }
        ids.remove(at: indice)
        // Las paradas hechas de después bajan una posición
        hechas = Set(hechas.compactMap { $0 == indice ? nil : ($0 > indice ? $0 - 1 : $0) })
        UserDefaults.standard.set(Array(hechas), forKey: clave)
        guardarOrden()
    }

    /// Subir o bajar una parada (el modo «Ordenar»), arrastrando también su estado
    private func mover(_ desde: Int, a destino: Int) {
        guard ids.indices.contains(desde), ids.indices.contains(destino), desde != destino else { return }
        let movido = ids.remove(at: desde)
        ids.insert(movido, at: destino)
        var nuevas = Set<Int>()
        for indice in hechas where indice != desde {
            if desde < destino, indice > desde, indice <= destino { nuevas.insert(indice - 1) }
            else if desde > destino, indice >= destino, indice < desde { nuevas.insert(indice + 1) }
            else { nuevas.insert(indice) }
        }
        if hechas.contains(desde) { nuevas.insert(destino) }
        hechas = nuevas
        UserDefaults.standard.set(Array(hechas), forKey: clave)
        guardarOrden()
    }

    /// Quitar todas las marcas de «hecha» (el «Reiniciar» de la web)
    private func reiniciar() {
        guard !hechas.isEmpty else {
            mostrar("No hay ninguna parada marcada como hecha")
            return
        }
        hechas = []
        UserDefaults.standard.set([Int](), forKey: clave)
        mostrar("↺ Selección reiniciada")
    }

    /// Añadir una ubicación al final de la ruta (el «＋ Añadir ubicaciones» de la web)
    private func anadir(_ ubicacion: Ubicacion) {
        guard !ids.contains(ubicacion.id) else {
            mostrar("«\(ubicacion.name)» ya está en la ruta")
            return
        }
        ids.append(ubicacion.id)
        guardarOrden()
        mostrar("Añadida: \(ubicacion.name)")
    }

    private func renombrar() {
        let limpio = nombreNuevo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return }
        var copia = ruta
        copia.name = limpio
        copia.locationIds = ids
        Task { await almacen.actualizarRuta(copia) }
    }

    private func guardarOrden() {
        var copia = ruta
        copia.locationIds = ids
        Task {
            await almacen.actualizarRuta(copia)
            await cargarTramos()
        }
    }

    // ── OPTIMIZAR LA RUTA: el mismo algoritmo que la web ─────────────────────
    private func optimizar() {
        guard ids.count >= 2 else {
            mostrar("Añade al menos 2 ubicaciones para optimizar la ruta")
            return
        }
        var coordenadas: [String: CLLocationCoordinate2D] = [:]
        for parada in paradas where parada.tieneCoordenadas {
            coordenadas[parada.id] = parada.coordinate
        }
        if coordenadas.isEmpty {
            mostrar("Se necesitan coordenadas en las ubicaciones para optimizar")
            return
        }

        let kmAntes = kmTotales
        let minAntes = minutosTotales

        let nuevos = OptimizarRuta.ordenar(
            ids: ids,
            coordenadas: coordenadas,
            hechas: hechas,
            desde: estado.posicion?.coordinate
        )

        guard nuevos != ids else {
            mostrar("✨ Esta ruta ya tiene el orden más óptimo")
            return
        }
        ids = nuevos

        var copia = ruta
        copia.locationIds = nuevos
        Task {
            await almacen.actualizarRuta(copia)
            await cargarTramos()
            let kmDespues = kmTotales
            let minDespues = minutosTotales
            let ahorroKm = max(0, kmAntes - kmDespues)
            let ahorroMin = max(0, minAntes - minDespues)
            if ahorroKm >= 0.1 || ahorroMin >= 1 {
                var partes: [String] = []
                if ahorroKm >= 0.1 { partes.append(String(format: "-%.1f km", ahorroKm)) }
                if ahorroMin >= 1 { partes.append("-\(ahorroMin) min") }
                mostrar("✨ Ruta optimizada: ahorras \(partes.joined(separator: " y "))")
            } else {
                mostrar("✨ Ruta optimizada al recorrido más eficiente")
            }
        }
    }

    private func invertir() {
        guard ids.count >= 2 else { return }
        let invertidos = Array(ids.reversed())
        guard invertidos != ids else {
            mostrar("La ruta ya está invertida")
            return
        }
        ids = invertidos
        hechas = Set(hechas.map { ids.count - 1 - $0 })
        UserDefaults.standard.set(Array(hechas), forKey: clave)
        guardarOrden()
        mostrar("↩️ Sentido de la ruta invertido")
    }

    // ── NAVEGAR: TODAS las paradas al navegador, como la web ─────────────────
    /* Antes sólo se metía la primera parada pendiente en el navegador y la ruta entera
       se quedaba fuera: por eso «el botón no hacía nada». Ahora el viaje entero va al
       navegador, con las paradas ya hechas saltadas, y arranca la conducción. */
    private func navegar() {
        guard !paradas.isEmpty else {
            mostrar("Esta ruta no tiene paradas")
            return
        }
        let pendientes = paradas.enumerated().filter { !hechas.contains($0.offset) }.map { $0.element }
        guard !pendientes.isEmpty else {
            mostrar("Ya has hecho todas las paradas de esta ruta")
            return
        }
        estado.cargarRutaEnElNavegador(paradas: paradas, hechas: hechas)
        cerrar()
        irAlMapa()
    }

    // ── Compartir y abrir ────────────────────────────────────────────────────
    private func compartirRuta() {
        let conCoordenadas = paradas.filter { $0.tieneCoordenadas }
        guard !conCoordenadas.isEmpty else {
            mostrar("Esta ruta no tiene ubicaciones con coordenadas")
            return
        }
        let nombres = conCoordenadas.enumerated().map { "\($0.offset + 1). \($0.element.name)" }.joined(separator: "\n")
        compartir = Compartir(
            texto: "Ruta: \(ruta.name) (\(conCoordenadas.count) paradas)\n\(nombres)",
            url: enlaceRutaGoogleMaps(conCoordenadas)
        )
    }

    private func compartirParada(_ parada: Ubicacion) {
        let texto = parada.address.isEmpty ? parada.name : "\(parada.name) — \(parada.address)"
        compartir = Compartir(texto: texto, url: enlaceGoogleMaps(parada))
    }

    private func abrirParada(_ parada: Ubicacion) {
        guard let url = enlaceGoogleMaps(parada) else { return }
        UIApplication.shared.open(url)
    }

    private func abrirEnGoogleMaps() {
        abrirViajeEnGoogleMaps(paradas: paradas, desde: estado.posicion?.coordinate)
    }

    private func mostrar(_ texto: String) {
        withAnimation { aviso = texto }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation { aviso = nil }
        }
    }
}

/// EL HILO VERTICAL DE UN TRAMO, CON SU PROGRESO (lo usan la ruta y el «Cambiar destino»)
/* Es la barra de progreso de la parada, pero EN VERTICAL:
     · la PISTA, una línea gris que se sale 14 px por arriba y por abajo para TOCAR las dos
       paradas (así no queda hueco entre el hilo y las tarjetas);
     · el RELLENO, con el mismo DEGRADADO que la barra de la parada, que baja desde arriba
       hasta donde vas;
     · y el PUNTO, que VIAJA por la línea: arriba del todo al empezar (pegado a la parada
       anterior) y abajo del todo al terminar (pegado a la siguiente). */
struct HiloVertical: View {
    var progreso: Double
    var activo: Bool
    var completado: Bool
    var alto: CGFloat

    private var avance: Double { min(max(progreso, 0), 1) }
    private var colorPunto: Color {
        if completado { return Color(hex: "#f17c82") }
        return activo || avance > 0 ? Diseno.acento : Diseno.apagado
    }
    private var colorRelleno: Color { completado ? Color(hex: "#6e2429") : Diseno.acento }
    private var diametro: CGFloat { activo ? 24 : 19 }

    var body: some View {
        let relleno = max(0, alto * avance)
        ZStack(alignment: .top) {
            // La pista (se sale por arriba y por abajo para tocar las dos paradas)
            Capsule()
                .fill(Color.white.opacity(0.14))
                .frame(width: 5, height: alto + 28)
                .offset(y: -14)

            // El relleno con el degradado, desde arriba hasta el punto
            VStack(spacing: 0) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [colorRelleno, Color(hex: "#5c1e22")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 5, height: relleno)
                Spacer(minLength: 0)
            }

            // El punto, que viaja por la línea con el progreso
            ZStack {
                Circle()
                    .fill(Diseno.fondoFila)
                    .frame(width: diametro, height: diametro)
                    .overlay(Circle().stroke(colorPunto, lineWidth: 2.5))
                Circle()
                    .fill(colorPunto)
                    .frame(width: diametro * 0.42, height: diametro * 0.42)
            }
            .offset(y: relleno - diametro / 2)
        }
        .frame(width: 28, height: alto, alignment: .top)
    }
}

/// El enlace de una sola ubicación en Google Maps (como el `mapLink` de la web)
func enlaceGoogleMaps(_ ubicacion: Ubicacion) -> URL? {
    guard ubicacion.tieneCoordenadas else { return nil }
    return URL(string: "https://www.google.com/maps/search/?api=1&query=\(ubicacion.lat),\(ubicacion.lng)")
}

// ── El selector para AÑADIR paradas a una ruta que ya existe ─────────────────
/* Es el «＋ Añadir ubicaciones» de la web: un buscador con todas tus ubicaciones; las que
   ya están en la ruta salen marcadas y no se pueden repetir. Al tocar una, se añade al
   final y se guarda. */
struct ElegirParadasRuta: View {
    @ObservedObject var almacen: Almacen
    let yaEnLaRuta: Set<String>
    var alElegir: (Ubicacion) -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var consulta = ""

    var body: some View {
        NavigationStack {
            /* CON EL MISMO SwipeRow QUE EN TODAS LAS LISTAS DE UBICACIONES (franja de la
               categoría, bordes redondeados) y con el botón de FIJAR. Se usa un ScrollView
               (no una List) por el mismo motivo que en «Cambiar destino»: dentro de una List
               el fondo donde se pinta el hilo recibe alto cero. */
            ScrollView {
                LazyVStack(spacing: 10) {
                    buscador

                    if filtradas.isEmpty {
                        Text("Ninguna ubicación coincide con «\(consulta)»")
                            .font(.disSecundario)
                            .foregroundColor(Diseno.apagado)
                            .padding(.vertical, 20)
                    }

                    ForEach(filtradas) { ubicacion in
                        let dentro = yaEnLaRuta.contains(ubicacion.id)
                        FilaDeslizable(
                            izquierda: [
                                AccionFila(
                                    titulo: ubicacion.pinned ? "Desfijar" : "Fijar",
                                    icono: ubicacion.pinned ? "pin.slash.fill" : "pin.fill",
                                    color: Diseno.naranjaPin
                                ) {
                                    Task { await almacen.alternarFijada(ubicacion) }
                                },
                            ],
                            derecha: [
                                AccionFila(
                                    titulo: dentro ? "Ya está" : "Añadir",
                                    icono: dentro ? "checkmark.circle.fill" : "plus.circle.fill",
                                    color: dentro ? Diseno.apagado : Diseno.verde
                                ) {
                                    if !dentro { alElegir(ubicacion) }
                                },
                            ],
                            alTocar: { if !dentro { alElegir(ubicacion) } }
                        ) {
                            ContenidoFilaUbicacion(
                                ubicacion: ubicacion,
                                categoria: almacen.categoria(ubicacion.categoryId),
                                etiquetas: ubicacion.tagIds.compactMap { almacen.etiqueta($0) },
                                distancia: nil,
                                mostrarDireccion: true,
                                mostrarTiempoDistancia: false
                            )
                            .overlay(alignment: .topTrailing) {
                                if dentro {
                                    Text("ya está")
                                        .font(.disEtiqueta)
                                        .foregroundColor(Diseno.apagado)
                                        .padding(.trailing, 34)
                                        .padding(.top, 12)
                                }
                            }
                        }
                        .opacity(dentro ? 0.6 : 1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
            }
            .background(FondoMidnight())
            .simultaneousGesture(TapGesture().onEnded { FilasAbiertas.compartida.cerrarTodas() })
            .cerrarFilasAlDesplazar()
            .bloqueaScrollAlDeslizarFila()
            .navigationTitle("Añadir paradas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Diseno.fondo, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(Diseno.acento)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { cerrar() }
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

    private var filtradas: [Ubicacion] {
        let texto = consulta.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = almacen.ubicaciones.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let lista = texto.isEmpty ? base : base.filter { "\($0.name) \($0.address) \($0.code)".lowercased().contains(texto) }
        // Las fijadas, arriba (como en Ubicaciones y en la web)
        return lista.filter { $0.pinned } + lista.filter { !$0.pinned }
    }
}
