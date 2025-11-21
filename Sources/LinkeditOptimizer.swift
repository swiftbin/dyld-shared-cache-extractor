//
//  LinkeditOptimizer.swift
//  dyld-shared-cache-extractor
//
//  Created by p-x9 on 2025/02/14
//  
//

import Foundation
@_spi(Support) import MachOKit

enum LinkeditOptimizerError: Error {
    case notFoundLinkedit
    case notFoundSymtab
    case notFoundDysymtab
    case invalidSymbolCount
}

extension LinkeditOptimizerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notFoundLinkedit:
            "__LINKEDIT not found"
        case .notFoundSymtab:
            "LC_SYMTAB not found"
        case .notFoundDysymtab:
            "LC_DYSYMTAB not found"
        case .invalidSymbolCount:
            "symbol count miscalculation"
        }
    }
}

final class LinkeditOptimizer {
    typealias FileHandle = MachOFile.File

    enum Segment {
        case _32(SegmentCommand)
        case _64(SegmentCommand64)
    }

    enum SymTab {
        case _32([Nlist])
        case _64([Nlist64])
    }

    let machO: MachOFile
    let cache: FullDyldCache

    private(set) var linkedit: Segment?
    private(set) var symtab: LoadCommandInfo<symtab_command>?
    private(set) var dysymtab: LoadCommandInfo<dysymtab_command>?
    private(set) var functionStarts: LoadCommandInfo<linkedit_data_command>?
    private(set) var dataInCode: LoadCommandInfo<linkedit_data_command>?

    private var exports: [ExportedSymbol] = []
    private var exportsTrieOffset: UInt32 = 0
    private var exportsTrieSize: UInt32 = 0
    private var reexportDeps: [Int] = []

    init(
        machO: MachOFile,
        cache: FullDyldCache
    ) {
        self.machO = machO
        self.cache = cache
    }
}

