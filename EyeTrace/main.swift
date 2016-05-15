//
//  main.swift
//  EyeTrace
//
//  Created by Manuel Broncano Rodriguez on 5/14/16.
//  Copyright © 2016 Manuel Broncano Rodriguez. All rights reserved.
//

import Foundation
import simd

/// Basic math definitions
typealias Scalar = Double
typealias Vector = double3
extension Vector {
    static let Zero = Vector()
    static let One = Vector(1, 1, 1)

    func length() -> Scalar { return simd.length(self) }
    func normalize() -> Vector { return simd.normalize(self) }
}

/// Ray definition
class Ray {
    let origin: Vector
    let direction: Vector

    init() { self.origin = Vector.Zero; self.direction = Vector.Zero }
    init(origin: Vector, direction: Vector) { self.origin = origin; self.direction = direction }
    func pointAtParameter(t: Scalar) -> Vector { return origin + direction * t }
}

/// Intersection
class HitRecord {
    var t: Scalar = 0
    var p: Vector = Vector.Zero
    var normal: Vector = Vector.Zero
    var material: Material? = nil
    
    init() { }
}

/// Used for objects that can be hit by a ray
/// We use an inout parameter to avoid allocation over the for loop
protocol Hitable {
    func hit(ray: Ray, tMin: Scalar, tMax: Scalar, inout hitRecord: HitRecord) -> Bool
}

/// Geometry
class Sphere: Hitable {
    let center: Vector
    let radius: Scalar
    let material: Material
    
    init(center: Vector, radius: Scalar, material: Material) {
        self.center = center
        self.radius = radius
        self.material = material
    }

    func hit(ray: Ray, tMin: Scalar, tMax: Scalar, inout hitRecord: HitRecord) -> Bool {
        let oc = ray.origin - center
        let a = simd.dot(ray.direction, ray.direction)
        let b = simd.dot(oc, ray.direction)
        let c = simd.dot(oc, oc) - radius*radius
        let discriminant = b*b-a*c
        if discriminant > 0 {
            var temp = (-b-sqrt(discriminant))/a
            if temp < tMax && temp > tMin {
                hitRecord.t = temp
                hitRecord.p = ray.pointAtParameter(hitRecord.t)
                hitRecord.normal = (hitRecord.p - center) * (1.0 / radius)
                hitRecord.material = material
                return true
            }
            temp = (-b+sqrt(discriminant))/a
            if temp < tMax && temp > tMin {
                hitRecord.t = temp
                hitRecord.p = ray.pointAtParameter(hitRecord.t)
                hitRecord.normal = (hitRecord.p - center) * (1.0 / radius)
                hitRecord.material = material
                return true
            }
        }
        return false
    }
}

/// List of geometric objects
class HitableList: Hitable {
    let list: [Hitable]
    
    init(list: [Hitable]) { self.list = list }
    
    func hit(ray: Ray, tMin: Scalar, tMax: Scalar, inout hitRecord: HitRecord) -> Bool {
        var hitAnything = false
        var tempRecord = HitRecord()
        var closestSoFar = tMax
        for item in list {
            if item.hit(ray, tMin: tMin, tMax: closestSoFar, hitRecord: &tempRecord) {
                hitAnything = true
                closestSoFar = tempRecord.t
                hitRecord = tempRecord
            }
        }
        return hitAnything
    }
}

/// Camera and ray factory
struct Camera {
    let origin: Vector
    let lowerLeftCorner: Vector
    let horizontal: Vector
    let vertical: Vector
    
    func getRay(u u: Scalar, v: Scalar) -> Ray {
        return Ray(origin: origin, direction: lowerLeftCorner + u * horizontal + v * vertical)
    }
}

/// Random unit sphere sample, rejection method
func randomInUnitSphere() -> Vector {
    var p = Vector()
    repeat {
        p = 2.0 * Vector(drand48(), drand48(), drand48()) - Vector.One
    } while  simd.length_squared(p) >= 1.0
    return p
}


/// Defined for materials
protocol Material {
    func scatter(ray: Ray, hitRecord: HitRecord, inout attenuation: Vector, inout scattered: Ray) -> Bool
}

