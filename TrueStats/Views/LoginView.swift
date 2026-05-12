import SwiftUI

struct LoginView: View {
    @Environment(DashboardViewModel.self) private var viewModel
    @State private var endpoint: String = ""
    @State private var apiKey: String = ""
    @State private var isSubmitting: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "externaldrive.fill")
                    .foregroundStyle(.tint)
                Text("Sign in to TrueNAS")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Endpoint")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("https://nas.example.com", text: $endpoint)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    .onSubmit(submit)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("API key")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("Paste your user-linked API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
            }

            if case .loggedOut(let error?) = viewModel.authState {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Quit", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Connect")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
            }

            Text("Generate a user-linked API key in TrueNAS → Settings → My API Keys. The key is stored in your macOS Keychain.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            if endpoint.isEmpty, let saved = viewModel.endpoint?.absoluteString {
                endpoint = saved
            }
        }
    }

    private var canSubmit: Bool {
        !isSubmitting && !endpoint.trimmingCharacters(in: .whitespaces).isEmpty && !apiKey.isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        Task {
            await viewModel.login(endpointString: endpoint, apiKey: apiKey)
            isSubmitting = false
            if viewModel.authState.isLoggedIn {
                apiKey = "" // wipe from memory once it's in the keychain
            }
        }
    }
}
