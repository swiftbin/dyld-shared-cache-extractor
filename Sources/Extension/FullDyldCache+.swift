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

extension FullDyldCache {
    internal typealias File = ConcatenatedMemoryMappedFile

    var fileHandle: File {
        try! .open(urls: urls, isWritable: false)
    }
}
