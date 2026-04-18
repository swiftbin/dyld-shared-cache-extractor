//
//  FullDyldCache+.swift
//  dyld-shared-cache-extractor
//
//  Created by p-x9 on 2025/07/29
//  
//

import Foundation
import MachOKit
import FileIO
//#if canImport(os)
//import struct os.OSAllocatedUnfairLock
//#endif

fileprivate final class FileHandleHolder: @unchecked Sendable {
    static let shared = FileHandleHolder()

//#if canImport(os)
//    private let lock: OSAllocatedUnfairLock = .init()
//#else
    private let lock: NSRecursiveLock = .init()
//#endif

#if canImport(ObjectiveC)
    private let _mapTable: NSMapTable<FullDyldCache, FullDyldCache.File> = .weakToStrongObjects()
#else
    private var _mapTable = WeakKeyStrongValueMap<FullDyldCache, FullDyldCache.File>()
#endif

    private init() {}

    func fileHandle(
        for cache: FullDyldCache,
        initialize: () -> FullDyldCache.File
    ) -> FullDyldCache.File {
        lock.lock()
        defer { lock.unlock() }

        if let fileHandle = _mapTable.object(forKey: cache) {
            return fileHandle
        } else {
            let fileHandle = initialize()
            _mapTable.setObject(fileHandle, forKey: cache)
            return fileHandle
        }
    }
}

#if !canImport(ObjectiveC)
fileprivate final class WeakBox<Value: AnyObject> {
    weak var value: Value?
    let id: ObjectIdentifier

    init(_ value: Value) {
        self.value = value
        self.id = ObjectIdentifier(value)
    }
}

fileprivate struct WeakKeyStrongValueMap<Key: AnyObject, Value> {
    private var storage: [ObjectIdentifier: (key: WeakBox<Key>, value: Value)] = [:]

    mutating func object(forKey key: Key) -> Value? {
        cleanupIfNeeded()
        return storage[ObjectIdentifier(key)]?.value
    }

    mutating func setObject(_ value: Value, forKey key: Key) {
        cleanupIfNeeded()
        let box = WeakBox(key)
        storage[box.id] = (box, value)
    }

    private mutating func cleanupIfNeeded() {
        storage = storage.filter { $0.value.key.value != nil }
    }
}
#endif

extension FullDyldCache {
    internal typealias File = ConcatenatedMemoryMappedFile

    var fileHandle: File {
        FileHandleHolder.shared.fileHandle(
            for: self,
            initialize: {
                try! .open(urls: urls, isWritable: false)
            }
        )
    }
}
