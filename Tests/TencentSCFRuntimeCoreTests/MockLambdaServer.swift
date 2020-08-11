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
//
// This source file was part of the SwiftAWSLambdaRuntime open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftAWSLambdaRuntime project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See http://github.com/swift-server/swift-aws-lambda-runtime/blob/master/CONTRIBUTORS.txt
// for the list of SwiftAWSLambdaRuntime project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===------------------------------------------------------------------------------------===//

import Foundation // for JSON
import Logging
import NIO
import NIOHTTP1
@testable import TencentSCFRuntimeCore

internal final class MockLambdaServer {
    private let logger = Logger(label: "MockLambdaServer")
    private let behavior: LambdaServerBehavior
    private let host: String
    private let port: Int
    private let keepAlive: Bool
    private let group: EventLoopGroup

    private var channel: Channel?
    private var shutdown = false

    public init(behavior: LambdaServerBehavior, host: String = "127.0.0.1", port: Int = 9001, keepAlive: Bool = true) {
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        self.behavior = behavior
        self.host = host
        self.port = port
        self.keepAlive = keepAlive
    }

    deinit {
        assert(shutdown)
    }

    func start() -> EventLoopFuture<MockLambdaServer> {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap { _ in
                    channel.pipeline.addHandler(HTTPHandler(logger: self.logger, keepAlive: self.keepAlive, behavior: self.behavior))
                }
            }
        return bootstrap.bind(host: self.host, port: self.port).flatMap { channel in
            self.channel = channel
            guard let localAddress = channel.localAddress else {
                return channel.eventLoop.makeFailedFuture(ServerError.cantBind)
            }
            self.logger.info("\(self) started and listening on \(localAddress)")
            return channel.eventLoop.makeSucceededFuture(self)
        }
    }

    func stop() -> EventLoopFuture<Void> {
        self.logger.info("stopping \(self)")
        guard let channel = self.channel else {
            return self.group.next().makeFailedFuture(ServerError.notReady)
        }
        return channel.close().always { _ in
            self.shutdown = true
            self.logger.info("\(self) stopped")
        }
    }
}

internal final class HTTPHandler: ChannelInboundHandler {
    public typealias InboundIn = HTTPServerRequestPart
    public typealias OutboundOut = HTTPServerResponsePart

    private let logger: Logger
    private let keepAlive: Bool
    private let behavior: LambdaServerBehavior

    private var pending = CircularBuffer<(head: HTTPRequestHead, body: ByteBuffer?)>()

    public init(logger: Logger, keepAlive: Bool, behavior: LambdaServerBehavior) {
        self.logger = logger
        self.keepAlive = keepAlive
        self.behavior = behavior
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let requestPart = unwrapInboundIn(data)

        switch requestPart {
        case .head(let head):
            self.pending.append((head: head, body: nil))
        case .body(var buffer):
            var request = self.pending.removeFirst()
            if request.body == nil {
                request.body = buffer
            } else {
                request.body!.writeBuffer(&buffer)
            }
            self.pending.prepend(request)
        case .end:
            let request = self.pending.removeFirst()
            self.processRequest(context: context, request: request)
        }
    }