extension LinkeditOptimizer {
    // https://github.com/apple-oss-distributions/dyld/blob/93bd81f9d7fcf004fcebcb66ec78983882b41e71/other-tools/dsc_extractor.cpp#L514
    func optimizeLoadCommands(
        writeHandle: FileHandle
    ) throws {
        // update header flags
        let flags = machO.header.layout.flags
        try writeHandle.write(
            flags & ~MachHeader.Flags.Bit.dylib_in_cache.rawValue,
            at: numericCast(MachHeader.layoutOffset(of: \.flags))
        )

        // update load commands
        var cumulativeFileSize: UInt64 = 0
        var depIndex = 0

        for loadCommand in machO.loadCommands {
            switch loadCommand {
            case let .segment(segment):
                if segment.segmentName == "__LINKEDIT" {
                    var segment = segment
                    segment.layout.fileoff = numericCast(cumulativeFileSize)
                    segment.layout.filesize = segment.vmsize
                    linkedit = ._32(segment)
                }

                let layoutOffset = machO.headerSize + loadCommand.offset
                try writeHandle.write(
                    UInt32(cumulativeFileSize),
                    at: numericCast(
                        layoutOffset + SegmentCommand.layoutOffset(of: \.fileoff)
                    )
                )
                try writeHandle.write(
                    segment.vmsize,
                    at: numericCast(
                        layoutOffset + SegmentCommand.layoutOffset(of: \.filesize)
                    )
                )

                let sectionsStart = layoutOffset + SegmentCommand.layoutSize
                let sections = segment.sections(in: machO)
                for (i, section) in sections.enumerated() {
                    let layoutOffset = sectionsStart + i * Section.layoutSize
                    let offset: UInt32 = numericCast(cumulativeFileSize + numericCast(section.addr - segment.vmaddr))
                    if section.offset != 0 {
                        try writeHandle.write(
                            offset,
                            at: numericCast(
                                layoutOffset + Section.layoutOffset(of: \.offset)
                            )
                        )
                    }
                }
                cumulativeFileSize += numericCast(segment.filesize)

            case let .segment64(segment):
                if segment.segmentName == "__LINKEDIT" {
                    var segment = segment
                    segment.layout.fileoff = cumulativeFileSize
                    segment.layout.filesize = segment.vmsize
                    linkedit = ._64(segment)
                }

                let layoutOffset = machO.headerSize + loadCommand.offset
                try writeHandle.write(
                    cumulativeFileSize,
                    at: numericCast(
                        layoutOffset + SegmentCommand64.layoutOffset(of: \.fileoff)
                    )
                )
                try writeHandle.write(
                    segment.vmsize,
                    at: numericCast(
                        layoutOffset + SegmentCommand64.layoutOffset(of: \.filesize)
                    )
                )

                let sectionsStart = layoutOffset + SegmentCommand64.layoutSize
                let sections = segment.sections(in: machO)
                for (i, section) in sections.enumerated() {
                    let layoutOffset = sectionsStart + i * Section64.layoutSize
                    let offset: UInt32 = numericCast(cumulativeFileSize + section.addr - segment.vmaddr)
                    if section.offset != 0 {
                        try writeHandle.write(
                            offset,
                            at: numericCast(
                                layoutOffset + Section64.layoutOffset(of: \.offset)
                            )
                        )
                    }
                }
                cumulativeFileSize += segment.filesize

            case let .dyldInfoOnly(info):
                let layoutOffset = machO.headerSize + loadCommand.offset
                var dyldInfo = info.layout

                exportsTrieOffset = dyldInfo.export_off
                exportsTrieSize = dyldInfo.export_size

                dyldInfo.rebase_off = 0
                dyldInfo.rebase_size = 0
                dyldInfo.bind_off = 0
                dyldInfo.bind_size = 0
                dyldInfo.weak_bind_off = 0
                dyldInfo.weak_bind_size = 0
                dyldInfo.lazy_bind_off = 0
                dyldInfo.lazy_bind_size = 0
                dyldInfo.export_off = 0
                dyldInfo.export_size = 0
                try writeHandle.write(dyldInfo, at: numericCast(layoutOffset))

            case let .dyldExportsTrie(info):
                let layoutOffset = machO.headerSize + loadCommand.offset
                var exportsTrie = info.layout

                exportsTrieOffset = exportsTrie.dataoff
                exportsTrieSize = exportsTrie.datasize

                exportsTrie.dataoff = 0
                exportsTrie.datasize = 0
                try writeHandle.write(exportsTrie, at: numericCast(layoutOffset))

            case let .symtab(info):
                symtab = info

            case let .dysymtab(info):
                dysymtab = info

            case let .functionStarts(info):
                functionStarts = info

            case let .dataInCode(info):
                dataInCode = info

            case .loadDylib, .loadWeakDylib, .loadUpwardDylib:
                depIndex += 1

            case .reexportDylib:
                depIndex += 1
                reexportDeps.append(depIndex)

            default:
                break
            }
        }

        exports = machO.exportTrie?.exportedSymbols ?? []

        // dylibs iOS 9 dyld caches have bogus LC_SEGMENT_SPLIT_INFO
        if let command = machO.loadCommands.of(.segmentSplitInfo).first(where: { _ in true }) {
            try removeLoadCommand(command, with: writeHandle)
        }
    }
}

