import SwiftUI

struct StreamView: View {
  @EnvironmentObject var ble: BLECoordinator

  var body: some View {
    NavigationView {
      List {
        Section {
          Toggle("会場モード", isOn: $ble.isVenueModeOn)
            .onChange(of: ble.isVenueModeOn) { _, on in
              on ? ble.startVenueMode() : ble.stopVenueMode()
            }

          HStack {
            Text("送信短句")
            Spacer()
            Text(ble.myTeaser.isEmpty ? "未設定" : ble.myTeaser)
              .foregroundStyle(.secondary)
          }
        }

        Section("すれちがい") {
          ForEach(ble.encounters) { e in
            Button {
              ble.requestBody(for: e)
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 4) {
                  Text(e.teaser).font(.headline)
                  Text("RSSI \(e.rssi)  ×\(e.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text("全文")
                  .font(.caption)
                  .padding(.horizontal, 10)
                  .padding(.vertical, 6)
                  .background(.thinMaterial)
                  .cornerRadius(8)
              }
            }
          }
        }

        Section("受信") {
          VStack(alignment: .leading, spacing: 8) {
            Text("状態: \(ble.activeStatusText)")
              .font(.caption)
              .foregroundStyle(.secondary)

            if !ble.receivedPreview.isEmpty {
              Text(ble.receivedPreview)
                .font(.body)
            }

            if let body = ble.receivedBody {
              Divider()
              Text(body)
                .font(.body)
            }
          }
          .padding(.vertical, 6)
        }
      }
      .navigationTitle("びっとら（テスト）")
    }
  }
}