    func processRequest(context: ChannelHandlerContext, request: (head: HTTPRequestHead, body: ByteBuffer?)) {
        self.logger.info("\(self) processing \(request.head.uri)")

        let requestBody = request.body.flatMap { (buffer: ByteBuffer) -> String? in
            var buffer = buffer
            return buffer.readString(length: buffer.readableBytes)
        }

        var responseStatus: HTTPResponseStatus
        var responseBody: String?
        var responseHeaders: [(String, String)]?

        // Handle post-init-error first to avoid matching the less specific post-error suffix.
        if request.head.uri == Consts.postInitErrorURL {
            guard let json = requestBody, let error = ErrorResponse.fromJson(json) else {
                return self.writeResponse(context: context, status: .badRequest)
            }
            switch self.behavior.process(initError: error) {
            case .success:
                responseStatus = .ok
            case .failure(let error):
                responseStatus = .init(statusCode: error.rawValue)
            }
        } else if request.head.uri == Consts.getNextInvocationURL {
            switch self.behavior.getInvocation() {
            case .success(let (requestId, result)):
                if requestId == "timeout" {
                    usleep((UInt32(result) ?? 0) * 1000)
                } else if requestId == "disconnect" {
                    return context.close(promise: nil)
                }
                responseStatus = .ok
                responseBody = result
                responseHeaders = [
                    (SCFHeaders.requestID, requestId),
                    (SCFHeaders.timeLimit, "3000"),
                    (SCFHeaders.memoryLimit, "128"),
                ]
            case .failure(let error):
                responseStatus = .init(statusCode: error.rawValue)
            }
        } else if request.head.uri == Consts.postResponseURL {
            switch self.behavior.process(response: requestBody) {
            case .success:
                responseStatus = .ok
            case .failure(let error):
                responseStatus = .init(statusCode: error.rawValue)
            }
        } else if request.head.uri == Consts.postErrorURL {
            guard let json = requestBody,
                let error = ErrorResponse.fromJson(json)
            else {
                return self.writeResponse(context: context, status: .badRequest)
            }
            switch self.behavior.process(error: error) {
            case .success():
                responseStatus = .ok
            case .failure(let error):
                responseStatus = .init(statusCode: error.rawValue)
            }
        } else {
            responseStatus = .notFound
        }
        self.writeResponse(context: context, status: responseStatus, headers: responseHeaders, body: responseBody)
    }

    func writeResponse(context: ChannelHandlerContext, status: HTTPResponseStatus, headers: [(String, String)]? = nil, body: String? = nil) {
        var headers = HTTPHeaders(headers ?? [])
        headers.add(name: "Content-Length", value: "\(body?.utf8.count ?? 0)")
        if !self.keepAlive {
            headers.add(name: "Connection", value: "close")
        }
        let head = HTTPResponseHead(version: HTTPVersion(major: 1, minor: 1), status: status, headers: headers)

        context.write(wrapOutboundOut(.head(head))).whenFailure { error in
            self.logger.error("\(self) write error \(error)")
        }

        if let b = body {
            var buffer = context.channel.allocator.buffer(capacity: b.utf8.count)
            buffer.writeString(b)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer)))).whenFailure { error in
                self.logger.error("\(self) write error \(error)")
            }
        }

        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { result in
            if case .failure(let error) = result {
                self.logger.error("\(self) write error \(error)")
            }
            if !self.keepAlive {
                context.close().whenFailure { error in
                    self.logger.error("\(self) close error \(error)")
                }
            }
        }
    }
}

internal protocol LambdaServerBehavior {
    func getInvocation() -> GetInvocationResult
    func process(response: String?) -> Result<Void, ProcessResponseError>
    func process(error: ErrorResponse) -> Result<Void, ProcessErrorError>
    func process(initError: ErrorResponse) -> Result<Void, ProcessErrorError>
}

internal typealias GetInvocationResult = Result<(String, String), GetWorkError>

internal enum GetWorkError: Int, Error {
    case badRequest = 400
    case tooManyRequests = 429
    case internalServerError = 500
}

internal enum ProcessResponseError: Int, Error {
    case badRequest = 400
    case payloadTooLarge = 413
    case tooManyRequests = 429
    case internalServerError = 500
}

internal enum ProcessErrorError: Int, Error {
    case invalidErrorShape = 299
    case badRequest = 400
    case internalServerError = 500
}

internal enum ServerError: Error {
    case notReady
    case cantBind
}

private extension ErrorResponse {
    static func fromJson(_ s: String) -> ErrorResponse? {
        let decoder = JSONDecoder()
        do {
            if let data = s.data(using: .utf8) {
                return try decoder.decode(ErrorResponse.self, from: data)
            } else {
                return nil
            }
        } catch {
            return nil
        }
    }
}
