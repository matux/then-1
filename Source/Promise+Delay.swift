//
//  Promise+Delay.swift
//  then
//
//  Created by Sacha Durand Saint Omer on 09/08/2017.
//  Copyright © 2017 s4cha. All rights reserved.
//

import Foundation

extension Promise {
    
    public func delay(_ time: TimeInterval) -> Promise<T> {
        return Promise<T> { resolve, reject in
            self.then { t in
                Promises.callBackOnCallingQueueIn(time: time) {
                    resolve(t)
                }
            }.onError { e in
                reject(e)
            }
        }
    }
}

extension Promises {
    public static func delay(_ time: TimeInterval) -> Promise<Void> {
        return Promise { resolve, _ in
            callBackOnCallingQueueIn(time: time, block: resolve)
        }
    }
}

extension Promises {

    static func callBackOnCallingQueueIn(time: TimeInterval, block: @escaping () -> Void) {
        if let callingQueue = OperationQueue.current?.underlyingQueue {
            DispatchQueue.global(qos: DispatchQoS.QoSClass.userInitiated).asyncAfter(deadline: .now() + time) {
                callingQueue.async {
                    block()
                }
            }
        }
    }
}