extension LinkeditOptimizer {
    // ref: https://github.com/apple-oss-distributions/dyld/blob/93bd81f9d7fcf004fcebcb66ec78983882b41e71/other-tools/dsc_extractor.cpp#L609
    func optimizeLinkEdit(
        newLinkeditData: inout Data,
        writeHandle: FileHandle
    ) throws {
        guard let linkedit else { throw LinkeditOptimizerError.notFoundLinkedit }
        guard let symtab else { throw LinkeditOptimizerError.notFoundSymtab }
        guard let dysymtab else { throw LinkeditOptimizerError.notFoundDysymtab }

        // function starts
        let newFunctionStartsOffset = newLinkeditData.count
        var functionStartsSize = 0
        if let functionStarts {
            functionStartsSize = numericCast(functionStarts.datasize)
            let data = machO._readLinkEditData(
                offset: numericCast(functionStarts.dataoff),
                length: numericCast(functionStarts.datasize)
            )!
            newLinkeditData.append(data)
        }

        // pointer align
        newLinkeditData.pad(
            toAlignment: machO.alignment,
            baseOffset: linkedit.fileOffset
        )

        // data in codes
        let newDataInCodeOffset = newLinkeditData.count
        var dataInCodeSize = 0
        if let dataInCode {
            dataInCodeSize = numericCast(dataInCode.datasize)
            let data = machO._readLinkEditData(
                offset: numericCast(dataInCode.dataoff),
                length: numericCast(dataInCode.datasize)
            )!
            newLinkeditData.append(data)
        }

        // exports
        if exportsTrieSize != 0 {
            exports.removeAll { entry in
                if entry.flags.kind != .regular { return true }
                if !entry.flags.contains(.reexport) { return true }
                if let ordinal = entry.ordinal {
                    return reexportDeps.contains(numericCast(ordinal))
                }
                return false
            }
        }

        // local symbols
        var localSymbols: [MachOFile.Symbol] = []
        if let symbolsCache = try? cache.symbolCache,
           let info = symbolsCache.localSymbolsInfo,
           // On new caches, the dylibOffset is 64-bits, and is a VM offset
           let entry = info.entry64(for: machO, in: symbolsCache) {
            if let symbols64 = info.symbols64(in: symbolsCache) {
                localSymbols = Array(symbols64[entry.nlistRange])
            } else if let symbols32 = info.symbols32(in: symbolsCache) {
                localSymbols = Array(symbols32[entry.nlistRange])
            }
        }

        // compute number of symbols in new symbol table
        var newSymCount: Int = numericCast(symtab.nsyms)
        if localSymbols.isEmpty == false {
            newSymCount = localSymbols.count + numericCast(dysymtab.nextdefsym + dysymtab.nundefsym)
        }
        // add room for N_INDR symbols for re-exported symbols
        newSymCount += exports.count

        var newSymTab: SymTab = machO.is64Bit ? ._64([]) : ._32([])
        var newSymNames = Data()
        // first pool entry is always empty string
        newSymNames.append(0)

        // local symbols are first in dylibs, if this cache has unmapped locals, insert them all first
        var undefSymbolShift: UInt32 = 0
        if !localSymbols.isEmpty {
            undefSymbolShift = numericCast(localSymbols.count) - dysymtab.nlocalsym

            // update load command to reflect new count of locals
            self.dysymtab?.layout.ilocalsym = numericCast(newSymTab.count)
            self.dysymtab?.layout.nlocalsym = numericCast(localSymbols.count)

            // copy local symbols
            for symbol in localSymbols {
                let localName = symbol.name
                // TODO: <corrupt local symbol name>
                if machO.is64Bit {
                    var nlist = (symbol.nlist as! Nlist64)
                    nlist.layout.n_un.n_strx = numericCast(newSymNames.count)
                    newSymTab.append(nlist)
                } else {
                    var nlist = (symbol.nlist as! Nlist)
                    nlist.layout.n_un.n_strx = numericCast(newSymNames.count)
                    newSymTab.append(nlist)
                }

                newSymNames.append(localName.data(using: .utf8) ?? Data())
                newSymNames.append(.init(0))
            }
        }

        // copy full symbol table from cache (skipping locals if they where elsewhere)
        var symbols: [MachOFile.Symbol] = []
        if !localSymbols.isEmpty {
            let index: Int = numericCast(dysymtab.iextdefsym)
            symbols = Array(machO.symbols[AnyIndex(index)...])
        } else {
            symbols = Array(machO.symbols)
        }
        for symbol in symbols {
            let symbolName = symbol.name
            // TODO: <corrupt symbol name>
            if machO.is64Bit {
                var nlist = (symbol.nlist as! Nlist64)
                nlist.layout.n_un.n_strx = numericCast(newSymNames.count)
                newSymTab.append(nlist)
            } else {
                var nlist = (symbol.nlist as! Nlist)
                nlist.layout.n_un.n_strx = numericCast(newSymNames.count)
                newSymTab.append(nlist)
            }
            newSymNames.append(symbolName.data(using: .utf8) ?? Data())
            newSymNames.append(.init(0))
        }

        // <rdar://problem/16529213> recreate N_INDR symbols in extracted dylibs for debugger
        for export in exports {
            var importName = export.importedName ?? ""
            if importName.isEmpty {
                importName = export.name
            }

            let n_strx: UInt32 = numericCast(newSymNames.count)
            newSymNames.append(export.name.data(using: .utf8) ?? Data())
            newSymNames.append(.init(0))
            let n_value: UInt64 = numericCast(newSymNames.count)
            newSymNames.append(importName.data(using: .utf8) ?? Data())
            newSymNames.append(.init(0))

            if machO.is64Bit {
                let _nlist = nlist_64(
                    n_un: .init(n_strx: n_strx),
                    n_type: UInt8(N_INDR | N_EXT),
                    n_sect: 0,
                    n_desc: 0,
                    n_value: n_value
                )
                newSymTab.append(unsafeBitCast(_nlist, to: Nlist64.self))
            } else {
                let _nlist = nlist(
                    n_un: .init(n_strx: n_strx),
                    n_type: UInt8(N_INDR | N_EXT),
                    n_sect: 0,
                    n_desc: 0,
                    n_value: numericCast(n_value)
                )
                newSymTab.append(unsafeBitCast(_nlist, to: Nlist.self))
            }
        }

        if newSymCount != newSymTab.count {
            throw LinkeditOptimizerError.invalidSymbolCount
        }

        // pointer align
        newLinkeditData.pad(
            toAlignment: machO.alignment,
            baseOffset: linkedit.fileOffset
        )

        let newSymTabOffset = newLinkeditData.count

        // Copy sym tab
        let newSymTabData = if machO.is64Bit {
            newSymTab.values64.reduce(into: Data(), {
                $0.append($1.data)
            })
        } else {
            newSymTab.values32.reduce(into: Data(), {
                $0.append($1.data)
            })
        }
        newLinkeditData.append(newSymTabData)

        let newIndSymTabOffset = newLinkeditData.count

        // Copy (and adjust) indirect symbol table
        if let _indirectSymbols = machO.indirectSymbols {
            var indirectSymbols = _indirectSymbols.map {
                unsafeBitCast($0, to: UInt32.self)
            }
            if undefSymbolShift != 0 {
                indirectSymbols = indirectSymbols.map { $0 + undefSymbolShift }
            }
            newLinkeditData.append(indirectSymbols.withUnsafeBytes { Data($0) })
        }

        let newStringPoolOffset = newLinkeditData.count

        // pointer align string pool size
        newSymNames.pad(
            toAlignment: machO.alignment
        )

        newLinkeditData.append(newSymNames)

        // update load commands
        if functionStarts != nil {
            functionStarts?.layout.dataoff = numericCast(newFunctionStartsOffset) + numericCast(linkedit.fileOffset)
            functionStarts?.layout.datasize = numericCast(functionStartsSize)
        }
        if dataInCode != nil {
            dataInCode?.layout.dataoff = numericCast(newDataInCodeOffset) + numericCast(linkedit.fileOffset)
            dataInCode?.layout.datasize = numericCast(dataInCodeSize)
        }

        self.symtab?.layout.nsyms = numericCast(newSymCount)
        self.symtab?.layout.symoff = numericCast(newSymTabOffset) + numericCast(linkedit.fileOffset)
        self.symtab?.layout.stroff = numericCast(newStringPoolOffset) + numericCast(linkedit.fileOffset)
        self.symtab?.layout.strsize = numericCast(newSymNames.count)

        self.dysymtab?.layout.extreloff = 0
        self.dysymtab?.layout.nextrel = 0
        self.dysymtab?.layout.locreloff = 0
        self.dysymtab?.layout.nlocrel = 0
        self.dysymtab?.layout.indirectsymoff = numericCast(newIndSymTabOffset) + numericCast(linkedit.fileOffset)

        let linkeditFilesize: UInt64 = numericCast(self.symtab!.stroff + self.symtab!.strsize) - numericCast(linkedit.fileOffset)

        switch self.linkedit {
        case ._32(var linkedit):
            linkedit.layout.filesize = UInt32(linkeditFilesize)
            linkedit.layout.vmsize = UInt32(linkeditFilesize.alignedUp(to: 4096))
            self.linkedit = ._32(linkedit)
        case ._64(var linkedit):
            linkedit.layout.filesize = linkeditFilesize
            linkedit.layout.vmsize = linkeditFilesize.alignedUp(to: 4096)
            self.linkedit = ._64(linkedit)
        case .none:
            break
        }

        // write command
        let base = machO.headerSize
        if let functionStarts {
            try writeHandle.write(
                functionStarts.layout,
                at: base + numericCast(functionStarts.offset)
            )
        }
        if let dataInCode {
            try writeHandle.write(
                dataInCode.layout,
                at: base + numericCast(dataInCode.offset)
            )
        }

        if let symtab = self.symtab {
            try writeHandle.write(
                symtab.layout,
                at: base + numericCast(symtab.offset)
            )
        }
        if let dysymtab = self.dysymtab {
            try writeHandle.write(
                dysymtab.layout,
                at: base + numericCast(dysymtab.offset)
            )
        }
        if let linkedit = self.linkedit {
            switch linkedit {
            case ._32(let linkedit):
                try writeHandle.write(
                    linkedit.layout,
                    at: base + numericCast(linkedit.offset)
                )
            case ._64(let linkedit):
                try writeHandle.write(
                    linkedit.layout,
                    at: base + numericCast(linkedit.offset)
                )
            }
        }
    }
}

