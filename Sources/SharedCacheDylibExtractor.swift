//
//  SharedCacheDylibExtractor.swift
//  dyld-shared-cache-extractor
//
//  Created by p-x9 on 2025/08/17
//  
//

import Foundation
import MachOKit
import FileIO

final class SharedCacheDylibExtractor {
    typealias FileHandle = MemoryMappedFile

    let outputDirectory: URL
    let skipLocalSymbols: Bool

    private let fileManager = FileManager.default

    init(
        outputDirectory: URL,
        skipLocalSymbols: Bool = false
    ) {
        self.outputDirectory = outputDirectory
        self.skipLocalSymbols = skipLocalSymbols
    }

    func extract(for machO: MachOFile, in cache: FullDyldCache) throws {
        let path = machO.imagePath
        let outputURL = outputDirectory.appendingPathComponent(path)

        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        fileManager.createFile(
            atPath: outputURL.path,
            contents: nil
        )

        let writeHandle: FileHandle = try .open(
            url: outputURL,
            isWritable: true
        )

        try dylibCreate(
            for: machO,
            in: cache,
            writeHandle: writeHandle
        )
    }
}

extension SharedCacheDylibExtractor {
    // https://github.com/apple-oss-distributions/dyld/blob/93bd81f9d7fcf004fcebcb66ec78983882b41e71/other-tools/dsc_extractor.cpp#L853
    private func dylibCreate(
        for machO: MachOFile,
        in cache: FullDyldCache,
        writeHandle: FileHandle
    ) throws {
        var additionalSize = 0
        for segment in machO.segments {
            guard segment.segmentName != "__LINKEDIT" else { continue }
            additionalSize += segment.fileSize
        }

        // Write regular segments into the buffer
        for segment in machO.segments {
            guard segment.segmentName != "__LINKEDIT" else { continue }

            guard let fileOffset = cache.fileOffset(
                of: numericCast(segment.virtualMemoryAddress)
            ) else { fatalError("Invalid virtual memory address") }

            let data = try cache.fileHandle.readData(
                offset: numericCast(fileOffset),
                length: segment.fileSize
            )
            try writeHandle.insertData(data, at: writeHandle.size)
        }

        // optimize linkedit
        let linkeditOptimizer = LinkeditOptimizer(
            machO: machO,
            cache: cache,
            skipLocalSymbols: skipLocalSymbols
        )
        try linkeditOptimizer.optimizeLoadCommands(
            writeHandle: writeHandle
        )

        var newLinkeditData = Data()
        try linkeditOptimizer.optimizeLinkEdit(
            newLinkeditData: &newLinkeditData,
            writeHandle: writeHandle
        )
        try writeHandle.insertData(newLinkeditData, at: writeHandle.size)

        // Page align file
        let current = writeHandle.size
        let aligned = writeHandle.size.alignedUp(to: 4096)
        let pad = aligned - current
        if pad != 0 {
            try writeHandle.insertData(Data(count: pad), at: writeHandle.size)
        }
    }
}
