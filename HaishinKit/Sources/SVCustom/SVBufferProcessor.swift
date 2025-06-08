//
//  File.swift
//  HaishinKit
//
//  Created by Peter P. on 08/06/2025.
//

import Foundation
import CoreMedia

open class SVBufferProcessor {
    
    static public nonisolated(unsafe) var current: SVBufferProcessor?
    
    open func process(sampleBuffer: CMSampleBuffer) -> (mainSampleBuffer: CMSampleBuffer, previewSampleBuffer: CMSampleBuffer)? {
        return (mainSampleBuffer: sampleBuffer, previewSampleBuffer: sampleBuffer)
    }
    
    public init() {}
    
}
