import SwiftUI

/// The small glass line at the foot of the screen while a file downloads, and after:
/// "Downloaded <name>", which opens the file on a tap.
struct DownloadToast: View {
    let toast: DownloadStore.Toast
    var onOpen: (URL) -> Void
    var onDismiss: () -> Void

    var body: some View {
        switch toast {
        case .done(_, let url):
            Button {
                onOpen(url)
            } label: {
                face
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens the file"))
            .accessibilityIdentifier("download.toast")
        case .running, .failed:
            face
                .onTapGesture(perform: onDismiss)
                .accessibilityIdentifier("download.toast")
        }
    }

    private var face: some View {
        HStack(spacing: 10) {
            icon
            Text(line)
                .font(Typography.small.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, Metrics.Spacing.insetFloating)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(line))
    }

    @ViewBuilder private var icon: some View {
        switch toast {
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.teal)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(Palette.textPrimary)
        }
    }

    private var line: String {
        switch toast {
        case .running(let name): String(localized: "Downloading \(name)")
        case .done(let name, _): String(localized: "Downloaded \(name)")
        case .failed(let name): String(localized: "Couldn't download \(name)")
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        DownloadToast(toast: .running(name: "report.pdf"), onOpen: { _ in }, onDismiss: {})
        DownloadToast(
            toast: .done(name: "report.pdf", url: URL(filePath: "/report.pdf")),
            onOpen: { _ in }, onDismiss: {})
        DownloadToast(toast: .failed(name: "report.pdf"), onOpen: { _ in }, onDismiss: {})
    }
    .padding()
    .background(MistBackground())
}
