import AVFoundation
import Foundation

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

/// An interface a screen uses to inform its delegate.
public protocol ScreenDelegate: AnyObject {
    /// Tells the receiver to screen object layout phase.
    func screen(_ screen: Screen, willLayout time: CMTime)
}

/// An object that manages offscreen rendering a foundation.
public final class Screen: ScreenObjectContainerConvertible {
    /// The default screen size.
    public static let size = CGSize(width: 1280, height: 720)

    private static let lockFrags = CVPixelBufferLockFlags(rawValue: 0)
    private static let preferredTimescale: CMTimeScale = 1000000000

    /// The total of child counts.
    public var childCounts: Int {
        return root.childCounts
    }

    /// Specifies the delegate object.
    public weak var delegate: (any ScreenDelegate)?

    /// Specifies the video size to use when output a video.
    public var size: CGSize = Screen.size {
        didSet {
            guard size != oldValue else {
                return
            }
            renderer.bounds = .init(origin: .zero, size: size)
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary?, &pixelBufferPool)
        }
    }

    #if os(macOS)
    /// Specifies the background color.
    public var backgroundColor: CGColor = NSColor.black.cgColor {
        didSet {
            guard backgroundColor != oldValue else {
                return
            }
            renderer.backgroundColor = backgroundColor
        }
    }
    #else
    /// Specifies the background color.
    public var backgroundColor: CGColor = UIColor.black.cgColor {
        didSet {
            guard backgroundColor != oldValue else {
                return
            }
            renderer.backgroundColor = backgroundColor
        }
    }
    #endif

    var videoCaptureLatency: TimeInterval = 0.0
    private(set) var renderer = ScreenRendererByCPU()
    private(set) var targetTimestamp: TimeInterval = 0.0
    private(set) var videoTrackScreenObject = VideoTrackScreenObject()
    private var root: ScreenObjectContainer = .init()
    private var attributes: [NSString: NSObject] {
        return [
            kCVPixelBufferPixelFormatTypeKey: NSNumber(value: kCVPixelFormatType_32ARGB),
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferWidthKey: NSNumber(value: Int(size.width)),
            kCVPixelBufferHeightKey: NSNumber(value: Int(size.height))
        ]
    }
    private var outputFormat: CMFormatDescription?
    private var pixelBufferPool: CVPixelBufferPool? {
        didSet {
            outputFormat = nil
        }
    }
    private var presentationTimeStamp: CMTime = .zero

    /// Creates a screen object.
    public init() {
        try? addChild(videoTrackScreenObject)
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary?, &pixelBufferPool)
    }

    /// Adds the specified screen object as a child of the current screen object container.
    public func addChild(_ child: ScreenObject?) throws {
        try root.addChild(child)
    }

    /// Removes the specified screen object as a child of the current screen object container.
    public func removeChild(_ child: ScreenObject?) {
        root.removeChild(child)
    }

    /// Registers a video effect.
    public func registerVideoEffect(_ effect: some VideoEffect) -> Bool {
        return videoTrackScreenObject.registerVideoEffect(effect)
    }

    /// Unregisters a video effect.
    public func unregisterVideoEffect(_ effect: some VideoEffect) -> Bool {
        return videoTrackScreenObject.unregisterVideoEffect(effect)
    }

    func append(_ track: UInt8, buffer: CMSampleBuffer) {
        let screens: [VideoTrackScreenObject] = root.getScreenObjects()
        for screen in screens where screen.track == track {
            screen.enqueue(buffer)
        }
    }

    func makeSampleBuffer(_ updateFrame: DisplayLinkTime) -> CMSampleBuffer? {
        defer {
            targetTimestamp = updateFrame.targetTimestamp
        }

        // Calculate presentation timestamp
        let presentationTimeStamp = CMTime(
            seconds: updateFrame.timestamp - videoCaptureLatency,
            preferredTimescale: Self.preferredTimescale
        )

        // Frame is too early or out of order — skip
        if self.presentationTimeStamp > presentationTimeStamp {
            return nil
        }

        // Prevent negative or zero durations
        let rawDuration = updateFrame.targetTimestamp - updateFrame.timestamp
        let safeDuration = max(rawDuration, 1.0 / Double(Self.preferredTimescale))

        // Create pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let result = pixelBufferPool?.createPixelBuffer(&pixelBuffer)
        guard result == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        // Setup format description if needed
        if outputFormat == nil {
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &outputFormat
            )
        }
        guard let outputFormat else {
            return nil
        }

        // Propagate buffer attachments
        if let dictionary = CVBufferGetAttachments(pixelBuffer, .shouldNotPropagate) {
            CVBufferSetAttachments(pixelBuffer, dictionary, .shouldPropagate)
        }

        // Store the timestamp after we commit to rendering
        self.presentationTimeStamp = presentationTimeStamp

        // Create sample timing info
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(seconds: safeDuration, preferredTimescale: Self.preferredTimescale),
            presentationTimeStamp: presentationTimeStamp,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: outputFormat,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        guard status == noErr, let buffer = sampleBuffer else {
            return nil
        }

        return render(buffer)
    }

    func render(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer {
        try? sampleBuffer.imageBuffer?.lockBaseAddress(Self.lockFrags)
        defer {
            try? sampleBuffer.imageBuffer?.unlockBaseAddress(Self.lockFrags)
        }
        renderer.presentationTimeStamp = sampleBuffer.presentationTimeStamp
        renderer.setTarget(sampleBuffer.imageBuffer)
        if let dimensions = sampleBuffer.formatDescription?.dimensions {
            root.size = dimensions.size
        }
        delegate?.screen(self, willLayout: sampleBuffer.presentationTimeStamp)
        root.layout(renderer)
        root.draw(renderer)
        return sampleBuffer
    }
}
