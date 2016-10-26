//
//  Promise.swift
//  then
//
//  Created by Sacha Durand Saint Omer on 06/02/16.
//  Copyright © 2016 s4cha. All rights reserved.
//

import Foundation

public typealias EmptyPromise = Promise<Void>

public class Promise<T> {
    
    public typealias ResolveCallBack = (T) -> Void
    public typealias ProgressCallBack = (Float) -> Void
    public typealias RejectCallBack = (Error) -> Void
    public typealias PromiseCallBack = (_ resolve: @escaping ResolveCallBack,
        _ reject: @escaping RejectCallBack) -> Void
    public typealias PromiseProgressCallBack =
        (_ resolve: @escaping ResolveCallBack,
        _ reject: @escaping RejectCallBack,
        _ progress: @escaping ProgressCallBack) -> Void
    private typealias SuccessBlock = (T) -> Void
    private typealias FailBlock = (Error) -> Void
    private typealias ProgressBlock = (Float) -> Void
    
    private var successBlocks = [SuccessBlock]()
    private var failBlocks = [FailBlock]()
    private var progressBlocks = [ProgressBlock]()
    private var finallyBlock: () -> Void = { }
    private var promiseCallBack: PromiseCallBack!
    private var promiseProgressCallBack: PromiseProgressCallBack?
    private var promiseStarted = false
    private var state: PromiseState<T> = .pending
    private var progress: Float?
    var initialPromiseStart:(() -> Void)?
    var initialPromiseStarted = false
    
    private convenience init() {
        self.init { _, _, _ in }
    }
    
    public init(callback: @escaping (_ resolve: @escaping ResolveCallBack,
        _ reject: @escaping RejectCallBack) -> Void) {
        promiseCallBack = callback
    }
    
    public init(callback: @escaping (_ resolve: @escaping ResolveCallBack,
        _ reject: @escaping RejectCallBack, _ progress: @escaping ProgressCallBack) -> Void) {
        promiseProgressCallBack = callback
    }
    
    public func start() {
        promiseStarted = true
        if let p = promiseProgressCallBack {
            p(resolvePromise, rejectPromise, progressPromise)
        } else {
            promiseCallBack(resolvePromise, rejectPromise)
        }
    }
    
    //MARK: - then((T)-> X)
    
    @discardableResult public func then<X>(_ block: @escaping (T) -> X) -> Promise<X> {
        tryStartInitialPromise()
        startPromiseIfNeeded()
        return registerThen(block)
    }
    
    @discardableResult public func registerThen<X>(_ block: @escaping (T) -> X) -> Promise<X> {
        let p = Promise<X>()
        switch state {
        case let .fulfilled(value):
            let x: X = block(value)
            p.resolvePromise(x)
        case let .rejected(error):
            p.rejectPromise(error)
        case .pending:
            successBlocks.append({ t in
                p.resolvePromise(block(t))
            })
            failBlocks.append(p.rejectPromise)
            progressBlocks.append(p.progressPromise)
        }
        p.start()
        passAlongFirstPromiseStartFunctionAndStateTo(p)
        return p
    }
    
    //MARK: - then((T)->Promise<X>)
    
    @discardableResult public func then<X>(_ block: @escaping (T) -> Promise<X>) -> Promise<X> {
        tryStartInitialPromise()
        startPromiseIfNeeded()
        return registerThen(block)
    }
    
    @discardableResult  public func registerThen<X>(_ block: @escaping (T) -> Promise<X>)
        -> Promise<X> {
        let p = Promise<X>()
        switch state {
        case let .fulfilled(value):
            registerNextPromise(block, result: value,
                                      resolve: p.resolvePromise, reject: p.rejectPromise)
        case let .rejected(error):
            p.rejectPromise(error)
        case .pending:
            successBlocks.append({ t in
                self.registerNextPromise(block, result: t, resolve: p.resolvePromise,
                                         reject: p.rejectPromise)
            })
            failBlocks.append(p.rejectPromise)
        }
        p.start()
        passAlongFirstPromiseStartFunctionAndStateTo(p)
        return p
    }
    
    //MARK: - then(Promise<X>)
    
    
    @discardableResult public func then<X>(_ promise: Promise<X>) -> Promise<X> {
        return then { _ in promise }
    }
    
    @discardableResult public func registerThen<X>(_ promise: Promise<X>) -> Promise<X> {
        return registerThen { _ in promise }
    }
    
