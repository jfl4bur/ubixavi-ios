/* ESTADÍSTICAS, DIAGNÓSTICO E IMPORTAR DATOS.

   Las tres pantallas de datos, como las que tenía la web:
   · Estadísticas: cuántas cosas hay y cómo están repartidas.
   · Diagnóstico: si el GPS, el servidor y los radares responden (para saber qué pasa
     cuando algo no va).
   · Importar: pegar una copia de seguridad (el JSON que exporta la propia app) para
     volver a dejar los datos como estaban.
*/
import SwiftUI

// ── Estadísticas ──────────────────────────────────────────────────────────────
struct PantallaEstadisticas: View {
    @ObservedObject var almacen: Almacen
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    GrupoEstadisticas(titulo: "Ubicaciones") {
                        FilaDato("En total", "\(almacen.ubicaciones.count)", Diseno.oro)
                        FilaDato("Con coordenadas", "\(almacen.ubicaciones.filter { $0.tieneCoordenadas }.count)", Diseno.verde)
                        FilaDato("Fijadas", "\(almacen.ubicaciones.filter { $0.pinned }.count)", Diseno.naranjaPin)
                        FilaDato("Con fotos", "\(almacen.ubicaciones.filter { !$0.photos.isEmpty }.count)", Diseno.acento)
                        FilaDato("Con notas", "\(almacen.ubicaciones.filter { !$0.notes.isEmpty }.count)", Diseno.morado)
                    }

                    GrupoEstadisticas(titulo: "Categorías") {
                        ForEach(almacen.categorias.sorted { cuenta($0) > cuenta($1) }) { categoria in
                            HStack {
                                Circle().fill(Color(hex: categoria.color)).frame(width: 14, height: 14)
                                Text(categoria.name).font(.disCuerpo)
                                Spacer()
                                Text("\(cuenta(categoria))").foregroundColor(Diseno.apagado)
                            }
                        }
                        if almacen.categorias.isEmpty {
                            Text("Sin categorías").foregroundColor(Diseno.apagado)
                        }
                        FilaDato("Sin categoría", "\(almacen.ubicaciones.filter { $0.categoryId.isEmpty }.count)", Diseno.apagado)
                    }

                    GrupoEstadisticas(titulo: "Etiquetas y rutas") {
                        FilaDato("Etiquetas", "\(almacen.etiquetas.count)", Diseno.morado)
                        FilaDato("Rutas guardadas", "\(almacen.rutas.count)", Diseno.verde)
                        FilaDato("Paradas en total", "\(almacen.rutas.reduce(0) { $0 + $1.locationIds.count })", Diseno.acento)
                        if let masLarga = almacen.rutas.max(by: { $0.locationIds.count < $1.locationIds.count }) {
                            FilaDato("Ruta más larga", "\(masLarga.name) (\(masLarga.locationIds.count))", Diseno.oro)
                        }
                    }

                    GrupoEstadisticas(titulo: "Papelera") {
                        FilaDato("Elementos", "\(almacen.papelera.count)", Diseno.peligro)
                    }
                }
                .padding(16)
            }
            .fondoApp()
            .navigationTitle("Estadísticas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { cerrar() }
                }
            }
        }
    }

    private func cuenta(_ categoria: Categoria) -> Int {
        almacen.ubicaciones.filter { $0.categoryId == categoria.id }.count
    }
}

struct GrupoEstadisticas<Contenido: View>: View {
    let titulo: String
    @ViewBuilder var contenido: Contenido

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titulo)
                .font(.disSubtitulo)
                .foregroundColor(Diseno.texto)
            VStack(alignment: .leading, spacing: 8) {
                contenido
            }
            .font(.disCuerpo)
            .foregroundColor(Diseno.texto)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tarjeta()
    }
}

struct FilaDato: View {
    let titulo: String
    let valor: String
    var color: Color = Diseno.apagado

    init(_ titulo: String, _ valor: String, _ color: Color = Diseno.apagado) {
        self.titulo = titulo
        self.valor = valor
        self.color = color
    }

    var body: some View {
        HStack {
            Text(titulo).foregroundColor(Diseno.apagado)
            Spacer()
            Text(valor).foregroundColor(color).fontWeight(.bold)
        }
    }
}

// ── Diagnóstico ───────────────────────────────────────────────────────────────
struct PantallaDiagnostico: View {
    @ObservedObject var almacen: Almacen
    @ObservedObject var estado: Estado
    @Environment(\.dismiss) private var cerrar
    @State private var comprobando = false
    @State private var estadoBase: Servidor.EstadoBase?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    GrupoEstadisticas(titulo: "Servidor") {
                        FilaDato("Datos", almacen.fallo == nil ? "✅ responden" : "❌ \(almacen.fallo ?? "")", almacen.fallo == nil ? Diseno.verde : Diseno.peligro)
                        FilaDato("Última carga", almacen.ultimaCarga.map { hora($0) } ?? "—", Diseno.texto)
                        FilaDato("Ubicaciones", "\(almacen.ubicaciones.count)", Diseno.texto)
                        FilaDato("Base de radares", estadoBase?.count.map { "\($0) radares" } ?? "—", Diseno.texto)
                        FilaDato("Base actualizada", estadoBase?.updatedAt.map { fecha($0) } ?? "—", Diseno.apagado)
                    }

