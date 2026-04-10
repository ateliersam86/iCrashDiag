import SwiftUI

struct ActivateLicenseView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var licenseService = LicenseService.shared
    @State private var keyInput = ""
    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var success = false

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                Text("Activate iCrashDiag Pro")
                    .font(.title3)
                    .fontWeight(.bold)
                Text("Enter the license key from your purchase email.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Input field
            VStack(alignment: .leading, spacing: 6) {
                Text("License Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("XXXX-XXXX-XXXX-XXXX", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .disabled(isValidating || success)
                    .onSubmit { validate() }
            }

            // Error
            if let err = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Success
            if success {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("License activated! Thank you for your support.")
                        .font(.callout)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }

            // Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    validate()
                } label: {
                    if isValidating {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Validating…")
                        }
                    } else if success {
                        Label("Done", systemImage: "checkmark")
                    } else {
                        Text("Activate")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty || isValidating)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private func validate() {
        guard !keyInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isValidating = true
        errorMessage = nil
        Task {
            do {
                try await licenseService.activate(key: keyInput)
                isValidating = false
                success = true
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                dismiss()
            } catch {
                isValidating = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
