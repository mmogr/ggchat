#if os(iOS) && canImport(VisionKit)
    import GGChatCore
    import SwiftUI
    import VisionKit

    /// The app's one moment of theatre: the live camera, a pairing string
    /// recognised inline from a QR code or printed text, handed back the
    /// moment it parses.
    ///
    /// What gglib prints in that QR is `TICKET-CODE`, uppercased, because
    /// uppercase base32 is a QR alphanumeric payload and lowercase is not.
    /// So the whole candidate goes to modelpipe's reader, which owns the
    /// split on the last `-` and the case folding both; this view holds no
    /// parsing of its own.
    ///
    /// What it hands back is the candidate as the lens saw it, upper case
    /// and all. `mpPair` reads it the same way the reader just did, so
    /// lower-casing it here would only be this view having an opinion about
    /// a format it is trying not to know.
    ///
    /// A candidate that does not read is dropped without a word, because
    /// the text recogniser reports every string the lens can see: a scanner
    /// that complained about each one would be complaining about the room.
    struct ScanTicketView: View {
        /// Handed in rather than taken from `@Environment(AppModel.self)`,
        /// which traps when the model is absent. The presenting form holds
        /// the model already, and nothing on a simulator can open this view —
        /// `DataScannerViewController.isSupported` is false there — so a
        /// mistake here would first be seen on a phone, by a person, with the
        /// camera up.
        let reader: any PairingReader
        let onScan: (String) -> Void
        @Environment(\.dismiss) private var dismiss
        @State private var seen: String?

        static var isSupported: Bool {
            DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        }

        var body: some View {
            NavigationStack {
                DataScanner { candidate in
                    guard case .success = reader.read(candidate), seen == nil else { return }
                    seen = candidate
                    onScan(candidate)
                }
                .ignoresSafeArea()
                .overlay(alignment: .bottom) {
                    Text("Point the camera at the code gglib printed")
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: .capsule)
                        .padding(.bottom, 24)
                }
                .navigationTitle("Scan ticket")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    private struct DataScanner: UIViewControllerRepresentable {
        let onCandidate: (String) -> Void

        func makeUIViewController(context: Context) -> DataScannerViewController {
            let scanner = DataScannerViewController(
                recognizedDataTypes: [.barcode(symbologies: [.qr, .aztec, .dataMatrix]), .text()],
                qualityLevel: .balanced,
                recognizesMultipleItems: false,
                isHighFrameRateTrackingEnabled: false,
                isHighlightingEnabled: true)
            scanner.delegate = context.coordinator
            try? scanner.startScanning()
            return scanner
        }

        func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

        func makeCoordinator() -> Coordinator {
            Coordinator(onCandidate: onCandidate)
        }

        final class Coordinator: NSObject, DataScannerViewControllerDelegate {
            let onCandidate: (String) -> Void

            init(onCandidate: @escaping (String) -> Void) {
                self.onCandidate = onCandidate
            }

            func dataScanner(
                _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                allItems: [RecognizedItem]
            ) {
                for item in addedItems {
                    switch item {
                    case .barcode(let barcode):
                        if let payload = barcode.payloadStringValue { onCandidate(payload) }
                    case .text(let text):
                        onCandidate(text.transcript)
                    @unknown default:
                        break
                    }
                }
            }
        }
    }
#endif
