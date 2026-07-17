//
//  KingfisherCacheManager.swift
//  romm
//
//  Created by Ilyas Hallak on 27.08.25.
//

import Foundation
import Kingfisher
import UIKit

// MARK: - Kingfisher Configuration Manager

class KingfisherCacheManager: ObservableObject {
    static let shared = KingfisherCacheManager()
    
    private let settings = ImageCacheSettings.shared
    private let legacyPrivateCache = ImageCache(name: "romm-private-assets")
    
    private init() {
        configureKingfisher()
    }
    
    func configureKingfisher() {
        legacyPrivateCache.clearDiskCache()

        // Configure memory cache with reasonable defaults (not user-configurable)
        ImageCache.default.memoryStorage.config.totalCostLimit = 100 * 1024 * 1024 // 100 MB
        ImageCache.default.memoryStorage.config.countLimit = 500

        // Configure disk cache with size limit AND expiry
        ImageCache.default.diskStorage.config.sizeLimit = UInt(settings.diskCacheLimitBytes)
        ImageCache.default.diskStorage.config.expiration = .seconds(settings.diskCacheExpirySeconds)

        // Configure downloader
        ImageDownloader.default.downloadTimeout = 30.0
        ImageDownloader.default.sessionConfiguration.httpMaximumConnectionsPerHost = 6

        // Configure default options for KingfisherManager
        KingfisherManager.shared.defaultOptions = [
            .diskCacheExpiration(.seconds(settings.diskCacheExpirySeconds)),
            .backgroundDecode,
            .scaleFactor(UIScreen.main.scale)
        ]

        Logger.general.info("🖼️ Kingfisher configured: Memory=100MB, Disk=\(settings.diskCacheLimitBytes / 1024 / 1024)MB, Expiry=\(settings.diskCacheExpirySeconds / 86400)d")
    }
    
    func updateSettings() {
        configureKingfisher()
        // Let Kingfisher handle cache management automatically
    }
    
    func clearMemoryCache() {
        ImageCache.default.clearMemoryCache()
    }
    
    func clearDiskCache() {
        ImageCache.default.clearDiskCache()
    }
    
    func clearAllCaches() {
        ImageCache.default.clearCache()
    }
    
    func getCacheUsage() -> (memory: Int, disk: Int) {
        // Memory cache: Kingfisher doesn't expose actual memory usage
        // We return 0 since memory cache is transient and not measurable
        let memoryUsed = 0
        
        // For disk cache, we return the last calculated value
        let diskUsed = lastCalculatedDiskSize
        
        return (memory: memoryUsed, disk: diskUsed)
    }
    
    private var lastCalculatedDiskSize: Int = 0
    
    func getCacheUsageAsync(completion: @escaping (Int, Int) -> Void) {
        // Memory cache is transient and not measurable
        let memoryUsed = 0
        
        ImageCache.default.calculateDiskStorageSize { [weak self] result in
            guard let self = self else { return }
            
            let diskUsed = switch result {
            case .success(let size): Int(size)
            case .failure(_): 0
            }
            
            // Store the calculated disk size for sync access
            self.lastCalculatedDiskSize = diskUsed
            
            // Log cache usage but don't force cleanup - let Kingfisher handle it
            let limitBytes = self.settings.diskCacheLimitBytes
            if diskUsed > limitBytes {
                print("ℹ️ Cache usage: \(diskUsed) bytes (limit: \(limitBytes) bytes)")
            }
            
            DispatchQueue.main.async {
                completion(memoryUsed, diskUsed)
            }
        }
    }
    
    func preloadImages(urls: [URL]) {
        guard settings.preloadEnabled else { return }
        
        let prefetcher = ImagePrefetcher(urls: urls)
        prefetcher.start()
    }
    
    // MARK: - Cache Management
    
    private func checkAndCleanCacheIfNeeded() {
        // Only clean expired cache - no aggressive cleanup
        ImageCache.default.cleanExpiredDiskCache()
    }
    
    private func cleanCacheToLimit() {
        // Only clean expired cache - don't be aggressive
        ImageCache.default.cleanExpiredDiskCache()
        
        // Don't clear entire cache - let Kingfisher handle it automatically
        // The size limit in configureKingfisher() will handle automatic cleanup
    }
    
    func forceCacheCleanup() {
        cleanCacheToLimit()
    }
}