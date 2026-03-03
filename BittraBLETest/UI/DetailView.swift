import SwiftUI

struct DetailView: View {
  @EnvironmentObject var ble: BLECoordinator
  
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("状態: \(ble.activeStatusText)")
        .font(.headline)
        .padding(.top)

      if !ble.receivedPreview.isEmpty {
        VStack(alignment: .leading) {
          Text("プレビュー:")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(ble.receivedPreview)
            .font(.body)
        }
      }

      if let bodyContent = ble.receivedBody {
        Divider()
        VStack(alignment: .leading) {
          Text("本文:")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(bodyContent)
            .font(.body)
        }
      }

      Spacer()
    }
    .padding()
    .navigationTitle("詳細")
  }
}
