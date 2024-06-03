import Foundation
import Metal

class FrameUniforms {
    private let alignedUniformsSize = (MemoryLayout<Uniforms>.size + 0xFF) & ~0xFF

    private var framesInFlight: Int

    private var buffer: MTLBuffer
    private var bufferOffset: Int = 0
    private var bufferIndex: Int = 0
    private var bufferPointer: UnsafeMutablePointer<Uniforms>!

    var current: Uniforms {
        get { bufferPointer.pointee }
        set { bufferPointer.pointee = newValue }
    }

    init(device: MTLDevice, framesInFlight: Int) {
        self.framesInFlight = framesInFlight
        buffer = device.makeBuffer(length: alignedUniformsSize * framesInFlight, options: .storageModeShared)!
        next()
    }

    private func next() {
        bufferOffset = alignedUniformsSize * bufferIndex
        bufferPointer = buffer.contents().advanced(by: bufferOffset).bindMemory(to: Uniforms.self, capacity: alignedUniformsSize)
        bufferIndex = (bufferIndex + 1) % framesInFlight
    }

    func bind(_ encoder: MTLComputeCommandEncoder, index: Int) {
        encoder.setBuffer(buffer, offset: bufferOffset, index: index)
        next()
    }
}
