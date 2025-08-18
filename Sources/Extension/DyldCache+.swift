//
//  DyldCache+.swift
//  dyld-shared-cache-extractor
//
//  Created by p-x9 on 2025/07/29
//  
//

import Foundation
import MachOKit
import FileIO

extension DyldCache {
    internal typealias File = MemoryMappedFile

    var fileHandle: File {
        try! .open(url: url, isWritable: false)
    }
}
