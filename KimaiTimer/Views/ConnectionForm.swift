import KimaiKit
import SwiftUI

/// Server address and credentials, with an inline test. Used by the welcome screen and Settings.
struct ConnectionForm: View {
    @Environment(AppModel.self) private var model
    @State private var input = ConnectionInput()
    @State private var status = Status.idle
    @State private var confirmDisconnect = false
    @FocusState private var focus: Field?

    private enum Field {
        case server
        case username
        case token
    }

    private enum Status: Equatable {
        case idle
        case working
        case success(ConnectionSummary)
        case failure(String)
    }

    private var isInsecure: Bool {
        input.url.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("http://")
    }

    var body: some View {
        Form {
            Section {
                TextField(L("Kimai server"), text: $input.url, prompt: Text(verbatim: "https://kimai.example.com"))
                    .textContentType(.URL)
                    .focused($focus, equals: .server)
                    .onSubmit { focus = input.mode == .legacy ? .username : .token }
                Picker(L("Sign in with"), selection: $input.mode) {
                    Text(L("API token")).tag(AuthMode.bearer)
                    Text(L("User name and API password")).tag(AuthMode.legacy)
                }
                if input.mode == .legacy {
                    TextField(L("User name"), text: $input.username)
                        .textContentType(.username)
                        .focused($focus, equals: .username)
                        .onSubmit { focus = .token }
                }
                SecureField(
                    input.mode == .legacy ? L("API password") : L("API token"), text: $input.token,
                    prompt: Text(input.mode == .legacy ? L("Paste API password") : L("Paste API token")))
                    .focused($focus, equals: .token)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(input.mode == .legacy
                        ? L("The API password is the older sign-in method. Newer Kimai versions only accept API tokens, which you create in Kimai under your profile › API access.")
                        : L("Create an API token in Kimai under your profile › API access. It is stored in your Keychain."))
                    if isInsecure {
                        Label(
                            L("Without https the token is sent unencrypted. Use this only on a network you trust."),
                            systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                statusRow
                HStack {
                    Spacer()
                    Button(L("Test Connection")) { run(save: false) }
                        .disabled(input.configuration == nil || status == .working)
                    Button(model.isConfigured ? L("Save") : L("Connect")) { run(save: true) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(input.configuration == nil || status == .working || model.isWorking)
                }
            }

            if model.isConfigured {
                Section {
                    Button(L("Disconnect…"), role: .destructive) { confirmDisconnect = true }
                        .disabled(model.isWorking || status == .working)
                } footer: {
                    Text(L("Removes the token from the Keychain. Your entries stay in Kimai."))
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            input = model.storedConnection()
            if input.url.isEmpty { focus = .server }
        }
        .onChange(of: input) {
            if status != .working { status = .idle }
        }
        .confirmationDialog(L("Disconnect from Kimai?"), isPresented: $confirmDisconnect) {
            Button(L("Disconnect"), role: .destructive) {
                model.disconnect()
                input = ConnectionInput()
                status = .idle
            }
            Button(L("Cancel"), role: .cancel) {}
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch status {
        case .idle:
            if model.isConfigured, let version = model.serverVersion, input == model.storedConnection() {
                Label(
                    L("Connected to Kimai %@ as %@", version, model.user?.displayName ?? input.username),
                    systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text(L("Enter the address of your Kimai server and your credentials."))
                    .foregroundStyle(.secondary)
            }
        case .working:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("Contacting Kimai…"))
            }
        case .success(let summary):
            Label(
                L("Connected to Kimai %@ as %@", summary.version, summary.userName),
                systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func run(save: Bool) {
        let current = input
        status = .working
        Task {
            let result = save ? await model.connect(current) : await model.test(current)
            switch result {
            case .success(let summary):
                status = .success(summary)
            case .failure(.cancelled):
                status = .idle
            case .failure(let error):
                status = .failure(ErrorText.message(for: error))
            }
        }
    }
}

/// First-launch screen of the main window.
struct WelcomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(L("Connect to Kimai"))
                    .font(.title.weight(.semibold))
                Text(L("Kimai Timer books your time directly into your own Kimai installation."))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                ConnectionForm()
                    .frame(maxWidth: 520)
                    .scrollDisabled(true)
            }
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
    }
}
