import Foundation
import Metal

class AccumulationTexture {
    private var textures: [MTLTexture]! = []
    private var previousIndex = 1
    private var currentIndex = 0
    private var descriptor = MTLTextureDescriptor()

    var current: MTLTexture { get { return textures[currentIndex] }}
    var previous: MTLTexture { get { return textures[previousIndex] }}

    init() {
        textures.reserveCapacity(2)
        descriptor.pixelFormat = .rgba32Float
        descriptor.textureType = .type2D
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .shaderWrite]
    }

    func resize(device: MTLDevice, width: Int, height: Int) {
        textures.removeAll(keepingCapacity: true)

        descriptor.width = width
        descriptor.height = height

        for _ in 0..<2 {
            textures.append(device.makeTexture(descriptor: descriptor)!)
        }
    }

    func next() {
        swap(&previousIndex, &currentIndex)
    }
}
