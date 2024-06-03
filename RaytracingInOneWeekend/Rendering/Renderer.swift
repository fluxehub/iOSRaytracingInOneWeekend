import Foundation
import Metal
import MetalKit

class Renderer: NSObject, MTKViewDelegate {
    private let framesInFlight = 3
    private let alignedUniformsSize = (MemoryLayout<Uniforms>.size + 0xFF) & ~0xFF

    private var device: MTLDevice
    private var semaphore: DispatchSemaphore
    private var commandQueue: MTLCommandQueue

    private var raytracingPipeline: MTLComputePipelineState
    private var intersectionFunctionTable: MTLIntersectionFunctionTable
    private var raytracingThreadsPerThreadgroup: MTLSize
    private var raytracingThreads = MTLSize()
    private var displayPipeline: MTLRenderPipelineState

    private var uniforms: FrameUniforms

    private var width: Int = 0
    private var height: Int = 0
    private var scene: Scene
    private var accelerationStructure: MTLAccelerationStructure

    private var target = AccumulationTexture()
    private var randomTexture = RandomTexture()
    
    var frameIndex: UInt32 = 0
    var camera: Camera

    init(device: MTLDevice, scene sceneBuilder: SceneBuilder, camera: Camera) {
        self.device = device
        semaphore = DispatchSemaphore(value: framesInFlight)
        commandQueue = device.makeCommandQueue()!
        uniforms = FrameUniforms(device: device, framesInFlight: framesInFlight)
        scene = sceneBuilder.build(device: device)
        self.camera = camera

        scene.geometryDescriptor.intersectionFunctionTableOffset = 0;
        accelerationStructure = Renderer.makeAccelerationStructure(device: device, commandQueue: commandQueue, descriptor: scene.geometryDescriptor)

        let defaultLibrary = device.makeDefaultLibrary()!

        (raytracingPipeline, intersectionFunctionTable, raytracingThreadsPerThreadgroup) = Renderer.makeRaytracingPipeline(device: device, library: defaultLibrary)
        displayPipeline = Renderer.makeRenderPipeline(device: device, library: defaultLibrary)
    }

    private static func makeRaytracingPipeline(device: MTLDevice, library: MTLLibrary) -> (MTLComputePipelineState, MTLIntersectionFunctionTable, MTLSize) {
        let intersectionFunction = library.makeFunction(name: "sphereIntersection")!
        let traceFunction = library.makeFunction(name: "trace")!

        let linkedFunctions = MTLLinkedFunctions()
        linkedFunctions.functions = [intersectionFunction]

        let pipelineDesc = MTLComputePipelineDescriptor()
        pipelineDesc.computeFunction = traceFunction
        pipelineDesc.linkedFunctions = linkedFunctions
        let (pipeline, _) = try! device.makeComputePipelineState(descriptor: pipelineDesc, options: [])

        let tableDesc = MTLIntersectionFunctionTableDescriptor()
        tableDesc.functionCount = 1
        let functionHandle = pipeline.functionHandle(function: intersectionFunction)!
        let intersectionFunctionTable = pipeline.makeIntersectionFunctionTable(descriptor: tableDesc)!
        intersectionFunctionTable.setFunction(functionHandle, index: 0)

        let threadW = pipeline.threadExecutionWidth
        let threadH = pipeline.maxTotalThreadsPerThreadgroup / threadW
        let threadsPerThreadgroup = MTLSize(width: threadW, height: threadH, depth: 1)

        return (pipeline, intersectionFunctionTable, threadsPerThreadgroup)
    }

    private static func makeRenderPipeline(device: MTLDevice, library: MTLLibrary) -> MTLRenderPipelineState {
        let vertexProgram = library.makeFunction(name: "drawQuad")!
        let fragmentProgram = library.makeFunction(name: "drawTexture")!

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = vertexProgram
        pipelineDesc.fragmentFunction = fragmentProgram
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm

        return try! device.makeRenderPipelineState(descriptor: pipelineDesc)
    }