                    GrupoEstadisticas(titulo: "GPS") {
                        if let pos = estado.posicion {
                            FilaDato("Precisión", String(format: "±%.0f m", pos.horizontalAccuracy), pos.horizontalAccuracy < 30 ? Diseno.verde : Diseno.naranja)
                            FilaDato("Velocidad", estado.velocidadKmh.map { "\($0) km/h" } ?? "—", Diseno.texto)
                            FilaDato("Rumbo", estado.rumbo >= 0 ? "\(Int(estado.rumbo))°" : "—", Diseno.texto)
                            FilaDato("Posición", String(format: "%.5f, %.5f", pos.coordinate.latitude, pos.coordinate.longitude), Diseno.apagado)
                        } else {
                            FilaDato("Posición", "todavía sin señal", Diseno.naranja)
                        }
                    }

                    GrupoEstadisticas(titulo: "Radares") {
                        FilaDato("Cerca de ti", "\(estado.radares.count)", Diseno.texto)
                        FilaDato("Avisando ahora", estado.radarAvisando != nil ? "sí" : "no", estado.radarAvisando != nil ? Diseno.naranjaPin : Diseno.apagado)
                        FilaDato("Límite detectado", estado.limiteActual.map { "\($0) km/h" } ?? "—", Diseno.texto)
                        FilaDato("Avisos", (UserDefaults.standard.object(forKey: "avisosRadares") as? Bool ?? true) ? "activados" : "apagados", Diseno.texto)
                        FilaDato("Sólo en ruta", (UserDefaults.standard.object(forKey: "soloRadaresEnRuta") as? Bool ?? false) ? "sí" : "no", Diseno.apagado)
                    }

                    GrupoEstadisticas(titulo: "Navegación") {
                        FilaDato("Navegando", estado.navegando ? "sí" : "no", estado.navegando ? Diseno.verde : Diseno.apagado)
                        FilaDato("Paradas del viaje", "\(estado.paradas.count)", Diseno.texto)
                        FilaDato("Ruta elegida", estado.rutaElegida.map { "\(String(format: "%.1f", $0.distKm)) km · \(Int($0.durationMins)) min" } ?? "—", Diseno.texto)
                        FilaDato("Queda", estado.quedaKm.map { String(format: "%.1f km", $0) } ?? "—", Diseno.acento)
                    }

                    Button {
                        Task {
                            comprobando = true
                            estadoBase = try? await Servidor.estadoBase()
                            comprobando = false
                        }
                    } label: {
                        Label(comprobando ? "Comprobando…" : "Volver a comprobar", systemImage: "arrow.clockwise")
                            .font(.disCuerpo.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Diseno.acento.opacity(0.2), in: RoundedRectangle(cornerRadius: Diseno.radioSm))
                            .foregroundColor(Diseno.texto)
                    }
                    .buttonStyle(.plain)
                    .disabled(comprobando)
                }
                .padding(16)
            }
            .fondoApp()
            .navigationTitle("Diagnóstico")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { cerrar() }
                }
            }
            .task { estadoBase = try? await Servidor.estadoBase() }
        }
    }

    private func hora(_ fecha: Date) -> String {
        let formato = DateFormatter()
        formato.dateFormat = "HH:mm:ss"
        return formato.string(from: fecha)
    }

    private func fecha(_ milisegundos: Double) -> String {
        let formato = DateFormatter()
        formato.dateFormat = "dd/MM HH:mm"
        return formato.string(from: Date(timeIntervalSince1970: milisegundos / 1000))
    }
}

// ── Importar datos ────────────────────────────────────────────────────────────
struct PantallaImportar: View {
    @ObservedObject var almacen: Almacen
    @Environment(\.dismiss) private var cerrar
    @State private var texto = ""
    @State private var confirmar = false
    @State private var importando = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pega aquí una copia de seguridad (el texto que saca «Copiar TODOS los datos»). Se subirá al servidor tal cual: si tenías algo distinto, se reemplaza.")
                        .font(.disSecundario)
                        .foregroundColor(Diseno.apagado)

                    TextEditor(text: $texto)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 220)
                        .padding(8)
                        .background(Diseno.fondoTarjeta, in: RoundedRectangle(cornerRadius: Diseno.radioSm))
                        .overlay(RoundedRectangle(cornerRadius: Diseno.radioSm).stroke(Diseno.linea, lineWidth: 1))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    HStack(spacing: 10) {
                        Button {
                            if let pegado = UIPasteboard.general.string { texto = pegado }
                        } label: {
                            Label("Pegar", systemImage: "doc.on.clipboard")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: Diseno.radioSm))
                                .foregroundColor(Diseno.texto)
                        }
                        .buttonStyle(.plain)

                        Button {
                            confirmar = true
                        } label: {
                            Label(importando ? "Importando…" : "Importar", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Diseno.peligro.opacity(0.25), in: RoundedRectangle(cornerRadius: Diseno.radioSm))
                                .foregroundColor(Diseno.texto)
                        }
                        .buttonStyle(.plain)
                        .disabled(importando || texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(16)
            }
            .fondoApp()
            .navigationTitle("Importar datos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { cerrar() }
                }
            }
            .alert("¿Seguro que quieres importar?", isPresented: $confirmar) {
                Button("Cancelar", role: .cancel) {}
                Button("Importar", role: .destructive) {
                    Task {
                        importando = true
                        let bien = await almacen.importar(texto)
                        importando = false
                        if bien { cerrar() }
                    }
                }
            } message: {
                Text("Los datos del servidor se reemplazan por los de la copia.")
            }
        }
    }
}
