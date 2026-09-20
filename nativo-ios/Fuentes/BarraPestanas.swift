/* LA BARRA DE PESTAÑAS, con el diseño de la web.

   La barra del sistema no se puede pintar como la de la web (icono y texto en dorado
   cuando está activa, indicador arriba, fondo de cristal oscuro), así que se hace a mano:
   mismo alto, mismo cristal, mismo dorado.

   Cada pestaña lleva su icono, su nombre y, cuando está activa, el INDICADOR dorado
   encima (como el .tabbar-indicator de la web).
*/
import SwiftUI

struct Pestana: Identifiable {
    let id: Int
    let titulo: String
    let icono: String
    let iconoActivo: String
}

struct BarraPestanas: View {
    @Binding var seleccion: Int
    var alCambiar: ((Int) -> Void)? = nil

    static let todas: [Pestana] = [
        Pestana(id: 0, titulo: "Mapa", icono: "map", iconoActivo: "map.fill"),
        Pestana(id: 1, titulo: "Ubicaciones", icono: "list.bullet", iconoActivo: "list.bullet.rectangle.fill"),
        Pestana(id: 2, titulo: "Rutas", icono: "arrow.triangle.turn.up.right.diamond", iconoActivo: "arrow.triangle.turn.up.right.diamond.fill"),
        Pestana(id: 3, titulo: "Radares", icono: "camera", iconoActivo: "camera.fill"),
        Pestana(id: 4, titulo: "Ajustes", icono: "gearshape", iconoActivo: "gearshape.fill"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(BarraPestanas.todas) { pestana in
                let activa = pestana.id == seleccion
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        seleccion = pestana.id
                    }
                    alCambiar?(pestana.id)
                } label: {
                    VStack(spacing: 4) {
                        // El indicador dorado de la pestaña activa
                        Capsule()
                            .fill(activa ? Diseno.acento : .clear)
                            .frame(width: activa ? 26 : 0, height: 3)
                            .padding(.bottom, 1)
                        Image(systemName: activa ? pestana.iconoActivo : pestana.icono)
                            .font(.system(size: 21, weight: activa ? .bold : .regular))
                            .foregroundColor(activa ? Diseno.acento : Diseno.apagado)
                        Text(pestana.titulo)
                            .font(.system(size: 11, weight: activa ? .bold : .medium))
                            .foregroundColor(activa ? Diseno.acento : Diseno.apagado)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background {
            Diseno.fondoTarjetaAlta
                .overlay(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}
