import SwiftUI

struct LogsView: View {
  @EnvironmentObject var ble: BLECoordinator

  var body: some View {
    NavigationView {
      List {
        ForEach(ble.logs) { l in
          VStack(alignment: .leading, spacing: 3) {
            Text("[\(l.tag)] \(l.msg)")
              .font(.caption)
            Text(l.ts.formatted(date: .omitted, time: .standard))
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle("ログ")
      .toolbar {
        Button("消去") { ble.clearLogs() }
      }
    }
  }
}
