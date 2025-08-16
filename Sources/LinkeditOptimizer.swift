//
//  LinkeditOptimizer.swift
//  dyld-shared-cache-extractor
//
//  Created by p-x9 on 2025/02/14
//  
//

import Foundation
@_spi(Support) import MachOKit

class LinkeditOptimizer {
    typealias FileHandle = MachOFile.File

    let machO: MachOFile
    let cache: FullDyldCache

    var linkedit: SegmentCommand64?
    var symtab: LoadCommandInfo<symtab_command>?
    var dysymtab: LoadCommandInfo<dysymtab_command>?
    var functionStarts: LoadCommandInfo<linkedit_data_command>?
    var dataInCode: LoadCommandInfo<linkedit_data_command>?

    var exports: [ExportedSymbol] = []
    var exportsTrieOffset: UInt32 = 0
    var exportsTrieSize: UInt32 = 0
    var reexportDeps: [Int] = []

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
//            case let .segment(segment):
//                if segment.segmentName == "__LINKEDIT" {
//                    linkedit = segment
//                }
//                cumulativeFileSize += UInt64(segment.filesize)
//                // TODO: Support 32bit

            case let .segment64(segment):
                if segment.segmentName == "__LINKEDIT" {
                    linkedit = segment
                    linkedit?.layout.fileoff = cumulativeFileSize
                    linkedit?.layout.filesize = segment.vmsize
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

        // TODO: not original, check
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
        guard let linkedit else { throw "__LINKEDIT not found" }
        guard let symtab else { throw "LC_SYMTAB not found" }
        guard let dysymtab else { throw "LC_DYSYMTAB not found" }

        // function starts
        let newFunctionStartsOffset = newLinkeditData.count
        var functionStartsSize = 0
        if let functionStarts {
            functionStartsSize = numericCast(functionStarts.datasize)
            let data = try machO.fileHandle.readData(
                offset: numericCast(functionStarts.dataoff),
                length: functionStartsSize
            )
            newLinkeditData.append(data)
        }

        // pointer align
        let pad = (MemoryLayout<UInt64>.size - ((linkedit.fileOffset + newLinkeditData.count) % MemoryLayout<UInt64>.size)) % MemoryLayout<UInt64>.size
        if pad != 0 {
            newLinkeditData.append(Data(count: pad))
        }

        // data in codes
        let newDataInCodeOffset = newLinkeditData.count
        var dataInCodeSize = 0
        if let dataInCode {
            dataInCodeSize = numericCast(dataInCode.datasize)
            let data = try machO.fileHandle.readData(
                offset: numericCast(dataInCode.dataoff),
                length: dataInCodeSize
            )
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
           let info = symbolsCache.localSymbolsInfo {
            let allSymbols = Array(info.symbols(in: symbolsCache))
            if let entry = info.entry(for: machO, in: symbolsCache) {
                localSymbols = Array(allSymbols[entry.nlistRange])
            }
        }

        // compute number of symbols in new symbol table
        var newSymCount: Int = numericCast(symtab.nsyms)
        if localSymbols.isEmpty == false {
            newSymCount = localSymbols.count + numericCast(dysymtab.nextdefsym + dysymtab.nundefsym)
        }
        // add room for N_INDR symbols for re-exported symbols
        newSymCount += exports.count

        var newSymTab = [Nlist64]()
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
                var nlist = (symbol.nlist as! Nlist64)
                nlist.layout.n_un.n_strx = numericCast(newSymNames.count)
                newSymNames.append(localName.data(using: .utf8) ?? Data())
                newSymNames.append(.init(0))
                newSymTab.append(nlist)
            }
        }

        // copy full symbol table from cache (skipping locals if they where elsewhere)
        if let _symbols = machO.symbols64 {
            var symbols = Array(_symbols)
            if !localSymbols.isEmpty {
                symbols = Array(symbols[Int(dysymtab.iextdefsym)...])
            }
            for symbol in symbols {
                let symbolName = symbol.name
                // TODO: <corrupt symbol name>
                var nlist = (symbol.nlist as! Nlist64)
                nlist.layout.n_un.n_strx = numericCast(newSymNames.count)
                newSymNames.append(symbolName.data(using: .utf8) ?? Data())
                newSymNames.append(.init(0))
                newSymTab.append(nlist)
            }
        }

        // <rdar://problem/16529213> recreate N_INDR symbols in extracted dylibs for debugger
        for export in exports {
            var importName = export.importedName ?? ""
            if importName.isEmpty {
                importName = export.name
            }
            var _nlist = nlist_64(
                n_un: .init(n_strx: numericCast(newSymNames.count)),
                n_type: UInt8(N_INDR | N_EXT),
                n_sect: 0,
                n_desc: 0,
                n_value: 0
            )
            newSymNames.append(export.name.data(using: .utf8) ?? Data())
            newSymNames.append(.init(0))
            _nlist.n_value = numericCast(newSymNames.count)
            newSymNames.append(importName.data(using: .utf8) ?? Data())
            newSymNames.append(.init(0))
            newSymTab.append(unsafeBitCast(_nlist, to: Nlist64.self))
        }

        if newSymCount != newSymTab.count {
            print("symbol count miscalculation\n")
            return
        }

        // pointer align
        let pad2 = (MemoryLayout<UInt64>.size - ((linkedit.fileOffset + newLinkeditData.count) % MemoryLayout<UInt64>.size)) % MemoryLayout<UInt64>.size
        if pad2 != 0 {
            newLinkeditData.append(Data(count: pad2))
        }

        let newSymTabOffset = newLinkeditData.count

        // Copy sym tab
        let newSymTabData = newSymTab.reduce(into: Data(), {
            $0.append($1.data)
        })
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
        let pad3 = (MemoryLayout<UInt64>.size - (newSymNames.count % MemoryLayout<UInt64>.size)) % MemoryLayout<UInt64>.size
        if pad3 != 0 {
            newSymNames.append(Data(count: pad3))
        }

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

        let linkeditFilesize: UInt64 = numericCast(self.symtab!.stroff + self.symtab!.strsize) - linkedit.fileoff
        self.linkedit?.layout.filesize = linkeditFilesize
        self.linkedit?.layout.vmsize = (linkeditFilesize + 4095) & ~UInt64(4095)


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
            try writeHandle.write(
                linkedit.layout,
                at: base + numericCast(linkedit.offset)
            )
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
