//
//  FixedWidthInteger+.swift
//  dyld-shared-cache-extractor
//
//  Created by p-x9 on 2025/08/19
//
//

import Foundation

extension FixedWidthInteger {
    @inline(__always)
    func alignedUp(to alignment: Self) -> Self {
        precondition(alignment > 0 && (alignment & (alignment &- 1)) == 0, "alignment must be a power of two")
        return (self &+ alignment &- 1) & ~(alignment &- 1)
    }
}
