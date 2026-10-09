import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Same project key as Android [com.google.android.geo.API_KEY]; enable Maps SDK for iOS in Cloud Console.
    GMSServices.provideAPIKey("AIzaSyBuYILpEr9o7m3KUblvE90KrPouvK4mHm0")
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
