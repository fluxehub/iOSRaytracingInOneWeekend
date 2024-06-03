import Foundation
import Metal

struct BoundingBox {
    var min: MTLPackedFloat3
    var max: MTLPackedFloat3
}

enum MaterialDescriptor {
    case labertian(color: (r: Float, g: Float, b: Float))
    case metal(albedo: (r: Float, g: Float, b: Float), fuzz: Float)
    case glass(indexOfRefraction: Float)
}

class SceneBuilder {
    private var spheres: [Sphere] = []
    private var boundingBoxes: [BoundingBox] = []

    func addSphere(center: SIMD3<Float>, radius: Float, material: MaterialDescriptor) -> Self {
        let materialStruct = switch material {
        case let .labertian(color):
            Material(lambertian: LambertianMaterial(color: MTLPackedFloat3Make(color.r, color.g, color.b)))
        case let .metal(albedo, fuzz):
            Material(metal: MetalMaterial(albedo: MTLPackedFloat3Make(albedo.r, albedo.g, albedo.b), fuzz: fuzz))
        case let .glass(indexOfRefraction):
            Material(glass: GlassMaterial(indexOfRefraction: indexOfRefraction))
        }

        let materialType = switch material {
        case .labertian: MaterialType(0)
        case .metal: MaterialType(1)
        case .glass: MaterialType(2)
        }

        spheres.append(Sphere(center: MTLPackedFloat3Make(center.x, center.y, center.z),
                              radius: radius,
                              materialType: materialType,
                              material: materialStruct))

        let boundingMin = center - radius
        let boundingMax = center + radius

        boundingBoxes.append(
            // Long day
            BoundingBox(min: MTLPackedFloat3Make(boundingMin.x, boundingMin.y, boundingMin.z),
                        max: MTLPackedFloat3Make(boundingMax.x, boundingMax.y, boundingMax.z)))

        return self
    }

    func build(device: MTLDevice) -> Scene {
        let sphereBuffer = device.makeBuffer(bytes: spheres, length: spheres.count * MemoryLayout<Sphere>.stride, options: .storageModeShared)!
        let boundingBoxBuffer = device.makeBuffer(bytes: boundingBoxes, length: boundingBoxes.count * MemoryLayout<BoundingBox>.stride, options: .storageModeShared)!
        let geometryDescriptor = MTLAccelerationStructureBoundingBoxGeometryDescriptor()
        geometryDescriptor.boundingBoxBuffer = boundingBoxBuffer
        geometryDescriptor.boundingBoxCount = boundingBoxes.count
        geometryDescriptor.primitiveDataBuffer = sphereBuffer
        geometryDescriptor.primitiveDataElementSize = MemoryLayout<Sphere>.size
        geometryDescriptor.primitiveDataStride = MemoryLayout<Sphere>.stride

        return Scene(sphereBuffer: sphereBuffer, boundingBoxBuffer: boundingBoxBuffer, gemoetryDescriptor: geometryDescriptor)
    }
}

class Scene {
    private let sphereBuffer: MTLBuffer
    private let boundingBoxBuffer: MTLBuffer
    let geometryDescriptor: MTLAccelerationStructureGeometryDescriptor

    init(sphereBuffer: MTLBuffer, boundingBoxBuffer: MTLBuffer, gemoetryDescriptor: MTLAccelerationStructureGeometryDescriptor) {
        self.sphereBuffer = sphereBuffer
        self.boundingBoxBuffer = boundingBoxBuffer
        self.geometryDescriptor = gemoetryDescriptor
    }
}
