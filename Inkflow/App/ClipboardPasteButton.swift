import SwiftUI
import UIKit

struct ClipboardPasteButton: View {
    var receive: ([String]) -> Void
    var body: some View {
        #if targetEnvironment(macCatalyst)
        Button {
            if let text = UIPasteboard.general.string { receive([text]) }
        } label: { Label("粘贴", systemImage: "doc.on.clipboard") }
            .buttonStyle(.borderedProminent).controlSize(.regular).fixedSize()
            .accessibilityLabel("粘贴文字")
        #else
        PasteButton(payloadType: String.self, onPaste: receive)
            .labelStyle(.titleAndIcon).buttonBorderShape(.capsule).controlSize(.regular).fixedSize()
            .accessibilityLabel("粘贴文字")
        #endif
    }
}
