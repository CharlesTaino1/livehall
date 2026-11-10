import SwiftUI

private struct ImageLoaderKey: EnvironmentKey {
    static let defaultValue = ImageLoader()
}

extension EnvironmentValues {
    var imageLoader: ImageLoader {
        get { self[ImageLoaderKey.self] }
        set { self[ImageLoaderKey.self] = newValue }
    }
}

struct CoverImage: View {
    let url: URL?
    let size: CGSize

    @Environment(\.imageLoader) private var loader
    @State private var image: CGImage?

    var body: some View {
        Theme.Color.placeholder
            .overlay {
                if let image {
                    Image(decorative: image, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                }
            }
            .clipped()
            .animation(Theme.Motion.imageFade, value: image == nil)
            .task(id: url) {
                guard let url else {
                    image = nil
                    return
                }
                let pixels = Int(max(size.width, size.height) * 2)
                if let cached = loader.cachedImage(url: url, maxPixelSize: pixels) {
                    image = cached
                    return
                }
                image = await loader.image(url: url, maxPixelSize: pixels)
            }
    }
}
