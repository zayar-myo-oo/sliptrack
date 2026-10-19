import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private var started = false
  private let label = UILabel()
  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = .systemBackground
    label.text = "Import bank receipt to SlipTrack?\n\nAn encrypted temporary copy stays on this device until you confirm or delete the imported receipt. Open SlipTrack after sharing to finish OCR and review."
    label.numberOfLines = 0; label.textAlignment = .center
    let button = UIButton(type: .system); button.setTitle("Import receipt", for: .normal); button.addTarget(self, action: #selector(importReceipt), for: .touchUpInside)
    let cancel = UIButton(type: .system); cancel.setTitle("Cancel", for: .normal); cancel.addTarget(self, action: #selector(close), for: .touchUpInside)
    let stack = UIStackView(arrangedSubviews: [label, button, cancel]); stack.axis = .vertical; stack.spacing = 24; stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28), stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28), stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
  }
  @objc private func close() { extensionContext?.completeRequest(returningItems: nil) }
  @objc private func importReceipt() {
    guard !started else { return }; started = true
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
      .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }.prefix(5)
    guard !providers.isEmpty else { label.text = "No receipt image was shared."; started = false; return }
    let group = DispatchGroup(); let lock = NSLock(); var failed = false
    for provider in providers {
      group.enter()
      provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
        do {
          guard let data = data else { throw ShareInbox.InboxError.unavailable }
          try ShareInbox.store(data)
        } catch { lock.lock(); failed = true; lock.unlock() }
        group.leave()
      }
    }
    group.notify(queue: .main) { [weak self] in
      if failed { self?.label.text = "Some images could not be imported. Unlock your device and check SlipTrack's App Group signing configuration."; self?.started = false }
      else { self?.extensionContext?.completeRequest(returningItems: nil) }
    }
  }
}
