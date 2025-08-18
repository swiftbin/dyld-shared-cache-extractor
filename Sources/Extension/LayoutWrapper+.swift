//
//  LayoutWrapper+.swift
//  dyld-shared-cache-extractor
//
//  Created by p-x9 on 2025/02/14
//  
//

import Foundation
@_spi(Support) import MachOKit

extension LayoutWrapper {
    var data: Data {
        Self.data(of: layout)
    }

    static func data(of layout: Layout) -> Data {
        var layout = layout
        return withUnsafeBytes(of: &layout) { ptr in
            Data(bytes: ptr.baseAddress!, count: layoutSize)
        }
    }
}
