//
//  MachOFile+.swift
//  dyld-shared-cache-extractor
//
//  Created by p-x9 on 2025/07/29
//  
//

import Foundation
import MachOKit
import FileIO

extension MachOFile {
    internal typealias File = MemoryMappedFile
}

extension MachOFile {
    var alignment: Int {
        is64Bit ? MemoryLayout<UInt64>.size : MemoryLayout<UInt32>.size
    }
}

extension LoadCommand {
    public var cmdsize: UInt32 {
        switch self {
        case let .segment(info): info.cmdsize
        case let .symtab(info): info.cmdsize
        case let .symseg(info): info.cmdsize
        case let .thread(info): info.cmdsize
        case let .unixthread(info): info.cmdsize
        case let .loadfvmlib(info): info.cmdsize
        case let .idfvmlib(info): info.cmdsize
        case let .ident(info): info.cmdsize
        case let .fvmfile(info): info.cmdsize
        case let .prepage(info): info.cmdsize
        case let .dysymtab(info): info.cmdsize
        case let .loadDylib(info): info.cmdsize
        case let .idDylib(info): info.cmdsize
        case let .loadDylinker(info): info.cmdsize
        case let .idDylinker(info): info.cmdsize
        case let .preboundDylib(info): info.cmdsize
        case let .routines(info): info.cmdsize
        case let .subFramework(info): info.cmdsize
        case let .subUmbrella(info): info.cmdsize
        case let .subClient(info): info.cmdsize
        case let .subLibrary(info): info.cmdsize
        case let .twolevelHints(info): info.cmdsize
        case let .prebindCksum(info): info.cmdsize
        case let .loadWeakDylib(info): info.cmdsize
        case let .segment64(info): info.cmdsize
        case let .routines64(info): info.cmdsize
        case let .uuid(info): info.cmdsize
        case let .rpath(info): info.cmdsize
        case let .codeSignature(info): info.cmdsize
        case let .segmentSplitInfo(info): info.cmdsize
        case let .reexportDylib(info): info.cmdsize
        case let .lazyLoadDylib(info): info.cmdsize
        case let .encryptionInfo(info): info.cmdsize
        case let .dyldInfo(info): info.cmdsize
        case let .dyldInfoOnly(info): info.cmdsize
        case let .loadUpwardDylib(info): info.cmdsize
        case let .versionMinMacosx(info): info.cmdsize
        case let .versionMinIphoneos(info): info.cmdsize
        case let .functionStarts(info): info.cmdsize
        case let .dyldEnvironment(info): info.cmdsize
        case let .main(info): info.cmdsize
        case let .dataInCode(info): info.cmdsize
        case let .sourceVersion(info): info.cmdsize
        case let .dylibCodeSignDrs(info): info.cmdsize
        case let .encryptionInfo64(info): info.cmdsize
        case let .linkerOption(info): info.cmdsize
        case let .linkerOptimizationHint(info): info.cmdsize
        case let .versionMinTvos(info): info.cmdsize
        case let .versionMinWatchos(info): info.cmdsize
        case let .note(info): info.cmdsize
        case let .buildVersion(info): info.cmdsize
        case let .dyldExportsTrie(info): info.cmdsize
        case let .dyldChainedFixups(info): info.cmdsize
        case let .filesetEntry(info): info.cmdsize
        case let .atomInfo(info): info.cmdsize
        case let .functionVariants(info): info.cmdsize
        case let .functionVariantFixups(info): info.cmdsize
        case let .targetTriple(info): info.cmdsize
        }
    }
}
