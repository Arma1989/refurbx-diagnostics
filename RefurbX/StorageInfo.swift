import Foundation
import SwiftUI

/// Display-only volume information. Never add these values to diagnostic outcomes or exports.
struct StorageSnapshot {
    let total: Int64
    let available: Int64
    var occupied: Int64 { total - available }

    static func read() throws -> StorageSnapshot {
        // Query the root filesystem. On APFS, FileManager's filesystem free
        // size includes free space shared by the system and data volumes.
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: "/")
        guard let totalValue = attributes[.systemSize] as? NSNumber,
              let availableValue = attributes[.systemFreeSize] as? NSNumber else {
            throw CocoaError(.fileReadUnknown)
        }
        let total = totalValue.int64Value
        let available = availableValue.int64Value
        guard total > 0, available >= 0, available <= total else {
            throw CocoaError(.fileReadUnknown)
        }
        return StorageSnapshot(total: total, available: available)
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
                Section("Informazioni sul file system") {
                    if let snapshot {
                        LabeledContent("Capacità del file system", value: StorageSnapshot.format(snapshot.total))
                        LabeledContent("Spazio disponibile", value: StorageSnapshot.format(snapshot.available))
                        LabeledContent("Spazio occupato (stima)", value: StorageSnapshot.format(snapshot.occupied))
                    } else {
                        Text(unavailable ? "Informazioni non disponibili. Riprova più tardi." : "Lettura in corso…")
                    }
                }
                Section {
                    Text("Dati del file system restituiti da iOS al momento della lettura. Lo spazio disponibile è lo spazio libero condiviso sul file system APFS. Lo spazio occupato è una stima calcolata sottraendo il disponibile dal totale. 1 GB = 1 miliardo di byte.")
                    Text("Impostazioni può mostrare valori leggermente diversi per via dello spazio riservato e dei dati di sistema. Non è una diagnosi della memoria RAM o dell'integrità dell'archiviazione.")
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