/// Diffuse material
class Lambertian: Material {
    let albedo: Vector
    
    init(albedo: Vector) {
        self.albedo = albedo
    }
    
    func scatter(ray: Ray, hitRecord: HitRecord, inout attenuation: Vector, inout scattered: Ray) -> Bool {
        let target = hitRecord.p + hitRecord.normal + randomInUnitSphere()
        scattered = Ray(origin: hitRecord.p, direction: target - hitRecord.p)
        attenuation = albedo
        return true
    }
}

/// Reflective material
class Metal: Material {
    let albedo: Vector
    let fuzz: Scalar

    init(albedo: Vector, fuzz: Double) { self.albedo = albedo; self.fuzz = fuzz }
    
    func scatter(ray: Ray, hitRecord: HitRecord, inout attenuation: Vector, inout scattered: Ray) -> Bool {
        let reflected = simd.reflect(ray.direction.normalize(), n: hitRecord.normal)
        scattered = Ray(origin: hitRecord.p, direction: reflected + fuzz * randomInUnitSphere())
        attenuation = albedo
        return (simd.dot(scattered.direction, hitRecord.normal)) > 0
    }
}


/// Computes a color for a ray
func color(ray: Ray, world: Hitable, depth: Int) -> Vector {
    var hitRecord = HitRecord()
    if world.hit(ray, tMin: 0.001, tMax: Scalar.infinity, hitRecord: &hitRecord) {
        var scattered: Ray = Ray()
        var attenuation: Vector = Vector()
        
        if depth > 0 && (hitRecord.material?.scatter(ray, hitRecord: hitRecord, attenuation: &attenuation, scattered: &scattered))! {
            return attenuation * color(scattered, world: world, depth: depth-1)
        } else {
            return Vector()
        }

    } else {
        // background, sky color is blended blue and white
        let unitDirection = ray.direction.normalize()
        let t = 0.5 * (unitDirection.y + 1)
        return (1 - t) * Vector(1, 1, 1) + t * Vector(0.5, 0.7, 1.0)
    }
}


func writeImage(nx: Int, ny: Int, framebuffer: [Vector]) {
    print("P3\n\(nx) \(ny) \n255")

    for col in framebuffer.reverse() {
        // gamma correction
        let ir = Int(255.99*sqrt(col[0]))
        let ig = Int(255.99*sqrt(col[1]))
        let ib = Int(255.99*sqrt(col[2]))

        print("\(ir) \(ig) \(ib)")
    }
}

// Main function
let nx = 400
let ny = 200
let ns = 32
let depth = 8


let camera = Camera(origin: Vector(), lowerLeftCorner: Vector(-2, -1, -1), horizontal: Vector(4, 0, 0), vertical: Vector(0, 2, 0))

let world = HitableList(list: [
    Sphere(center: Vector(0, 0, -1), radius: 0.5, material: Lambertian(albedo: Vector(0.8, 0.3, 0.3))),
    Sphere(center: Vector(0, -100.5, -1), radius: 100, material: Lambertian(albedo: Vector(0.8, 0.8, 0.0))),
    Sphere(center: Vector(1, 0, -1), radius: 0.5, material: Metal(albedo: Vector(0.8, 0.6, 0.2), fuzz: 0.8)),
    Sphere(center: Vector(-1, 0, -1), radius: 0.5, material: Metal(albedo: Vector(0.8, 0.8, 0.8), fuzz: 0.3))
    ])

var framebuffer = [Vector](count: nx*ny, repeatedValue: Vector())

let group = dispatch_group_create()

for j in 0..<ny {
    dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), {
        for i in 0..<nx {
            
            var col = Vector()
            
            for s in 0..<ns {
                let u = (Scalar(i) + drand48()) / Scalar(nx)
                let v = (Scalar(j) + drand48()) / Scalar(ny)
                
                let ray = camera.getRay(u: u, v: v)
                col = col + color(ray, world: world, depth: depth)
            }
            
            col = col * (1.0 / Scalar(ns))
            
            framebuffer[j*nx+i] = col
        }
    })
}

dispatch_group_wait(group, DISPATCH_TIME_FOREVER)

writeImage(nx, ny: ny, framebuffer: framebuffer)

