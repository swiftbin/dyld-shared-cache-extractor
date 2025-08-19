//
//  Data+.swift
//  dyld-shared-cache-extractor
//
//  Created by p-x9 on 2025/08/19
//  
//

import Foundation

extension Data {
    mutating func pad(
        toAlignment alignment: Int,
        baseOffset: Int = 0
    ) {
        let current = baseOffset + count
        let aligned = (current + alignment - 1) & ~(alignment - 1)
        let pad = aligned - current
        if pad > 0 {
            append(Data(count: pad))
        }
    }
}
