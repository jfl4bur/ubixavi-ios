/* AVISOS FLOTANTES (los «toasts» de la web).

   Un cartelito que sale abajo, dice lo que ha pasado («Ubicación añadida», «Radar
   capturado», «No pude guardar…») y se va solo a los dos segundos. Antes las acciones
   se hacían en silencio y no sabías si habían funcionado.
*/
import SwiftUI

struct Aviso: Identifiable, Equatable {
    enum Tipo { case bien, mal, info }
    let id = UUID()
    let texto: String
    let tipo: Tipo

    var color: Color {
        switch tipo {
        case .bien: return Diseno.verde
        case .mal: return Diseno.peligro
        case .info: return Diseno.acento
        }
    }

    var icono: String {
        switch tipo {
        case .bien: return "checkmark.circle.fill"
        case .mal: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

@MainActor
final class AvisosFlotantes: ObservableObject {
    /// Uno solo para toda la app (se usa desde el almacén y desde las pantallas)
    static let compartido = AvisosFlotantes()

    @Published private(set) var actual: Aviso?
    private var tarea: Task<Void, Never>?

    func bien(_ texto: String) { mostrar(texto, tipo: .bien) }
    func mal(_ texto: String) { mostrar(texto, tipo: .mal) }
    func info(_ texto: String) { mostrar(texto, tipo: .info) }

    func mostrar(_ texto: String, tipo: Aviso.Tipo = .bien) {
        // Se pueden apagar desde Ajustes
        let activados = UserDefaults.standard.object(forKey: "avisosFlotantes") as? Bool ?? true
        guard activados else { return }
        tarea?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            actual = Aviso(texto: texto, tipo: tipo)
        }
        tarea = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    self?.actual = nil
                }
            }
        }
    }
}

/// El cartel, para ponerlo encima de todo en la pantalla principal
struct AvisoFlotanteVista: View {
    @ObservedObject var avisos: AvisosFlotantes

    var body: some View {
        VStack {
            Spacer()
            if let aviso = avisos.actual {
                HStack(spacing: 10) {
                    Image(systemName: aviso.icono)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(aviso.color)
                    Text(aviso.texto)
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundColor(Diseno.texto)
                        .lineLimit(3)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(Diseno.fondoTarjetaAlta, in: RoundedRectangle(cornerRadius: Diseno.radioSm))
                .overlay(RoundedRectangle(cornerRadius: Diseno.radioSm).stroke(aviso.color.opacity(0.55), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                .padding(.horizontal, 16)
                .padding(.bottom, 86)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
    }
}
