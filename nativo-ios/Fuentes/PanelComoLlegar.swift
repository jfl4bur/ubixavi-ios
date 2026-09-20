/* EL PANEL DE «CÓMO LLEGAR», como Apple Maps (imagen 5): una FILA POR RUTA con su duración,
   sus km, la hora de llegada y su botón IR. Tocando la fila (fuera del IR) se elige esa ruta
   para verla en el mapa. */
import SwiftUI

struct PanelComoLlegar: View {
    @ObservedObject var estado: Estado
    var cerrar: () -> Void
    /// La ruta cuyas indicaciones se están viendo (al tocar una fila)
    @State private var viendoIndicaciones: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            /* LA X PARA CERRARLO (como en la imagen): al tocarla, este panel se cierra y
               vuelve todo al principio, con la barra de buscar «Ubicaciones» otra vez. */
            HStack(alignment: .center, spacing: 10) {
                Text("Cómo llegar")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundColor(Diseno.texto)
                Spacer(minLength: 0)
                Button {
                    estado.limpiarViaje()
                    cerrar()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Diseno.texto)
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.16), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            // EL PERFIL: en coche o a pie (como en tu imagen)
            HStack(spacing: 10) {
                perfil("coche", titulo: "En coche", icono: "car.fill")
                perfil("pie", titulo: "A pie", icono: "figure.walk")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(estado.rutas.enumerated()), id: \.offset) { indice, ruta in
                        filaDeRuta(indice: indice, ruta: ruta)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
            }
        }
        .padding(.top, 4)
        /* AL TOCAR UNA FILA (fuera del botón IR) salen LAS INDICACIONES PASO A PASO */
        .sheet(item: Binding(
            get: { viendoIndicaciones.flatMap { estado.rutas.indices.contains($0) ? TextoIdentificable(id: "\($0)", texto: "") : nil } },
            set: { if $0 == nil { viendoIndicaciones = nil } }
        )) { cual in
            if let indice = Int(cual.id), estado.rutas.indices.contains(indice) {
                PanelIndicaciones(ruta: estado.rutas[indice]) { viendoIndicaciones = nil }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .fondoDelPanelNativo()
            }
        }
    }

    private func filaDeRuta(indice: Int, ruta: Ruta) -> some View {
        let elegida = indice == estado.elegida
        let llegada = Date().addingTimeInterval(ruta.durationMins * 60)
        return HStack(spacing: 12) {
            Button {
                estado.elegida = indice
                viendoIndicaciones = indice
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(textoDuracion(ruta.durationMins))
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundColor(Diseno.texto)
                        if ruta.principal == true {
                            Text("Más rápida")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Diseno.verde, in: Capsule())
                        }
                    }
                    Text("\(textoDistancia(ruta.distKm)) · Llegada \(horaDe(llegada))")
                        .font(.system(size: 15))
                        .foregroundColor(Diseno.apagado)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // EL BOTÓN IR: arranca la navegación con ESA ruta
            Button {
                estado.elegida = indice
                Task {
                    await estado.iniciarNavegacion()
                    cerrar()
                }
            } label: {
                Text("IR")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: 66, height: 46)
                    .background(Diseno.verde, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: Diseno.radio)
                .fill(elegida ? Diseno.acento.opacity(0.22) : Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Diseno.radio)
                .stroke(elegida ? Diseno.acento : Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    /// Un perfil (coche / a pie): al tocarlo se recalcula la ruta
    private func perfil(_ clave: String, titulo: String, icono: String) -> some View {
        Button {
            Task { await estado.cambiarPerfil(clave) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icono).font(.system(size: 20, weight: .bold))
                Text(titulo).font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(estado.perfil == clave ? .black : Diseno.texto)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(estado.perfil == clave ? Diseno.acento : Color.white.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func horaDe(_ fecha: Date) -> String {
        let formato = DateFormatter()
        formato.dateFormat = "HH:mm"
        return formato.string(from: fecha)
    }
}
