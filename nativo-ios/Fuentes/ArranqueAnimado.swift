/* LA ANIMACIÓN DE ARRANQUE (la de la web).

   Sale SÓLO al iniciar la app de verdad: el degradado del tema, el halo dorado, las
   ondas que salen del logo y el logo (el coche y las ondas, sin fondo) apareciendo.
   Después se desvanece y deja la app.

   En la web se guardaba en sessionStorage para no repetirla al cambiar de pestaña; aquí
   basta con una variable estática, que dura lo que dura el arranque de la app.
*/
import SwiftUI

struct ArranqueAnimado: View {
    /// ¿Ya se ha visto la animación en este arranque?
    static var yaMostrado = false

    var alTerminar: () -> Void

    @State private var aparecer = false
    @State private var salir = false
    private let duracion: Double = 2.1

    var body: some View {
        ZStack {
            FondoMidnight()

            // Las ONDAS que salen del logo, una detrás de otra
            ForEach(0..<3, id: \.self) { indice in
                Circle()
                    .stroke(Diseno.acento.opacity(0.45), lineWidth: 1.5)
                    .frame(width: 130, height: 130)
                    .scaleEffect(aparecer ? 2.5 : 0.7)
                    .opacity(aparecer ? 0 : 0.5)
                    .animation(
                        .easeOut(duration: 2.0).delay(Double(indice) * 0.42),
                        value: aparecer
                    )
            }

            // El HALO dorado detrás del logo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Diseno.acento.opacity(0.28), .clear],
                        center: .center,
                        startRadius: 8,
                        endRadius: 160
                    )
                )
                .frame(width: 330, height: 330)
                .scaleEffect(aparecer ? 1.08 : 0.8)
                .animation(.easeOut(duration: 1.1), value: aparecer)

            // EL LOGO (el coche con las ondas, sin fondo)
            VStack(spacing: 14) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200)
                    .scaleEffect(aparecer ? 1 : 0.84)
                    .opacity(aparecer ? 1 : 0)
                    .animation(.spring(response: 0.75, dampingFraction: 0.72), value: aparecer)

                Text("Ubicaciones")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundColor(Diseno.acento)
                    .opacity(aparecer ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(0.25), value: aparecer)
            }
        }
        .opacity(salir ? 0 : 1)
        .onAppear {
            aparecer = true
            DispatchQueue.main.asyncAfter(deadline: .now() + duracion) {
                withAnimation(.easeOut(duration: 0.45)) { salir = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    alTerminar()
                }
            }
        }
    }
}
