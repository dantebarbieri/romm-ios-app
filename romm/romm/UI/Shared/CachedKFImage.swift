//
//  CachedKFImage.swift
//  romm
//
//  Created by Claude on 15.11.25.
//

import SwiftUI
import Kingfisher

// MARK: - Cached Image using KFImage (Native Kingfisher SwiftUI Support)

struct CachedKFImage<Content: View, Placeholder: View>: View {
    private let request: RommImageRequest?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.init(
            request: resolveImageRequest(url?.absoluteString),
            content: content,
            placeholder: placeholder
        )
    }

    private init(
        request: RommImageRequest?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.request = request
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        CachedKFImageLoader(
            request: request,
            content: content,
            placeholder: placeholder
        )
    }
}

// MARK: - Internal Image Loader using KFImage

private struct CachedKFImageLoader<Content: View, Placeholder: View>: View {
    let request: RommImageRequest?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var loadedImage: KFCrossPlatformImage?

    var body: some View {
        Group {
            if let loadedImage = loadedImage {
                content(Image(uiImage: loadedImage))
            } else {
                placeholder()
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: request) { _, _ in
            loadedImage = nil
            loadImage()
        }
    }

    private func loadImage() {
        guard let request else { return }

        var options: KingfisherOptionsInfo = [
            .backgroundDecode,
            .scaleFactor(UIScreen.main.scale),
            .processor(DownsamplingImageProcessor(size: CGSize(width: 600, height: 600))),
            .transition(.fade(0.2))
        ]
        options.append(
            contentsOf: request.kingfisherOptions(
                sessionManager: RommImageSessionManager.shared
            )
        )

        KingfisherManager.shared.retrieveImage(with: request.url, options: options) { result in
            switch result {
            case .success(let value):
                loadedImage = value.image

            case .failure:
                let host = request.url.host ?? "unknown host"
                Logger.general.error("Failed to load image from \(host)")
            }
        }
    }
}

// MARK: - Convenience Initializers

extension CachedKFImage where Content == Image, Placeholder == Color {
    init(url: URL?) {
        self.init(
            request: resolveImageRequest(url?.absoluteString),
            content: { $0 },
            placeholder: { Color.gray.opacity(0.3) }
        )
    }
}

extension CachedKFImage where Placeholder == Color {
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(
            request: resolveImageRequest(url?.absoluteString),
            content: content,
            placeholder: { Color.gray.opacity(0.3) }
        )
    }
}

// MARK: - String URL Convenience

extension CachedKFImage {
    init(
        urlString: String?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.init(
            request: resolveImageRequest(urlString),
            content: content,
            placeholder: placeholder
        )
    }
}

extension CachedKFImage where Content == Image, Placeholder == Color {
    init(urlString: String?) {
        self.init(
            request: resolveImageRequest(urlString),
            content: { $0 },
            placeholder: { Color.gray.opacity(0.3) }
        )
    }
}

private func resolveImageRequest(_ reference: String?) -> RommImageRequest? {
    guard let reference else { return nil }
    do {
        return try RommImageRequestPolicy().resolve(reference)
    } catch APIClientError.noConfiguration {
        Logger.general.error("Cannot resolve RomM image without server configuration")
    } catch APIClientError.disallowedURL {
        Logger.general.error("Image URL rejected by security policy")
    } catch APIClientError.invalidURL {
        Logger.general.error("Image URL is malformed")
    } catch {
        Logger.general.error("Image URL resolution failed")
    }
    return nil
}
