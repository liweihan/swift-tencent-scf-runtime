//===------------------------------------------------------------------------------------===//
//
// This source file is part of the SwiftTencentSCFRuntime open source project
//
// Copyright (c) 2020 stevapple and the SwiftTencentSCFRuntime project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftTencentSCFRuntime project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===------------------------------------------------------------------------------------===//

// https://cloud.tencent.com/document/product/583/17530

public enum CKafka {
    public struct Event: Codable, Equatable {
        public typealias Record = Message
        public let records: [Record]

        public enum CodingKeys: String, CodingKey {
            case records = "Records"
        }
    }

    public struct Message: Codable, Equatable {
        public let topic: String
        public let partition: UInt64
        public let offset: UInt64
        public let key: String
        public let body: String

        enum WrappingCodingKeys: String, CodingKey {
            case ckafka = "Ckafka"
        }

        enum CodingKeys: String, CodingKey {
            case topic
            case partition
            case offset
            case key = "msgKey"
            case body = "msgBody"
        }

        public init(from decoder: Decoder) throws {
            let wrapperContainer = try decoder.container(keyedBy: WrappingCodingKeys.self)
            let container = try wrapperContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .ckafka)
            self.topic = try container.decode(String.self, forKey: .topic)
            self.partition = try container.decode(UInt64.self, forKey: .partition)
            self.offset = try container.decode(UInt64.self, forKey: .offset)
            self.key = try container.decode(String.self, forKey: .key)
            self.body = try container.decode(String.self, forKey: .body)
        }

        public func encode(to encoder: Encoder) throws {
            var wrapperContainer = encoder.container(keyedBy: WrappingCodingKeys.self)
            var container = wrapperContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .ckafka)
            try container.encode(self.topic, forKey: .topic)
            try container.encode(self.partition, forKey: .partition)
            try container.encode(self.offset, forKey: .offset)
            try container.encode(self.key, forKey: .key)
            try container.encode(self.body, forKey: .body)
        }
    }
}