extension LinkeditOptimizer {
    // ref: https://github.com/apple-oss-distributions/dyld/blob/93bd81f9d7fcf004fcebcb66ec78983882b41e71/common/MachOFile.cpp#L710
    func removeLoadCommand(
        _ command: LoadCommand,
        with writeHandle: FileHandle
    ) throws {
        let header = machO.header

        // update header flags
        let ncmds = header.layout.ncmds
        let sizeofcmds = header.layout.sizeofcmds
        let commandSize: Int = numericCast(command.cmdsize)
        try writeHandle.write(
            ncmds - 1,
            at: numericCast(MachHeader.layoutOffset(of: \.ncmds))
        )
        try writeHandle.write(
            sizeofcmds - numericCast(commandSize),
            at: numericCast(MachHeader.layoutOffset(of: \.sizeofcmds))
        )

        // move loadcommands
        let start = machO.headerSize + command.offset + commandSize
        let end = machO.headerSize + numericCast(header.sizeofcmds)
        let size = end - start
        let buffer = try writeHandle.readData(
            offset: numericCast(start),
            length: size
        )
        try writeHandle.writeData(buffer, at: numericCast(start - commandSize))
        try writeHandle.writeData(Data(count: commandSize), at: numericCast(end - commandSize)) // fill zero
    }
}

