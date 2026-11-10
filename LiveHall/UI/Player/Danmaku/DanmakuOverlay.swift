import AppKit
import SwiftUI

struct DanmakuOverlay: NSViewRepresentable {
    let channel: DanmakuChannel
    let isEnabled: Bool
    let settings: DanmakuSettings

    func makeNSView(context: Context) -> DanmakuLayerView {
        let view = DanmakuLayerView()
        channel.onSubmit = { [weak view] in view?.submit($0) }
        channel.onClear = { [weak view] in view?.clear() }
        return view
    }

    func updateNSView(_ nsView: DanmakuLayerView, context: Context) {
        nsView.setEnabled(isEnabled)
        nsView.apply(settings)
    }
}
