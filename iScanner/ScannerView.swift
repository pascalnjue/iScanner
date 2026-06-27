import SwiftUI

struct ScannerView: View {
    @State private var viewModel = ScannerViewModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Camera area
                cameraSection

                // Results list
                if viewModel.scannedCodes.isEmpty {
                    emptyState
                } else {
                    resultsList
                }
            }
            .navigationTitle("iScanner")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if !viewModel.scannedCodes.isEmpty {
                        Button("Clear") {
                            viewModel.clearHistory()
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(viewModel: viewModel)
            }
            .alert("iScanner Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onAppear {
                if viewModel.cameraPermissionGranted {
                    viewModel.startScanning()
                }
            }
            .onDisappear {
                viewModel.stopScanning()
            }
        }
    }

    // MARK: - Camera section

    @ViewBuilder
    private var cameraSection: some View {
        ZStack {
            if viewModel.isScanning && viewModel.cameraPermissionGranted {
                CameraPreview(captureSession: viewModel.captureSession)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                // Scanning indicator
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "viewfinder")
                            .font(.title2)
                        Text("Point at a barcode or QR code")
                            .font(.caption)
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
                .padding(.bottom, 16)
            } else if !viewModel.cameraPermissionGranted {
                permissionDenied
            } else {
                cameraPlaceholder
            }
        }
        .frame(height: 320)
    }

    private var cameraPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Camera not started")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("Start Scanning") {
                viewModel.checkCameraPermission()
                viewModel.startScanning()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var permissionDenied: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.slash")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("Camera access required")
                .font(.headline)
            Text("Open Settings to grant camera permission.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Scanned codes will appear here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Results list

    private var resultsList: some View {
        List {
            ForEach(viewModel.scannedCodes) { code in
                ScannedCodeRow(code: code) {
                    Task {
                        await viewModel.sendToComputer(code.value)
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Scanned code row

struct ScannedCodeRow: View {
    let code: ScannedCode
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(code.type)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(codeTypeColor, in: Capsule())

                Spacer()

                Text(code.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(code.value)
                .font(.body.monospaced())
                .lineLimit(3)

            HStack {
                Button {
                    UIPasteboard.general.string = code.value
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)

                Spacer()

                Button(action: onSend) {
                    Label("Send to Computer", systemImage: "keyboard")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    private var codeTypeColor: Color {
        switch code.type {
        case "QR Code": return .blue
        case "EAN-13", "EAN-8", "UPC-E": return .green
        case "Code 128", "Code 39", "Code 93", "Code 39 Mod 43": return .orange
        case "PDF417": return .purple
        case "Data Matrix": return .pink
        case "Aztec": return .teal
        default: return .gray
        }
    }
}

// MARK: - Settings view

struct SettingsView: View {
    @Bindable var viewModel: ScannerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Companion Connection") {
                    TextField("Host (e.g. 192.168.1.5)", text: $viewModel.companionHost)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()

                    TextField("Port", text: $viewModel.companionPort)
                        .keyboardType(.numberPad)
                }

                Section {
                    Text("The companion runs on your Mac and types scanned text into the focused input field.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    ScannerView()
}
