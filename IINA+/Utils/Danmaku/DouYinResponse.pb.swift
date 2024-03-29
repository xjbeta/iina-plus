// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: 1.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

import Foundation
import SwiftProtobuf

// If the compiler emits an error on this type, it is because this file
// was generated by a version of the `protoc` Swift plug-in that is
// incompatible with the version of SwiftProtobuf to which you are linking.
// Please ensure that you are building against the same version of the API
// that was used to generate this file.
fileprivate struct _GeneratedWithProtocGenSwiftVersion: SwiftProtobuf.ProtobufAPIVersionCheck {
  struct _2: SwiftProtobuf.ProtobufAPIVersion_2 {}
  typealias Version = _2
}

struct DouYinResponse {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var wssPushRoomID: Int64 = 0

  var wssPushDid: Int64 = 0

  var wssPushLogID: Int64 = 0

  var wssFetchMs: Int64 = 0

  var wssPushMs: Int64 = 0

  var wssMsgType: String = String()

  var pb: String = String()

  var data: Data = Data()

  var serverTime: Int64 = 0

  var compressType: String = String()

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

#if swift(>=5.5) && canImport(_Concurrency)
extension DouYinResponse: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

extension DouYinResponse: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "DouYinResponse"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "wss_push_room_id"),
    2: .standard(proto: "wss_push_did"),
    3: .standard(proto: "wss_push_log_id"),
    4: .standard(proto: "wss_fetch_ms"),
    5: .standard(proto: "wss_push_ms"),
    6: .standard(proto: "wss_msg_type"),
    7: .same(proto: "pb"),
    8: .same(proto: "data"),
    9: .standard(proto: "server_time"),
    10: .standard(proto: "compress_type"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularInt64Field(value: &self.wssPushRoomID) }()
      case 2: try { try decoder.decodeSingularInt64Field(value: &self.wssPushDid) }()
      case 3: try { try decoder.decodeSingularInt64Field(value: &self.wssPushLogID) }()
      case 4: try { try decoder.decodeSingularInt64Field(value: &self.wssFetchMs) }()
      case 5: try { try decoder.decodeSingularInt64Field(value: &self.wssPushMs) }()
      case 6: try { try decoder.decodeSingularStringField(value: &self.wssMsgType) }()
      case 7: try { try decoder.decodeSingularStringField(value: &self.pb) }()
      case 8: try { try decoder.decodeSingularBytesField(value: &self.data) }()
      case 9: try { try decoder.decodeSingularInt64Field(value: &self.serverTime) }()
      case 10: try { try decoder.decodeSingularStringField(value: &self.compressType) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.wssPushRoomID != 0 {
      try visitor.visitSingularInt64Field(value: self.wssPushRoomID, fieldNumber: 1)
    }
    if self.wssPushDid != 0 {
      try visitor.visitSingularInt64Field(value: self.wssPushDid, fieldNumber: 2)
    }
    if self.wssPushLogID != 0 {
      try visitor.visitSingularInt64Field(value: self.wssPushLogID, fieldNumber: 3)
    }
    if self.wssFetchMs != 0 {
      try visitor.visitSingularInt64Field(value: self.wssFetchMs, fieldNumber: 4)
    }
    if self.wssPushMs != 0 {
      try visitor.visitSingularInt64Field(value: self.wssPushMs, fieldNumber: 5)
    }
    if !self.wssMsgType.isEmpty {
      try visitor.visitSingularStringField(value: self.wssMsgType, fieldNumber: 6)
    }
    if !self.pb.isEmpty {
      try visitor.visitSingularStringField(value: self.pb, fieldNumber: 7)
    }
    if !self.data.isEmpty {
      try visitor.visitSingularBytesField(value: self.data, fieldNumber: 8)
    }
    if self.serverTime != 0 {
      try visitor.visitSingularInt64Field(value: self.serverTime, fieldNumber: 9)
    }
    if !self.compressType.isEmpty {
      try visitor.visitSingularStringField(value: self.compressType, fieldNumber: 10)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: DouYinResponse, rhs: DouYinResponse) -> Bool {
    if lhs.wssPushRoomID != rhs.wssPushRoomID {return false}
    if lhs.wssPushDid != rhs.wssPushDid {return false}
    if lhs.wssPushLogID != rhs.wssPushLogID {return false}
    if lhs.wssFetchMs != rhs.wssFetchMs {return false}
    if lhs.wssPushMs != rhs.wssPushMs {return false}
    if lhs.wssMsgType != rhs.wssMsgType {return false}
    if lhs.pb != rhs.pb {return false}
    if lhs.data != rhs.data {return false}
    if lhs.serverTime != rhs.serverTime {return false}
    if lhs.compressType != rhs.compressType {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
