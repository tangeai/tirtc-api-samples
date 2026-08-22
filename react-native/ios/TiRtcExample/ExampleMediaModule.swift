import Foundation
import Photos
import React

@objc(TiRtcExampleMedia)
final class ExampleMediaModule: NSObject {
  @objc
  static func requiresMainQueueSetup() -> Bool { false }

  @objc(requestGalleryWritePermission:rejecter:)
  func requestGalleryWritePermission(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: RCTPromiseRejectBlock
  ) {
    let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    if status == .authorized || status == .limited {
      resolve(true)
      return
    }
    guard status == .notDetermined else {
      resolve(false)
      return
    }
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { updatedStatus in
      resolve(updatedStatus == .authorized || updatedStatus == .limited)
    }
  }

  @objc(cacheFilePath:resolver:rejecter:)
  func cacheFilePath(
    _ extensionName: String,
    resolver resolve: RCTPromiseResolveBlock,
    rejecter reject: RCTPromiseRejectBlock
  ) {
    let safeExtension = extensionName.lowercased().filter { $0.isLetter || $0.isNumber }
    let filename = "tirtc-\(Int(Date().timeIntervalSince1970 * 1000)).\(safeExtension.isEmpty ? "bin" : safeExtension)"
    resolve(FileManager.default.temporaryDirectory.appendingPathComponent(filename).path)
  }

  @objc(saveImageToGallery:resolver:rejecter:)
  func saveImageToGallery(
    _ sourcePath: String,
    resolver resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    guard FileManager.default.fileExists(atPath: sourcePath) else {
      reject("snapshot_missing", "Snapshot file does not exist", nil)
      return
    }
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        reject("gallery_permission_denied", "Photo library add permission was not granted", nil)
        return
      }
      var placeholder: PHObjectPlaceholder?
      PHPhotoLibrary.shared().performChanges {
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: .photo, fileURL: URL(fileURLWithPath: sourcePath), options: nil)
        placeholder = request.placeholderForCreatedAsset
      } completionHandler: { success, error in
        if success {
          resolve(placeholder?.localIdentifier ?? "")
        } else {
          reject("gallery_write_failed", "Unable to save snapshot to Photos", error)
        }
      }
    }
  }
}
