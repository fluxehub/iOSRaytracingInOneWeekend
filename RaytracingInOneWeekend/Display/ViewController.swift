import UIKit
import Metal
import MetalKit

class ViewController: UIViewController {
    var metalView: MTKView!
    var renderer: Renderer!

    var panCenter: CGPoint = .zero

    override func viewDidLoad() {
        super.viewDidLoad()

        metalView = self.view as? MTKView
        metalView.device = MTLCreateSystemDefaultDevice()
        metalView.backgroundColor = .black
        metalView.preferredFramesPerSecond = 120
        assert(metalView.device!.supportsRaytracing, "Ray tracing is not supported")

        let scene = SceneBuilder()
            .addSphere(center: simd_float3(0.0, -1000.0, 0.0), radius: 1000.0, material: .labertian(color: (r: 0.5, g: 0.5, b: 0.5)))

        for a in -21..<21 {
            for b in -21..<21 {
                let chooseMat = Float.random(in: 0...1)
                let center = simd_float3(Float(a) + 0.9 * Float.random(in: 0...1), 0.2, Float(b) + 0.9 * Float.random(in: 0...1))

                if length(center - simd_float3(4.0, 0.2, 0)) > 0.9 {
                    if chooseMat < 0.8 {
                        // Diffuse
                        let albedo = simd_float3(Float.random(in: 0.0...1.0), Float.random(in: 0.0...1.0), Float.random(in: 0.0...1.0)) * simd_float3(Float.random(in: 0...1), Float.random(in: 0.0...1.0), Float.random(in: 0...1.0))
                        _ = scene.addSphere(center: center, radius: 0.2, material: .labertian(color: (r: albedo.x, g: albedo.y, b: albedo.z)))
                    } else if chooseMat < 0.95 {
                        let albedo = simd_float3(Float.random(in: 0.5...1.0), Float.random(in: 0.5...1.0), Float.random(in: 0.5...1.0))
                        let fuzz = Float.random(in: 0...0.5)
                        _ = scene.addSphere(center: center, radius: 0.2, material: .metal(albedo: (r: albedo.x, g: albedo.y, b: albedo.z), fuzz: fuzz))
                    } else {
                        _ = scene.addSphere(center: center, radius: 0.2, material: .glass(indexOfRefraction: 1.5))
                    }
                }
            }
        }

        _ = scene
            .addSphere(center: simd_float3(0.0, 1.0, 0.0), radius: 1.0, material: .glass(indexOfRefraction: 1.5))
            .addSphere(center: simd_float3(-4.0, 1.0, 0.0), radius: 1.0, material: .labertian(color: (r: 0.4, g: 0.2, b: 0.1)))
            .addSphere(center: simd_float3(4.0, 1.0, 0.0), radius: 1.0, material: .metal(albedo: (r: 0.7, g: 0.6, b: 0.5), fuzz: 0.0))

        let camera = Camera(lookFrom: simd_float3(13.0, 2.0, 3.0), lookAt: simd_float3(0.0, 0.5, 0.0), fov: 45.0, defocusAngle: 0.3, focusDistance: 10.0)
        renderer = Renderer(device: metalView.device!, scene: scene, camera: camera)
        renderer.mtkView(metalView, drawableSizeWillChange: view.bounds.size)

        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(didPan(_:)))
        let zoomGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(didZoom(_:)))

        self.metalView.addGestureRecognizer(panGestureRecognizer)
        self.metalView.addGestureRecognizer(zoomGestureRecognizer)

        metalView.delegate = renderer
    }

    @objc private func didPan(_ sender: UIPanGestureRecognizer) {
        switch sender.state {
        case .began:
            panCenter = sender.location(in: metalView)
        case .changed:
            let location = sender.location(in: metalView)
            let x = Float((location.x - panCenter.x) / view.bounds.width) / 8.0
            let y = Float((location.y - panCenter.y) / view.bounds.height) / 8.0
            renderer.camera.rotate(azimuth: x, polar: y)
            renderer.frameIndex = 0
        default:
            break
        }
    }

    @objc private func didZoom(_ sender: UIPinchGestureRecognizer) {
        renderer.camera.zoom(by: -Float(sender.velocity / 4.0))
        renderer.frameIndex = 0
    }
}
