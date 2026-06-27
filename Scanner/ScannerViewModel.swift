import SwiftUI
import AVFoundation
import Network

@MainActor
@Observable
final class ScannerViewModel {
    // MARK: - Published state

    var scannedCodes: [ScannedCode] = []
    var isScanning = false
    var cameraPermissionGranted = false
    var errorMessage: String?

    // MARK: - Camera

    let captureSession = AVCaptureSession()
    private let metadataOutput = AVCaptureMetadataOutput()

    // MARK: - Network

    var companionHost: String {
        get { UserDefaults.standard.string(forKey: "companionHost") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "companionHost") }
    }
    var companionPort: String {
        get { UserDefaults.standard.string(forKey: "companionPort") ?? "9876" }
        set { UserDefaults.standard.set(newValue, forKey: "companionPort") }
    }
    var isSending = false

    // MARK: - Deduplication

    private var lastScannedValue = ""
    private var lastScanTime = Date.distantPast
    private let dedupInterval: TimeInterval = 2.0

    // MARK: - Supported barcode types

    static let supportedMetadataTypes: [AVMetadataObject.ObjectType] = [
        .qr,
        .ean8,
        .ean13,
        .upce,
        .code39,
        .code39Mod43,
        .code93,
        .code128,
        .pdf417,
        .aztec,
        .dataMatrix,
        .interleaved2of5,
        .itf14,
    ]

    // MARK: - Init

    init() {
        checkCameraPermission()
    }

    // MARK: - Permission

    func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionGranted = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    self?.cameraPermissionGranted = granted
                }
            }
        default:
            cameraPermissionGranted = false
        }
    }

    // MARK: - Session control

    func startScanning() {
        guard cameraPermissionGranted, !captureSession.isRunning else { return }

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        // Video input
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input)
        else {
            errorMessage = "Failed to access camera."
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)

        // Metadata output
        guard captureSession.canAddOutput(metadataOutput) else {
            errorMessage = "Failed to configure scanner."
            captureSession.commitConfiguration()
            return
        }
        captureSession.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(ScannerDelegate { [weak self] objects in
            self?.handleDetectedObjects(objects)
        }, queue: DispatchQueue.main)
        metadataOutput.metadataObjectTypes = Self.supportedMetadataTypes

        captureSession.commitConfiguration()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
            Task { @MainActor in
                self?.isScanning = true
            }
        }
    }

    func stopScanning() {
        guard captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
            Task { @MainActor in
                self?.isScanning = false
            }
        }
    }

    // MARK: - Detection

    private func handleDetectedObjects(_ objects: [AVMetadataObject]) {
        for object in objects {
            guard let machineReadable = object as? AVMetadataMachineReadableCodeObject,
                  let value = machineReadable.stringValue,
                  !value.isEmpty
            else { continue }

            // Deduplicate
            let now = Date()
            if value == lastScannedValue && now.timeIntervalSince(lastScanTime) < dedupInterval {
                continue
            }
            lastScannedValue = value
            lastScanTime = now

            let typeName = formatCodeType(machineReadable.type)
            let code = ScannedCode(
                value: value,
                type: typeName,
                timestamp: now
            )
            scannedCodes.insert(code, at: 0)
        }
    }

    private func formatCodeType(_ type: AVMetadataObject.ObjectType) -> String {
        switch type {
        case .qr: return "QR Code"
        case .ean8: return "EAN-8"
        case .ean13: return "EAN-13"
        case .upce: return "UPC-E"
        case .code39: return "Code 39"
        case .code39Mod43: return "Code 39 Mod 43"
        case .code93: return "Code 93"
        case .code128: return "Code 128"
        case .pdf417: return "PDF417"
        case .aztec: return "Aztec"
        case .dataMatrix: return "Data Matrix"
        case .interleaved2of5: return "Interleaved 2 of 5"
        case .itf14: return "ITF-14"
        default: return type.rawValue
        }
    }

    // MARK: - Send to computer

    func sendToComputer(_ text: String) async {
        let host = companionHost.trimmingCharacters(in: .whitespaces)
        let port = companionPort.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else {
            errorMessage = "No companion address set. Tap the gear icon to configure."
            return
        }

        isSending = true
        defer { isSending = false }

        let urlString = "http://\(host):\(port)/type"
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid companion address."
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5

        let body = ["text": text]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                errorMessage = "Companion returned error \(httpResponse.statusCode)."
            }
        } catch {
            errorMessage = "Failed to reach companion: \(error.localizedDescription)"
        }
    }

    func clearHistory() {
        scannedCodes.removeAll()
        lastScannedValue = ""
    }
}

// MARK: - ScannedCode model

struct ScannedCode: Identifiable {
    let id = UUID()
    let value: String
    let type: String
    let timestamp: Date
}

// MARK: - Scanner delegate

private final class ScannerDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    private let handler: ([AVMetadataObject]) -> Void

    init(handler: @escaping ([AVMetadataObject]) -> Void) {
        self.handler = handler
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        handler(metadataObjects)
    }
}
