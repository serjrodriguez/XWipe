import SwiftUI

struct ContentView: View {
    @EnvironmentObject var e: Engine
    @State private var confirmAuto = false

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 14) {
                Text("1. Inicia sesión en X (panel derecho)").font(.headline)
                Text("2. Elige qué borrar y pulsa Escanear y borrar. No toques el panel derecho mientras corre.")
                    .font(.callout).foregroundStyle(.secondary)

                GroupBox("Qué borrar") {
                    VStack(alignment: .leading) {
                        Toggle("Posts y respuestas (\(e.count(.post)))", isOn: $e.doPosts)
                        Toggle("Reposts (\(e.count(.repost)))", isOn: $e.doReposts)
                        Toggle("Me gusta (\(e.count(.like)))", isOn: $e.doLikes)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }

                HStack {
                    Button("Escanear y borrar…", role: .destructive) { confirmAuto = true }
                        .disabled(e.running || e.scanning || !(e.doPosts || e.doReposts || e.doLikes))
                    Button("Detener") { e.stop() }.disabled(!e.running && !e.scanning)
                    Button("Reiniciar progreso") { e.resetProgress() }.disabled(e.running || e.scanning)
                }
                if e.running || e.total > 0 {
                    ProgressView(value: Double(e.processed), total: Double(max(e.total, 1)))
                }
                Text(e.status).font(.callout)
                ScrollView {
                    Text(e.log.suffix(60).joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(6).background(.quaternary.opacity(0.4)).cornerRadius(6)
            }
            .padding()
            .frame(minWidth: 340, idealWidth: 380, maxWidth: 460)

            WebViewRepresentable().frame(minWidth: 500)
        }
        .confirmationDialog("¿Escanear tu cuenta y borrar todo lo seleccionado?",
                            isPresented: $confirmAuto, titleVisibility: .visible) {
            Button("Escanear y borrar", role: .destructive) { Task { await e.autoWipe() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se repite hasta vaciar la cuenta. No se puede deshacer.")
        }
    }
}
