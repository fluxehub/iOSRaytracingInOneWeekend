import Foundation
import Metal

class RandomTexture {
    private var descriptor = MTLTextureDescriptor()

    var texture: MTLTexture!

    init() {
        descriptor.pixelFormat = .r32Uint
        descriptor.textureType = .type2D
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
    }

    func resize(device: MTLDevice, width: Int, height: Int) {
        descriptor.width = width
        descriptor.height = height
        texture = device.makeTexture(descriptor: descriptor)

        var randomValues: [Int] = []
        randomValues.reserveCapacity(1024 * 1024)
        for _ in 0..<width*height {
            randomValues.append(Int.random(in: 0..<1024*1024))
        }

        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: randomValues, bytesPerRow: MemoryLayout<Int>.stride * width)
    }
}
