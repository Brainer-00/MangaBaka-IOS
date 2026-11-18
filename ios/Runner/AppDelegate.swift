import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let names: Set<String> = [
      "IconEmerald", "IconAmber", "IconOrange", "IconRose",
      "IconPink", "IconViolet", "IconBlue", "IconCyan",
      "IconTeal", "IconLime", "IconTwilightLavender", "IconHorizonBlue"
    ]
    let channel = FlutterMethodChannel(
      name: "eirenyu/home_icon",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      DispatchQueue.main.async {
        let application = UIApplication.shared
        switch call.method {
        case "supported":
          result(application.supportsAlternateIcons)
        case "current":
          result(application.alternateIconName)
        case "set":
          guard application.supportsAlternateIcons else {
            result(FlutterError(code: "unsupported", message: "Alternate icons unavailable", details: nil))
            return
          }
          let name = call.arguments as? String
          guard call.arguments == nil || call.arguments is NSNull || (name != nil && names.contains(name!)) else {
            result(FlutterError(code: "invalid_icon", message: "Unknown icon", details: nil))
            return
          }
          application.setAlternateIconName(name) { error in
            DispatchQueue.main.async {
              if let error = error {
                result(FlutterError(code: "icon_change_failed", message: error.localizedDescription, details: nil))
              } else {
                result(nil)
              }
            }
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
