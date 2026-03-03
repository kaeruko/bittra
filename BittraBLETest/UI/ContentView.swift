import SwiftUI

struct ContentView: View {
  var body: some View {
    TabView {
      StreamView()
        .tabItem { Label("すれちがい", systemImage: "dot.radiowaves.left.and.right") }

      ComposeView()
        .tabItem { Label("投稿", systemImage: "square.and.pencil") }

      LogsView()
        .tabItem { Label("ログ", systemImage: "doc.plaintext") }
    }
  }
}
