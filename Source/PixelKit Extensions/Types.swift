//
//  PixelKitTypes.swift
//  PixelKit
//
//  Created by Hexagons on 2018-09-28.
//  Open Source - MIT License
//

import CoreGraphics

public extension PixelKit {
    
    public struct Pixel {
        public let x: Int
        public let y: Int
        public let uv: CGVector
        public let color: LiveColor
    }
    
}
