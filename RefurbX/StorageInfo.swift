import Foundation
import SwiftUI

/// Display-only volume information. Never add these values to diagnostic outcomes or exports.
struct StorageSnapshot {
    let total: Int64
    let available: Int64
    var occupied: Int64 { total - available }

    static func read() throws -> StorageSnapshot {
        let url = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let values = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        guard let totalValue = values.volumeTotalCapacity,
              let availableValue = values.volumeAvailableCapacity,
              totalValue > 0, availableValue >= 0, availableValue <= totalValue else {
            throw CocoaError(.fileReadUnknown)
        }
        return StorageSnapshot(total: Int64(totalValue), available: Int64(availableValue))
    }

    static func format(_ bytes: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        let value = formatter.string(from: NSNumber(value: Double(bytes) / 1_000_000_000)) ?? "—"
        return "\(value) GB"
    }
}

struct StorageInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: StorageSnapshot?
    @State private var unavailable = false
    @State private var refreshedAt: Date?

    var body: some View {
        NavigationStack {
            List {
                Section("Informazioni sul volume") {
                    if let snapshot {
                        LabeledContent("Spazio totale del volume", value: StorageSnapshot.format(snapshot.total))
                        LabeledContent("Spazio libero", value: StorageSnapshot.format(snapshot.available))
                        LabeledContent("Spazio occupato (stima)", value: StorageSnapshot.format(snapshot.occupied))
                    } else {
                        Text(unavailable ? "Informazioni non disponibili. Riprova più tardi." : "Lettura in corso…")
                    }
                }
                Section {
                    Text("Dati del volume restituiti da iOS al momento della lettura. Lo spazio libero è la capacità disponibile del volume. Lo spazio occupato è una stima calcolata sottraendo il libero dal totale. 1 GB = 1 miliardo di byte.")
                    Text("Il valore può differire leggermente da Impostazioni perché iOS gestisce cache, dati di sistema e spazio recuperabile. Non è una diagnosi della memoria RAM o dell'integrità del disco.")
                    Text("Questa schermata è informativa: non esegue una diagnosi della RAM o dell'integrità dell'archiviazione. I valori non vengono salvati nella scheda, esportati o inviati al banco.")
                }
                Section {
                    Button("Aggiorna", action: refresh)
                    if let refreshedAt {
                        Text("Ultima lettura: \(refreshedAt.formatted(date: .omitted, time: .standard))")
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Spazio di archiviazione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .onAppear(perform: refresh)
        }
    }

    private func refresh() {
        do {
            snapshot = try StorageSnapshot.read()
            unavailable = false
            refreshedAt = Date()
        } catch {
            snapshot = nil
            unavailable = true
            refreshedAt = nil
        }
    }
}
