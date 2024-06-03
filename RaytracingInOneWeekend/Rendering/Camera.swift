import Foundation

// Based off https://www.mbsoftworks.sk/tutorials/opengl4/026-camera-pt3-orbit-camera/
class Camera {
    private var lookFrom: simd_float3
    private var lookAt: simd_float3
    private var fov: Float
    private var width: Float = 0.0
    private var height: Float = 0.0
    private var aspectRatio: Float = 0.0
    
    private var orbitRadius: Float
    private var azimuth: Float
    private var polar: Float
    
    private var defocusAngle: Float
    private var focusDistance: Float
    
    init(lookFrom: simd_float3, lookAt: simd_float3, fov: Float, defocusAngle: Float, focusDistance: Float) {
        self.lookFrom = lookFrom
        self.lookAt = lookAt
        
        let c = lookFrom - lookAt
        self.orbitRadius = length(c)
        self.azimuth = acosf(c.x / sqrtf(powf(c.x, 2) + powf(c.y, 2)))
        self.polar = c.z / orbitRadius
        
        self.fov = fov
        
        self.defocusAngle = defocusAngle
        self.focusDistance = focusDistance
        self.updateLookFrom()
    }
    
    func setViewport(width: Float, height: Float) {
        self.width = width
        self.height = height
        self.aspectRatio = self.width / self.height
    }
    
    func rotateAzimuth(radians: Float) {
        azimuth += radians
    }
    
    func rotatePolar(radians: Float) {
        polar += radians
        
        let polarCap: Float = .pi / 2.0 - 0.001
        if polar > polarCap {
            polar = polarCap
        } else if polar < 0.1 {
            polar = 0.1
        }
    }
    
    func updateLookFrom() {
        let sinAzimuth = sin(azimuth)
        let cosAzimuth = cos(azimuth)
        let sinPolar = sin(polar)
        let cosPolar = cos(polar)
        
        let newX = lookAt.x + orbitRadius * cosPolar * cosAzimuth
        let newY = lookAt.y + orbitRadius * sinPolar
        let newZ = lookAt.z + orbitRadius * cosPolar * sinAzimuth
        lookFrom = simd_float3(newX, newY, newZ)
    }
    
    func rotate(azimuth: Float, polar: Float) {
        rotateAzimuth(radians: azimuth)
        rotatePolar(radians: polar)
        
        updateLookFrom()
    }
    
    func zoom(by deltaR: Float) {
        orbitRadius += deltaR
        if orbitRadius < 1.0 {
            orbitRadius = 1.0
        }
        
        updateLookFrom()
    }
    
    func setUniforms(uniforms: inout Uniforms) {
        if width == 0.0 || height == 0.0 {
            return
        }
        
        let up = simd_float3(0.0, 1.0, 0.0)
        let theta: Float = fov * .pi / 180.0
        let h = tan(theta / 2.0)
        let viewportHeight: Float = 2.0 * h * orbitRadius
        let viewportWidth = viewportHeight * aspectRatio
        let cameraCenter = lookFrom
        
        let w = normalize(lookFrom - lookAt)
        let u = normalize(cross(up, w))
        let v = cross(w, u)
        
        // Create the vectors across the horizontal and down the vertical viewport edges
        let viewportU = viewportWidth * u
        let viewportV = viewportHeight * v
        
        let pixelDeltaU = viewportU / width
        let pixelDeltaV = viewportV / height
        
        // Calculate the location of the upper left pixel
        let viewportUpperLeft = cameraCenter - orbitRadius * w - viewportU / 2.0 - viewportV / 2.0;
        let pixel00Loc = viewportUpperLeft + 0.5 * (pixelDeltaU + pixelDeltaV)
        
        let defocusRadius = orbitRadius * tan(defocusAngle * .pi / 180.0)
        
        uniforms.cameraCenter = lookFrom
        uniforms.pixelDeltaU = pixelDeltaU
        uniforms.pixelDeltaV = pixelDeltaV
        uniforms.pixel00Loc = pixel00Loc
        uniforms.defocusDiscU = u * defocusRadius
        uniforms.defocusDiscV = v * defocusRadius
    }
}
