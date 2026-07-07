import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Open at a size that suits the treemap; keep a sane minimum.
    let windowFrame = NSRect(x: 0, y: 0, width: 1280, height: 820)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.center()
    self.minSize = NSSize(width: 960, height: 620)
    self.title = "Clean Mind"

    // Seamless title bar: the Flutter content extends under a transparent,
    // text-free title bar for a modern native look. The traffic lights float
    // over the content; the results header insets itself to clear them.
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
