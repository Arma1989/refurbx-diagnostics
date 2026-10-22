import Foundation
import SwiftUI

/// Display-only volume information. Never add these values to diagnostic outcomes or exports.
struct StorageSnapshot {
    let total: Int64
    let available: Int64
    var occupied: Int64 { total - available }

    static func read() throws -> StorageSnapshot {
        // Ask iOS about the volume containing the user's Documents directory.
        // Important-usage capacity estimates space available for user-requested
        // content; the immediate free-block count can be much lower on APFS.
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileReadUnknown)
        }
        let values = try documents.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ])
        let availableCapacity = values.volumeAvailableCapacityForImportantUsage
            ?? values.volumeAvailableCapacity.map(Int64.init)
        guard let totalValue = values.volumeTotalCapacity,
              let availableValue = availableCapacity else {
            throw CocoaError(.fileReadUnknown)
        }
        let total = Int64(totalValue)
        let available = Int64(availableValue)
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
                        LabeledContent("Disponibile per nuovi contenuti", value: StorageSnapshot.format(snapshot.available))
                        LabeledContent("Spazio occupato (stima)", value: StorageSnapshot.format(snapshot.occupied))
                    } else {
                        Text(unavailable ? "Informazioni non disponibili. Riprova più tardi." : "Lettura in corso…")
                    }
                }
                Section {
                    Text("Stima iOS dello spazio disponibile per contenuti richiesti dall'utente sul volume dell'app. Il valore può differire da Impostazioni perché iOS riserva spazio e gestisce i contenuti eliminabili. Lo spazio occupato è una stima calcolata sottraendo il disponibile dal totale. 1 GB = 1 miliardo di byte.")
                    Text("Queste informazioni non diagnosticano la memoria RAM o l'integrità dell'archiviazione.")
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
