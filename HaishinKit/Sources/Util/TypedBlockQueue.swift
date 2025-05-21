import CoreMedia
import Foundation

final class TypedBlockQueue<T: AnyObject> {
    private let queue: CMBufferQueue
    private let capacity: CMItemCount

    @inlinable @inline(__always) var head: T? {
        guard let head = queue.head else {
            return nil
        }
        return (head as! T)
    }

    @inlinable @inline(__always) var isEmpty: Bool {
        queue.isEmpty
    }

    @inlinable @inline(__always) var duration: CMTime {
        queue.duration
    }

    init(capacity: CMItemCount, handlers: CMBufferQueue.Handlers) throws {
        self.capacity = capacity
        self.queue = try CMBufferQueue(capacity: capacity, handlers: handlers)
    }

    @inlinable
    @inline(__always)
    func enqueue(_ buffer: T) throws {
        try queue.enqueue(buffer)
    }

    @inlinable
    @inline(__always)
    func dequeue() -> T? {
        guard let value = queue.dequeue() else {
            return nil
        }
        return (value as! T)
    }

    @inlinable
    @inline(__always)
    func reset() throws {
        try queue.reset()
    }
}

extension TypedBlockQueue where T == CMSampleBuffer {
    func dequeue(_ presentationTimeStamp: CMTime) -> CMSampleBuffer? {
        var best: CMSampleBuffer? = nil
        let tolerance = CMTimeMake(value: 1, timescale: 10) // ~1/10 s
        var maxDif = CMTimeMake(value: 0, timescale: 1)
        while !queue.isEmpty {
            guard let head else { break }
            if !head.isValid {
                _ = dequeue()
                continue
            }
            if head.presentationTimeStamp <= presentationTimeStamp {
                if presentationTimeStamp - head.presentationTimeStamp <= tolerance {
                    best = dequeue() // Fresh enough
                } else {
                    _ = dequeue() // Too old, discard
                }
            } else {
                break
            }
        }
        
        return best
    }
}
