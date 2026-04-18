// The Swift Programming Language
// https://docs.swift.org/swift-book
// 
// Swift Argument Parser
// https://swiftpackageindex.com/apple/swift-argument-parser/documentation

import Foundation
import ArgumentParser
@_spi(Support) import MachOKit

@main
struct dyld_shared_cache_extractor: ParsableCommand {
    enum ExtractorError: Error {
        case failedToLoadDyldCache(error: Error)
        case dyldNotFound(name: String)
    }

    static let configuration = CommandConfiguration(
        commandName: "dyld-shared-cache-extractor",
        abstract: "Extract dylib from dyld shared cache",
        version: "0.1.0"
    )

    @Argument(help: "Path to the input main dyld shared cache file.")
    var inputPath: String

    @Option(name: .shortAndLong, help: "Path to the output directory for exacted dyld file (default: ./)")
    var output: String?

    @Option(name: .shortAndLong, help: "Name of dylib to be extracted.")
    var dylib: String?

    @Flag(name: .long, help: "Extract all dylibs.")
    var all: Bool = false

    @Flag(
        name: .long,
        help: "Skip extraction of local symbols from dyld local symbol cache."
    )
    var skipLocalSymbols: Bool = false

    var inputURL: URL { .init(fileURLWithPath: inputPath) }
    var outputDirectoryURL: URL {
        if let output {
            URL(fileURLWithPath: output)
        } else {
            if #available(macOS 13.0, *) {
                URL.currentDirectory()
            } else {
                URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            }
        }
    }

    mutating func run() throws {
        let cache = try loadDyldCache(url: inputURL)

        if all {
            try extractAll(
                from: cache,
                outputDirectory: outputDirectoryURL
            )
        } else if let dylib {
            try extract(
                dylib: dylib,
                from: cache,
                outputDirectory: outputDirectoryURL
            )
        } else {
            print(Self.helpMessage())
        }
    }
}

extension dyld_shared_cache_extractor {
    private func loadDyldCache(
        url: URL
    ) throws -> FullDyldCache {
        do {
            return try FullDyldCache(url: url)
        } catch {
            throw ExtractorError.failedToLoadDyldCache(error: error)
        }
    }
}

extension dyld_shared_cache_extractor {
    private func extract(
        dylib: String,
        from cache: FullDyldCache,
        outputDirectory: URL
    ) throws {
        guard let machO = cache.machOFiles().first(
            where: {
                $0.name == dylib ||
                $0.imagePath.components(separatedBy: "/").last == dylib ||
                dylib.hasSuffix(".framework") && $0.imagePath.contains(dylib)
            }
        ) else {
            throw ExtractorError.dyldNotFound(name: dylib)
        }
        try extract(
            machO: machO,
            from: cache,
            outputDirectory: outputDirectory
        )
    }

    private func extractAll(
        from cache: FullDyldCache,
        outputDirectory: URL
    ) throws {
        let count = cache.header.imagesCount
        try cache.machOFiles().enumerated().forEach {
            print("[\($0 + 1)/\(count)] Extracting: \($1.imagePath)")
            try extract(
                machO: $1,
                from: cache,
                outputDirectory: outputDirectory
            )
        }
    }

    private func extract(
        machO: MachOFile,
        from cache: FullDyldCache,
        outputDirectory: URL
    ) throws {
        let extractor = SharedCacheDylibExtractor(
            outputDirectory: outputDirectory,
            skipLocalSymbols: skipLocalSymbols
        )
        try extractor.extract(for: machO, in: cache)
    }
}

extension dyld_shared_cache_extractor.ExtractorError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .failedToLoadDyldCache(let error):
            "Failed to load dyld cache: \(error)"
        case .dyldNotFound(let name):
            "Dyld \(name) not found in cache"
        }
    }
}

private extension MachOFile {
    var name: String? {
        imagePath
            .components(separatedBy: "/")
            .last?
            .components(separatedBy: ".")
            .first
    }
}
