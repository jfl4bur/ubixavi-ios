/* LAS INDICACIONES PASO A PASO, como en Apple Maps (imagen 6): la lista de giros con su
   flechita, lo que hay que hacer y los metros que faltan hasta el siguiente. */
import SwiftUI

struct PanelIndicaciones: View {
    let ruta: Ruta
    var cerrar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Detalles")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundColor(Diseno.texto)
                Text("\(textoDuracion(ruta.durationMins)) · \(textoDistancia(ruta.distKm))")
                    .font(.disSecundario)
                    .foregroundColor(Diseno.apagado)
                Spacer(minLength: 0)
                Button {
                    cerrar()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Diseno.texto)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            if let pasos = ruta.pasos, !pasos.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // El punto de salida
                        fila(
                            icono: "location.fill",
                            color: Diseno.azul,
                            titulo: "Salida",
                            detalle: "Desde donde estás",
                            distancia: nil
                        )
                        ForEach(Array(pasos.enumerated()), id: \.element.id) { indice, paso in
                            Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 62)
                            fila(
                                icono: iconoDe(paso.tipo, texto: paso.instruccion),
                                color: Diseno.acento,
                                titulo: textoDeDistancia(paso.distKm),
                                detalle: paso.instruccion,
                                distancia: indice == pasos.count - 1 ? "Llegada" : nil
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 20)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond")
                        .font(.system(size: 34))
                        .foregroundColor(Diseno.apagado)
                    Text("El motor de rutas no ha dado las indicaciones de este recorrido.")
                        .font(.disSecundario)
                        .foregroundColor(Diseno.apagado)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.top, 4)
    }

    private func fila(icono: String, color: Color, titulo: String, detalle: String, distancia: String?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icono)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(color)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(titulo)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(Diseno.texto)
                Text(detalle)
                    .font(.system(size: 16))
                    .foregroundColor(Diseno.apagado)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let distancia = distancia {
                Text(distancia)
                    .font(.disEtiqueta)
                    .foregroundColor(Diseno.verde)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
    }

    /// La flechita del giro, según el tipo de maniobra de Valhalla
    private func iconoDe(_ tipo: Int?, texto: String) -> String {
        let dicho = texto.lowercased()
        if dicho.contains("rotonda") { return "arrow.triangle.turn.up.right.circle" }
        if dicho.contains("izquierda") { return "arrow.turn.up.left" }
        if dicho.contains("derecha") { return "arrow.turn.up.right" }
        if dicho.contains("incorpor") || dicho.contains("incorpór") { return "arrow.merge" }
        if dicho.contains("salida") || dicho.contains("desvío") || dicho.contains("desvio") { return "arrow.up.right" }
        if dicho.contains("llegada") || dicho.contains("destino") { return "flag.checkered" }
        switch tipo {
        case 1, 2, 3: return "arrow.turn.up.left"
        case 4, 5, 6: return "arrow.turn.up.right"
        case 7, 8: return "arrow.uturn.up"
        case 26, 27: return "arrow.triangle.turn.up.right.circle"
        default: return "arrow.up"
        }
    }

    private func textoDeDistancia(_ km: Double) -> String {
        if km < 0.1 { return "Ahora" }
        return textoDistancia(km)
    }
}