    private static func makeAccelerationStructure(device: MTLDevice, commandQueue: MTLCommandQueue, descriptor: MTLAccelerationStructureGeometryDescriptor) -> MTLAccelerationStructure {
        let accelerationDesc = MTLPrimitiveAccelerationStructureDescriptor()
        accelerationDesc.geometryDescriptors = [descriptor]

        let accelerationBufferSizes = device.accelerationStructureSizes(descriptor: accelerationDesc)
        let accelerationStructure = device.makeAccelerationStructure(size: accelerationBufferSizes.accelerationStructureSize)!
        let scratchBuffer = device.makeBuffer(length: accelerationBufferSizes.buildScratchBufferSize, options: .storageModePrivate)!
        var commandBuffer = commandQueue.makeCommandBuffer()!
        var commandEncoder = commandBuffer.makeAccelerationStructureCommandEncoder()!
        let compactedSizeBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared)!

        commandEncoder.build(accelerationStructure: accelerationStructure, descriptor: accelerationDesc, scratchBuffer: scratchBuffer, scratchBufferOffset: 0)
        commandEncoder.writeCompactedSize(accelerationStructure: accelerationStructure, buffer: compactedSizeBuffer, offset: 0)
        commandEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let compactedSize = compactedSizeBuffer.contents().load(as: UInt32.self)
        let compactedAccelerationStructure = device.makeAccelerationStructure(size: Int(compactedSize))!
        commandBuffer = commandQueue.makeCommandBuffer()!
        commandEncoder = commandBuffer.makeAccelerationStructureCommandEncoder()!

        commandEncoder.copyAndCompact(sourceAccelerationStructure: accelerationStructure, destinationAccelerationStructure: compactedAccelerationStructure)
        commandEncoder.endEncoding()
        commandBuffer.commit()

        return compactedAccelerationStructure
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        width = Int(size.width)
        height = Int(size.height)

        raytracingThreads = MTLSize(width: width, height: height, depth: 1)

        camera.setViewport(width: Float(width), height: Float(height))
        target.resize(device: device, width: width, height: height)
        randomTexture.resize(device: device, width: width, height: height)
        frameIndex = 0
    }

    private func updateUniforms() {
        camera.setUniforms(uniforms: &uniforms.current)

        uniforms.current.width = Float(width)
        uniforms.current.height = Float(height)
        uniforms.current.frame = frameIndex
        frameIndex += 1
    }

    private func renderScene(commandBuffer: MTLCommandBuffer) {
        let encoder = commandBuffer.makeComputeCommandEncoder()!

        encoder.setComputePipelineState(raytracingPipeline)
        encoder.setAccelerationStructure(accelerationStructure, bufferIndex: 1)
        encoder.setIntersectionFunctionTable(intersectionFunctionTable, bufferIndex: 2)
        encoder.setTexture(randomTexture.texture, index: 0)
        encoder.setTexture(target.previous, index: 1)
        encoder.setTexture(target.current, index: 2)
        uniforms.bind(encoder, index: 0)

        encoder.dispatchThreads(raytracingThreads, threadsPerThreadgroup: raytracingThreadsPerThreadgroup)
        encoder.endEncoding()
    }

    private func copyToDisplay(commandBuffer: MTLCommandBuffer, view: MTKView) {
        guard let drawable = view.currentDrawable else { return }

        let renderDesc = MTLRenderPassDescriptor()
        renderDesc.colorAttachments[0].texture = drawable.texture
        renderDesc.colorAttachments[0].loadAction = .clear
        renderDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)

        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDesc)!

        encoder.setRenderPipelineState(displayPipeline)
        encoder.setFragmentTexture(target.current, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()

        commandBuffer.present(drawable, afterMinimumDuration: 1.0 / Double(view.preferredFramesPerSecond))
    }

    func draw(in view: MTKView) {
        semaphore.wait()

        let commandBuffer = commandQueue.makeCommandBuffer()!
        commandBuffer.addCompletedHandler { _ in
            self.semaphore.signal()
        }

        updateUniforms()

        renderScene(commandBuffer: commandBuffer)
        copyToDisplay(commandBuffer: commandBuffer, view: view)

        commandBuffer.commit()

        target.next()
    }
}