extension LinkeditOptimizer.Segment {
    @inline(__always)
    var fileOffset: Int {
        switch self {
        case ._64(let segment):
            segment.fileOffset
        case ._32(let segment):
            segment.fileOffset
        }
    }
}

extension LinkeditOptimizer.SymTab {
    @inline(__always)
    var count: Int {
        switch self {
        case ._32(let list):
            list.count
        case ._64(let list):
            list.count
        }
    }

    @inline(__always)
    var values64: [Nlist64] {
        switch self {
        case ._32:
            fatalError(
                "\(#function) called on 32-bit symtab, which is not supported"
            )
        case ._64(let list):
            return list
        }
    }

    @inline(__always)
    var values32: [Nlist] {
        switch self {
        case ._32(let list):
            return list
        case ._64:
            fatalError(
                "\(#function) called on 64-bit symtab, which is not supported"
            )
        }
    }

    @inline(__always)
    mutating func append(_ value: Nlist) {
        switch self {
        case ._32(let list):
            self = ._32([value] + list)
        case ._64:
            fatalError(
                "\(#function) called on 64-bit symtab, which is not supported"
            )
        }
    }

    @inline(__always)
    mutating func append(_ value: Nlist64) {
        switch self {
        case ._32:
            fatalError(
                "\(#function) called on 64-bit symtab, which is not supported"
            )
        case ._64(let list):
            self = ._64([value] + list)
        }
    }
}
