import UIKit
import WebKit
import AVFoundation

final class GameViewController: UIViewController, WKNavigationDelegate {
    private var webView: WKWebView!
    private let key = "nightfall.serverURL"

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // الصوت يشتغل حتى لو زر الصامت مفعّل
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)

        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: view.bounds, configuration: cfg)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        view.addSubview(webView)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        if webView.url == nil { loadGame() }
    }

    // هز الجوال لتغيير السيرفر
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { askForServer(message: "ادخل رابط السيرفر الجديد") }
    }

    private func loadGame() {
        if let s = UserDefaults.standard.string(forKey: key), let url = URL(string: s) {
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60))
        } else {
            askForServer(message: "ادخل رابط سيرفر اللعبة (مثل https://nightfall-xxxx.onrender.com أو عنوان جهازك)")
        }
    }

    private func askForServer(message: String) {
        let a = UIAlertController(title: "سيرفر Nightfall", message: message, preferredStyle: .alert)
        a.addTextField { tf in
            tf.placeholder = "https://..."
            tf.keyboardType = .URL
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
            tf.text = UserDefaults.standard.string(forKey: self.key)
        }
        a.addAction(UIAlertAction(title: "حفظ وتشغيل", style: .default) { _ in
            var s = (a.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { self.askForServer(message: "لازم تكتب الرابط"); return }
            if !s.lowercased().hasPrefix("http") { s = "https://" + s }
            UserDefaults.standard.set(s, forKey: self.key)
            self.loadGame()
        })
        if UserDefaults.standard.string(forKey: key) != nil {
            a.addAction(UIAlertAction(title: "إلغاء", style: .cancel))
        }
        present(a, animated: true)
    }

    // فشل الاتصال (مثلاً السيرفر المجاني كان نايم)
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let a = UIAlertController(title: "تعذر الاتصال بالسيرفر",
                                  message: "تأكد من النت وأن السيرفر شغال. السيرفر المجاني يحتاج نص دقيقة يصحى.",
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "إعادة المحاولة", style: .default) { _ in self.loadGame() })
        a.addAction(UIAlertAction(title: "تغيير السيرفر", style: .default) { _ in self.askForServer(message: "ادخل رابط السيرفر") })
        if presentedViewController == nil { present(a, animated: true) }
    }
}
