import SwiftUI

struct ComposeView: View {
  @EnvironmentObject var ble: BLECoordinator
  @State private var teaserInput: String = ""
  @State private var bodyInput: String = ""

  var body: some View {
    NavigationView {
      Form {
        Section("短句（8文字固定）") {
          TextField("例：英国片思い", text: $teaserInput)
            .onChange(of: teaserInput) { _, v in
              // UIは8文字固定（表示上）
              if v.count > 8 { teaserInput = String(v.prefix(8)) }
            }

          Text("\(teaserInput.count)/8")
            .font(.caption)
            .foregroundStyle(.secondary)

          Button("短句を適用") {
            ble.setMyTeaser(teaserInput)
          }
          .disabled(teaserInput.isEmpty)
        }

        Section("本文（任意）") {
          TextEditor(text: $bodyInput)
            .frame(minHeight: 140)

          Button("本文を適用") {
            ble.setMyBody(bodyInput)
          }
        }

        Section {
          Button("会場モード ON（送受信開始）") {
            ble.isVenueModeOn = true
            ble.startVenueMode()
          }
          Button("会場モード OFF（停止）") {
            ble.isVenueModeOn = false
            ble.stopVenueMode()
          }
        }
      }
      .onAppear {
        teaserInput = ble.myTeaser
        bodyInput = ble.myBody
      }
      .navigationTitle("投稿")
    }
  }
}
