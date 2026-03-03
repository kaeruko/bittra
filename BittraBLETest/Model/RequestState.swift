import Foundation

enum RequestStatus: Equatable {
  case idle
  case connecting
  case discovering
  case subscribing
  case requesting
  case receivingPreview
  case completed
  case timeout
  case failed(String)
}