    //MARK: - Error
    
    @discardableResult public func onError(_ block: @escaping (Error) -> Void) -> Promise<Void> {
        tryStartInitialPromise()
        startPromiseIfNeeded()
        return registerOnError(block)
    }
    
    
    @discardableResult public func registerOnError(_ block:
        @escaping (Error) -> Void) -> Promise<Void> {
        let p = Promise<Void>()
        switch state {
        case .fulfilled:
            p.rejectPromise(NSError(domain: "", code: 123, userInfo: nil))
        // No error so do nothing.
        case let .rejected(error):
            // Already failed so call error block
            block(error)
            p.resolvePromise()
        case .pending:
            // if promise fails, resolve error promise
            failBlocks.append({ e in
                block(e)
                p.resolvePromise()
            })
            successBlocks.append({ t in
                p.resolvePromise()
            })
        }
        progressBlocks.append(p.progressPromise)
        p.start()
        passAlongFirstPromiseStartFunctionAndStateTo(p)
        return p
    }
    
    //MARK: - Finally
    
    
    @discardableResult public func finally<X>(block: @escaping () -> X) -> Promise<X> {
        tryStartInitialPromise()
        startPromiseIfNeeded()
        return registerFinally(block: block)
    }
    
    @discardableResult public func registerFinally<X>(block: @escaping () -> X) -> Promise<X> {
        let p = Promise<X>()
        switch state {
        case .fulfilled:
            p.resolvePromise(block())
        case .rejected:
            p.resolvePromise(block())
        case .pending:
            failBlocks.append({ e in
                p.resolvePromise(block())
            })
            successBlocks.append({ t in
                 p.resolvePromise(block())
            })
        }
        progressBlocks.append(p.progressPromise)
        p.start()
        passAlongFirstPromiseStartFunctionAndStateTo(p)
        return p
    }
    
    //MARK: - Progress
    
    @discardableResult public func progress(block: @escaping (Float) -> Void) -> Promise<Void> {
        tryStartInitialPromise()
        startPromiseIfNeeded()
        return registerProgress(block)
    }
    
    public func registerProgress(_ block: @escaping (Float) -> Void) -> Promise<Void> {
        let p = Promise<Void>()
        switch state {
        case .fulfilled:
            p.resolvePromise()
        case let .rejected(error):
            p.rejectPromise(error)
        case .pending:() //
        failBlocks.append(p.rejectPromise)
        successBlocks.append({ _ in
            p.resolvePromise()
        })
        }
        progressBlocks.append({ v in
            block(v)
            p.progressPromise(v)
        })
        p.start()
        passAlongFirstPromiseStartFunctionAndStateTo(p)
        return p
    }
    
    
    //MARK: - Helpers
    
    private func passAlongFirstPromiseStartFunctionAndStateTo<X>(_ promise: Promise<X>) {
        // Pass along First promise start block
        if let startBlock = self.initialPromiseStart {
            promise.initialPromiseStart = startBlock
        } else {
            promise.initialPromiseStart = self.start
        }
        // Pass along initil promise start state.
        promise.initialPromiseStarted = self.initialPromiseStarted
    }
    
    private func tryStartInitialPromise() {
        if !initialPromiseStarted {
            initialPromiseStart?()
            initialPromiseStarted = true
        }
    }
    
    private func startPromiseIfNeeded() {
        if !promiseStarted { start() }
    }
    
    private func registerNextPromise<X>(_ block: (T) -> Promise<X>,
                                     result: T,
                                     resolve: @escaping (X) -> Void,
                                     reject: @escaping RejectCallBack) {
        let nextPromise: Promise<X> = block(result)
        nextPromise.then { x in
            resolve(x)
            }.onError(reject)
    }
    
    private func resolvePromise(_ result: T) {
        state = .fulfilled(value:result)
        for sb in successBlocks {
            sb(result)
        }
        finallyBlock()
        initialPromiseStart = nil
    }
    
    private func rejectPromise(_ anError: Error) {
        state = .rejected(error:anError)
        for fb in failBlocks {
            fb(anError)
        }
        finallyBlock()
        initialPromiseStart = nil
    }
    
    private func progressPromise(_ value: Float) {
        progress = value
        for pb in progressBlocks {
            if let progress = progress {
                pb(progress)
            }
        }
    }
}
