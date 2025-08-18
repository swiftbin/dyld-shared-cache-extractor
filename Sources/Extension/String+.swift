//
//  String+.swift
//  dyld-shared-cache-extractor
//
//  Created by p-x9 on 2025/08/17
//  
//

import Foundation

extension String: @retroactive LocalizedError {
    public var errorDescription: String? { self }
}
