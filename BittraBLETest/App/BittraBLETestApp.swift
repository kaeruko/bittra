import SwiftUI

@main
struct BittraBLETestApp: App {
  @StateObject private var ble = BLECoordinator()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(ble)
    }
  }
}
