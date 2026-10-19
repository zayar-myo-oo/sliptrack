import Flutter
import UIKit
import Photos
import PhotosUI
import Vision
import CryptoKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var media: SlipMediaBridge?
  override func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SlipTrackMedia") {
      media = SlipMediaBridge(messenger: registrar.messenger())
    }
  }
}

// Kept in the app source compilation unit so no generated Xcode references are required.
final class SlipMediaBridge: NSObject, FlutterStreamHandler, PHPhotoLibraryChangeObserver, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
  private var channel: FlutterMethodChannel!
  private var sink: FlutterEventSink?
  private var pickerResult: FlutterResult?
  private var backupResult: FlutterResult?
  private var exportURL: URL?
  private var observing = false
  private var transient: [String: Data] = [:]
  private let worker = DispatchQueue(label: "app.sliptrack.ocr", qos: .userInitiated)
  private var presenter: UIViewController? {
    let root = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }.first(where: { $0.isKeyWindow })?.rootViewController
    var current = root
    while let next = current?.presentedViewController { current = next }
    return current
  }
  init(messenger: FlutterBinaryMessenger) {
    super.init()
    channel = FlutterMethodChannel(name: "app.sliptrack/media", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
    FlutterEventChannel(name: "app.sliptrack/media_changes", binaryMessenger: messenger).setStreamHandler(self)
    updateObserver()
  }
  private func permission() -> String {
    switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
    case .authorized: return "full"
    case .limited: return "limited"
    case .notDetermined: return "notDetermined"
    default: return "denied"
    }
  }
  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "backupExport", "backupImport":
      guard backupResult == nil, let presenter = presenter else { result(FlutterError(code: "busy", message: "File picker unavailable", details: nil)); return }
      let picker: UIDocumentPickerViewController
      if call.method == "backupExport" {
        guard let text = args["data"] as? String else { result(FlutterError(code: "backup", message: "Missing encrypted backup", details: nil)); return }
        do {
          let url = FileManager.default.temporaryDirectory.appendingPathComponent("sliptrack-backup-" + UUID().uuidString + ".json")
          try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtection])
          exportURL = url; picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        } catch { result(FlutterError(code: "backup", message: "Cannot stage encrypted export", details: nil)); return }
      } else { picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true) }
      backupResult = result; picker.delegate = self; presenter.present(picker, animated: true)
    case "permission":
      if args["request"] as? Bool == true {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] _ in
          DispatchQueue.main.async { result(self?.permission() ?? "denied"); self?.updateObserver() }
        }
      } else { result(permission()) }
    case "automatic":
      UserDefaults.standard.set(args["enabled"] as? Bool == true, forKey: "sliptrack.automatic")
      updateObserver(); result(nil)
    case "incoming": result((try? ShareInbox.sources()) ?? [])
    case "cleanup":
      if args["all"] as? Bool == true { transient.removeAll(); try? ShareInbox.clear() }
      else if let id = args["id"] as? String {
        transient.removeValue(forKey: id)
        if id.hasPrefix("shared:") { try? ShareInbox.remove(id) }
      }
      result(nil)
    case "limitedPicker":
      if let presenter = presenter { PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter) }
      result(nil)
    case "pick":
      guard pickerResult == nil, let presenter = presenter else { result(FlutterError(code: "busy", message: "Picker unavailable", details: nil)); return }
      var config = PHPickerConfiguration(photoLibrary: .shared())
      config.filter = .images; config.selectionLimit = 10; config.preferredAssetRepresentationMode = .current
      let picker = PHPickerViewController(configuration: config); picker.delegate = self
      pickerResult = result; presenter.present(picker, animated: true)
    case "assets":
      guard permission() == "full" || permission() == "limited" else { result(FlutterError(code: "permission", message: "Photo access denied", details: nil)); return }
      let after = (args["afterMs"] as? NSNumber)?.doubleValue ?? 0
      let since = (args["sinceMs"] as? NSNumber)?.doubleValue ?? 0
      let offset = (args["offset"] as? NSNumber)?.intValue ?? 0
      worker.async {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d AND creationDate >= %@ AND (modificationDate >= %@ OR creationDate >= %@)", PHAssetMediaType.image.rawValue,
          Date(timeIntervalSince1970: since / 1000) as NSDate, Date(timeIntervalSince1970: after / 1000) as NSDate, Date(timeIntervalSince1970: after / 1000) as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(with: options)
        let ids = offset < assets.count ? (offset..<min(offset + 100, assets.count)).map { assets.object(at: $0).localIdentifier } : []
        DispatchQueue.main.async { result(ids) }
      }
    case "ocr", "thumbnail":
      guard let id = args["id"] as? String else { result(FlutterError(code: "image", message: "Missing image", details: nil)); return }
      let inMemory = transient[id]
      worker.async { [weak self] in
        guard let self = self, let data = inMemory ?? self.imageData(id) else {
          DispatchQueue.main.async { result(FlutterError(code: "image", message: "Image unavailable or permission revoked. Reimport to retry.", details: nil)) }; return
        }
        if call.method == "thumbnail" {
          guard let image = UIImage(data: data) else { DispatchQueue.main.async { result(nil) }; return }
          let ratio = min(1, 1600 / max(image.size.width, image.size.height))
          let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
          let format = UIGraphicsImageRendererFormat(); format.scale = 1
          let preview = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: 0.85)
          DispatchQueue.main.async { result(preview.map { FlutterStandardTypedData(bytes: $0) }) }; return
        }
        do {
          let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
          let languages = try request.supportedRecognitionLanguages()
          let preferred = ["en-US", "th-TH", "my-MM"].filter { languages.contains($0) }
          if !preferred.isEmpty { request.recognitionLanguages = preferred }
          try VNImageRequestHandler(data: data, options: [:]).perform([request])
          let observations = request.results ?? []
          // Vision bounding boxes use normalized coordinates and a bottom-left origin.
          let blocks: [[String: Any]] = observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first else { return nil }
            let r = observation.boundingBox
            return ["text": text.string, "confidence": text.confidence, "box": [r.minX, 1 - r.maxY, r.width, r.height]]
          }
          let confidence: Any = observations.isEmpty ? NSNull() : observations.reduce(Float(0)) { $0 + ($1.topCandidates(1).first?.confidence ?? 0) } / Float(observations.count)
          let payload: [String: Any] = ["text": blocks.compactMap { $0["text"] as? String }.joined(separator: "\n"),
            "hash": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), "languages": languages,
            "confidence": confidence, "blocks": blocks]
          DispatchQueue.main.async { result(payload) }
        } catch { DispatchQueue.main.async { result(FlutterError(code: "ocr", message: "On-device recognition failed", details: nil)) } }
      }
    default: result(FlutterMethodNotImplemented)
    }
  }
  private func imageData(_ id: String) -> Data? {
    if id.hasPrefix("shared:") { return try? ShareInbox.read(id) }
    let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
    guard let asset = assets.firstObject else { return nil }
    let options = PHImageRequestOptions(); options.isSynchronous = true; options.isNetworkAccessAllowed = false; options.version = .current
    var data: Data?
    PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { value, _, _, _ in data = value }
    return data
  }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    let callback = backupResult; backupResult = nil
    if let exported = exportURL { try? FileManager.default.removeItem(at: exported); exportURL = nil; callback?(true); return }
    guard let url = urls.first else { callback?(nil); return }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do { callback?(try String(contentsOf: url, encoding: .utf8)) }
    catch { callback?(FlutterError(code: "backup", message: "Cannot read selected backup", details: nil)) }
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    if let url = exportURL { try? FileManager.default.removeItem(at: url); exportURL = nil }
    let callback = backupResult; backupResult = nil; callback?(nil)
  }
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    let callback = pickerResult; pickerResult = nil
    let group = DispatchGroup()
    var selected = [Int: String]()
    for (index, item) in results.enumerated() {
      if let id = item.assetIdentifier, PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject != nil {
        selected[index] = id; continue
      }
      group.enter()
      item.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
        DispatchQueue.main.async {
          if let data = data {
            let id = "temporary:" + UUID().uuidString; self?.transient[id] = data; selected[index] = id
          }
          group.leave()
        }
      }
    }
    group.notify(queue: .main) { callback?(selected.keys.sorted().compactMap { selected[$0] }) }
  }
  private func updateObserver() {
    if observing { PHPhotoLibrary.shared().unregisterChangeObserver(self); observing = false }
    if UserDefaults.standard.bool(forKey: "sliptrack.automatic"), permission() == "full" || permission() == "limited" {
      PHPhotoLibrary.shared().register(self); observing = true
    }
  }
  func photoLibraryDidChange(_ changeInstance: PHChange) { DispatchQueue.main.async { [weak self] in self?.sink?(true) } }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? { sink = events; return nil }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }
  deinit { if observing { PHPhotoLibrary.shared().unregisterChangeObserver(self) } }
}
