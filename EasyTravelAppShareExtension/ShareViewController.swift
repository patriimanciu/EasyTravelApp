//
//  ShareViewController.swift
//  EasyTravelAppShareExtension
//
//  We do NOT load from the item provider (TikTok/sandbox causes crash).
//  We only use the share sheet's text field (contentText), which often
//  contains the link when sharing from TikTok.
//

import Social
import UIKit

final class ShareViewController: SLComposeServiceViewController {

    override func isContentValid() -> Bool {
        return true
    }

    override func didSelectPost() {
        // Use only the text field — never touch extensionContext.inputItems / NSItemProvider.
        // TikTok (and others) often put the video link in this field; otherwise user can paste.
        let text = contentText ?? ""
        let urlString = extractURL(from: text) ?? text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        openApp(withSharedURL: urlString.isEmpty ? nil : urlString)
    }

    override func configurationItems() -> [Any]! {
        return []
    }

    private func extractURL(from text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        return matches.first?.url?.absoluteString
    }

    private func openApp(withSharedURL sharedURL: String?) {
        var components = URLComponents()
        components.scheme = "easytravel"
        components.host = "import"
        if let sharedURL, !sharedURL.isEmpty {
            components.queryItems = [URLQueryItem(name: "url", value: sharedURL)]
        }

        guard let url = components.url else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        extensionContext?.open(url, completionHandler: { [weak self] success in
            guard let self else { return }
            if !success {
                self.openURLViaResponderChain(url)
            }
            self.extensionContext?.completeRequest(returningItems: nil)
        })
    }

    private func openURLViaResponderChain(_ url: URL) {
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = r.next
        }
    }
}
