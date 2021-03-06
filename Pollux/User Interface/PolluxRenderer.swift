//
//  PolluxRenderer.swift
//  Pollux
//
//  Created by Youssef Kamal Victor on 11/8/17.
//  Copyright © 2017 Youssef Victor. All rights reserved.
//

import Metal
import MetalKit
import simd

class PolluxRenderer: NSObject {
    // View this renderer writes to
    private let view : MTKView
    
    // Data Alignment
    private let alignment  : Int = 0x4000
    // Reference to the GPU essentially
    let device: MTLDevice
    // Default GPU Library
    private let defaultLibrary: MTLLibrary
    // The command Queue from which we'll obtain command buffers
    private let commandQueue: MTLCommandQueue!
    
    // Clear Color
    private let bytesPerRow : Int
    private var region : MTLRegion
    private let blankBitmapRawData : [UInt8]
    
    // The iteration the renderer is on
    var iteration : Int = 0
    
    /****
    **
    **  GPU Kernels / Shader Stages
    **
    *****/
    private var threadsPerThreadgroup:MTLSize!
    private var threadgroupsPerGrid:MTLSize!
    
    // Our compute pipeline is analogous to a shader stage
    private var ps_GenerateRaysFromCamera: MTLComputePipelineState!;
    private var kern_GenerateRaysFromCamera: MTLFunction!
    
    private var ps_ComputeIntersections: MTLComputePipelineState!;
    private var kern_ComputeIntersections: MTLFunction!
    
//    private var rayCompactor : Partition<Ray>!
    
    private var ps_ShadeMaterials: MTLComputePipelineState!;
    private var kern_ShadeMaterials: MTLFunction!
    
    private var ps_FinalGather: MTLComputePipelineState!;
    private var kern_FinalGather: MTLFunction!
    
    
    /*****
    **
    **  Rays Shared Buffer
    **
    ******/
    let rays : DeviceBuffer<Ray>
//    var frame_ray_count : Int
    
    /*****
     **
     **  Geoms Shared Buffer
     **
     ******/
    let geoms         : DeviceBuffer<Geom>
    var light_count   : UInt32
    let kdtrees       : SharedBuffer<Float>
    
    /*****
     **
     **  Materials Shared Buffer
     **
     ******/
    let materials      : DeviceBuffer<Material>
    
    /*****
     **
     **  Intersections Shared Buffer
     **
     ******/
    let intersections : DeviceBuffer<Intersection>
    
    /*****
     **
     **  Camera & Camera Buffer
     **
     ******/
    var camera       : Camera
    
    /*****
     **
     **  Frame Shared Buffer
     **
     ******/
    let frame : DeviceBuffer<float4>
    
    /*****
     **
     **  Simulation Variable(s)
     **
     ******/
    var max_depth : UInt;
    
    /*****
     **
     ** Environment
     **
     *****/
    var environment : DeviceTexture?
    var envEmittance : float3
    
    /*****
     **
     **  CPU/GPU Synchronization Stuff
     **
     ******/
    // MARK: SEMAPHORE CODE - Initialization
//    let iterationSemaphore : DispatchSemaphore = DispatchSemaphore(value: Int(MaxBuffers))
    
    
    /// Initialize with the MetalKit view from which we'll obtain our Metal device.  We'll also use this
    /// mtkView object to set the pixelformat and other properties of our drawable
    init(in mtkView: MTKView, with scene: Scene) {
        self.view = mtkView
        self.device = mtkView.device!;
        self.commandQueue = device.makeCommandQueue();
        self.defaultLibrary = device.makeDefaultLibrary()!
        
        // Tell the MTKView that we want to use other buffers to draw
        // (needed for displaying from our own texture)
        mtkView.framebufferOnly = false
        
        // Indicate we would like to use the RGBAPisle format.
        mtkView.colorPixelFormat = .bgra8Unorm
        
        //Some Other Stuff
        mtkView.sampleCount = 1
        mtkView.preferredFramesPerSecond = 60

        let width  = Float(mtkView.drawableSize.width)
        let height = Float(mtkView.drawableSize.height)
        let ray_count = width * height
        
        // For Clearing the Frame Buffer
        self.bytesPerRow = Int(4 * width)
        self.region = MTLRegionMake2D(0, 0, Int(width), Int(height))
        self.blankBitmapRawData = [UInt8](repeating: 0, count: Int(ray_count * 4))
        
        // Initialize Camera:
        self.camera = scene.0
        camera.data.x = width
        camera.data.y = height
        self.max_depth = UInt(camera.data[3])
        
        self.rays          = DeviceBuffer<Ray>(count: Int(ray_count), with: device)
        self.geoms         = DeviceBuffer<Geom>(count: scene.1.count, with: device, containing: scene.1, blitOn: self.commandQueue)
        self.kdtrees       = SharedBuffer<Float>(count: scene.5.count, with:device, containing: scene.5 /**, blitOn: self.commandQueue**/)
        self.materials     = DeviceBuffer<Material>(count: scene.3.count, with: device, containing: scene.3, blitOn: self.commandQueue)
        self.frame         = DeviceBuffer<float4>(count: self.rays.count, with: self.device)
        self.intersections = DeviceBuffer<Intersection>(count: self.rays.count, with: self.device)
        if let environment = scene.4 {
            self.environment   = DeviceTexture(from: environment.filename as String, with: device)
            self.envEmittance  = environment.emittance
        } else {
            self.envEmittance  = float3(0, 0, 0)
        }
        self.light_count   = scene.2
        
        super.init()
        
        // Sets up the Compute Pipeline that we'll be working with
        self.setupComputePipeline()
    }
    
    private func setupComputePipeline() {
        // Create Pipeline State for RayGenereration from Camera
        self.kern_GenerateRaysFromCamera = defaultLibrary.makeFunction(name: "kern_GenerateRaysFromCamera")
        do    { try ps_GenerateRaysFromCamera = device.makeComputePipelineState(function: kern_GenerateRaysFromCamera)}
        catch { fatalError("generateRaysFromCamera computePipelineState failed")}
        
        // Create Pipeline State for ComputeIntersection
        self.kern_ComputeIntersections = defaultLibrary.makeFunction(name: "kern_ComputeIntersections")
        do    { try ps_ComputeIntersections = device.makeComputePipelineState(function: kern_ComputeIntersections)}
        catch { fatalError("ComputeIntersections computePipelineState failed") }
        
        // Create Pipeline State for ShadeMaterials
        self.kern_ShadeMaterials = defaultLibrary.makeFunction(name: "kern_ShadeMaterials" + integrator)
        do    { try ps_ShadeMaterials = device.makeComputePipelineState(function: kern_ShadeMaterials)}
        catch { fatalError("ShadeMaterials computePipelineState failed") }
        
        // Create Pipeline State for Ray Stream Compaction
//        self.rayCompactor = Partition<Ray>(on: device,
//                                                 with: defaultLibrary,
//                                                 applying: "kern_EvaluateRays")
        
        // Create Pipeline State for Final Gather
        self.kern_FinalGather = defaultLibrary.makeFunction(name: "kern_FinalGather")
        do    { try ps_FinalGather = device.makeComputePipelineState(function: kern_FinalGather)}
        catch { fatalError("FinalGather computePipelineState failed ") }
    }
}


extension PolluxRenderer {
    fileprivate func updateThreadGroups(for stage: PipelineStage) {
        // If we are currently generating rays or coloring the buffer,
        // Set up the threadGroups to loop over all pixels in the image (2D)
        if stage == GENERATE_RAYS {
            let w = ps_GenerateRaysFromCamera.threadExecutionWidth
            let h = ps_GenerateRaysFromCamera.maxTotalThreadsPerThreadgroup / w
            self.threadsPerThreadgroup = MTLSizeMake(w, h, 1)
            
            let widthInt  = Int(self.camera.data.x)
            let heightInt = Int(self.camera.data.y)
            self.threadgroupsPerGrid = MTLSize(width:  (widthInt + w - 1) / w,
                                               height: (heightInt + h - 1) / h,
                                               depth: 1)
        }
        // If we are currently computing the ray intersections, or shading those intersections,
        // Set up the threadgroups to go over all available rays (1D)
        else if stage == COMPUTE_INTERSECTIONS || stage == SHADE || stage == FINAL_GATHER {
            let warp_size = ps_ComputeIntersections.threadExecutionWidth
            self.threadsPerThreadgroup = MTLSize(width: min(self.rays.count, warp_size),height:1,depth:1)
            self.threadgroupsPerGrid   = MTLSize(width: max(self.rays.count / warp_size,1), height:1, depth:1)
        }
    }
    
    fileprivate func setBuffers(for stage: PipelineStage, using commandEncoder: MTLComputeCommandEncoder) {
        switch (stage) {
        case GENERATE_RAYS:
            commandEncoder.setBytes(&self.camera, length: MemoryLayout<Camera>.size, index: 0)
            commandEncoder.setBytes(&self.max_depth, length: MemoryLayout<UInt>.size, index: 1)
            commandEncoder.setBuffer(self.rays.data, offset: 0, index: 2)
            commandEncoder.setBytes(&self.iteration,  length: MemoryLayout<Int>.size, index: 3)
        case COMPUTE_INTERSECTIONS:
            commandEncoder.setBytes(&self.rays.count, length: MemoryLayout<Int>.size, index: 0)
            commandEncoder.setBytes(&self.geoms.count,  length: MemoryLayout<Int>.size, index: 1)
//            commandEncoder.setBuffer(self.rays.data, offset: 0, index: 2)
            commandEncoder.setBuffer(self.intersections.data, offset: 0, index: 3)
            commandEncoder.setBuffer(self.geoms.data        , offset: 0, index: 4)
            commandEncoder.setBuffer(self.kdtrees.data      , offset: 0, index: 5)
            break;
        case SHADE:
            // Buffer (0) is already set
            commandEncoder.setBytes(&self.iteration,  length: MemoryLayout<Int>.size, index: 1)
            // Buffer (2) is already set
            // Buffer (3) is already set
            commandEncoder.setBuffer(self.materials.data, offset: 0, index: 4)
            // Buffer (5) is already set
            commandEncoder.setTexture(self.environment?.data ?? self.view.currentDrawable?.texture, index: 5)
            commandEncoder.setBytes(&self.envEmittance, length: MemoryLayout<float3>.size, index: 6)
            
            if (integrator == "MIS" || integrator == "Direct") {
                if (integrator == "MIS") {
                    commandEncoder.setBytes(&self.max_depth,  length: MemoryLayout<UInt>.size, index: 7)
                }
                commandEncoder.setBuffer(self.geoms.data, offset: 0, index: 8)
                commandEncoder.setBytes(&self.geoms.count,  length: MemoryLayout<Int>.size, index: 9)
                commandEncoder.setBytes(&self.light_count,  length: MemoryLayout<UInt32>.size, index: 10)
            }
            break;
            
        case FINAL_GATHER:
//            commandEncoder.setBytes(&self.camera, length: MemoryLayout<Camera>.size, index: 0)
//            commandEncoder.setBytes(&self.iteration, length: MemoryLayout<UInt>.size, index: 1)
//            commandEncoder.setBuffer(self.rays.data, offset: 0, index: 2)
            commandEncoder.setBuffer(self.frame.data, offset: 0, index: 3)
            commandEncoder.setBytes(&self.camera, length: MemoryLayout<Camera>.size, index: 4)
            commandEncoder.setTexture(self.view.currentDrawable?.texture , index: 4)
            break;
         default:
            fatalError("Undefined Pipeline Stage Passed to SetBuffers")
        }
    }
    
    fileprivate func dispatchPipelineState(for stage: PipelineStage,using commandEncoder: MTLComputeCommandEncoder) {
        setBuffers(for: stage, using: commandEncoder);
        updateThreadGroups(for: stage);
        switch (stage) {
            case GENERATE_RAYS:
                commandEncoder.setComputePipelineState(ps_GenerateRaysFromCamera)
            case COMPUTE_INTERSECTIONS:
                commandEncoder.setComputePipelineState(ps_ComputeIntersections)
            case SHADE:
                commandEncoder.setComputePipelineState(ps_ShadeMaterials)
            case FINAL_GATHER:
                commandEncoder.setComputePipelineState(ps_FinalGather)
            default:
                fatalError("Undefined Pipeline Stage Passed to DispatchPipelineState")
        }

        commandEncoder.dispatchThreadgroups(self.threadgroupsPerGrid,
                                            threadsPerThreadgroup: self.threadsPerThreadgroup)
    }
    
    fileprivate func pathtrace(in view: MTKView) {
//        self.frame_ray_count = self.rays.count
        
        let commandBuffer = self.commandQueue.makeCommandBuffer()
        commandBuffer?.label = "Iteration: \(iteration)"
        
        // MARK: SEMAPHORE CODE - Completion Handler
//        commandBuffer?.addCompletedHandler({ _ in //unused parameter
            // This triggers the CPU that the GPU has finished work
            // this function is run when the GPU ends an iteration
            // Needed for CPU/GPU Synchronization
//        self.iterationSemaphore.signal()
//            print(self.iteration)
//        })
        
        
        // If drawable is not ready, skip this iteration
        guard let drawable = view.currentDrawable
            else { // If drawable
                // print("Drawable not ready for iteration #\(self.iteration)")
                return;
        }
        
        // Clear the drawable on the first iteration
        if (self.iteration == 0) {
            let blitCommandEnconder = commandBuffer?.makeBlitCommandEncoder()
            let frameRange = Range(0 ..< MemoryLayout<float4>.stride * self.frame.count)
            blitCommandEnconder?.fill(buffer: self.frame.data!, range: frameRange, value: 0)
            blitCommandEnconder?.endEncoding()
            
            drawable.texture.replace(region: self.region, mipmapLevel: 0, withBytes: blankBitmapRawData, bytesPerRow: bytesPerRow)
        }
        
        let commandEncoder = commandBuffer?.makeComputeCommandEncoder()
        
        // If the commandEncoder could not be made
        if commandEncoder == nil || commandBuffer == nil {
            return
        }
        
        self.dispatchPipelineState(for: GENERATE_RAYS, using: commandEncoder!)
        
        
        // Repeat Shading Steps `depth` number of times
        for _ in 0 ..< Int(self.camera.data[3]) {
            self.dispatchPipelineState(for: COMPUTE_INTERSECTIONS, using: commandEncoder!)

            self.dispatchPipelineState(for: SHADE, using: commandEncoder!)
            
        }
        
        self.dispatchPipelineState(for: FINAL_GATHER, using: commandEncoder!)
        self.iteration += 1
        
        commandEncoder!.endEncoding()
        commandBuffer!.present(drawable)
        commandBuffer!.commit()
    }
}

extension PolluxRenderer : MTKViewDelegate {
    
    // Is called on each frame
    func draw(in view: MTKView) {
        // MARK: SEMAPHORE CODE - Wait
        // Wait until the last iteration is finished
//        _ = self.iterationSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        self.pathtrace(in: view)
    }
    
    // If the window changes, change the size of display
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Save the size of the drawable as we'll pass these
        //   values to our vertex shader when we draw
        self.camera.data.x  = Float(size.width );
        self.camera.data.y  = Float(size.height);
        
        // Size of the new frame
//        print(size)
        
        // Resize Rays Buffer
        self.region = MTLRegionMake2D(0, 0, Int(view.frame.size.width), Int(view.frame.size.height))
        self.rays.resize(count: Int(size.width*size.height), with: self.device)
        self.intersections.resize(count: Int(size.width*size.height), with: self.device)
        self.frame.resize(count: Int(size.width*size.height), with: self.device)
//        self.rayCompactor.resize(size: uint2(UInt32(self.camera.data.x), UInt32(self.camera.data.y)))
        self.iteration = 0
    }
}

// MARK: Handles User Gestures
extension PolluxRenderer {
    
    // Pans the camera along it's right and up vectors by dt.x and -dt.y respectively
    func panCamera(by dt: PlatformPoint) {
        // Change pos values
        self.camera.pos += self.camera.right * Float(dt.x) / gestureDampening
        self.camera.pos -= self.camera.up    * Float(dt.y) / gestureDampening
        
        // Change the lookAt as well
        self.camera.lookAt += self.camera.right * Float(dt.x) / gestureDampening
        self.camera.lookAt -= self.camera.up    * Float(dt.y) / gestureDampening
        
//        self.camera.view = normalize(self.camera.lookAt - self.camera.pos)
        
        // Clear buffer by setting iteration = 0
        self.iteration = 0
    }
    
    // Zooms the camera along it's view vector by dz
    func zoomCamera(by dz: Float) {
        // Avoiding the isNaN
        if dz.isNaN { return }
            
        // Change pos values
        self.camera.pos += self.camera.view * dz
        
        // Change the lookAt as well
        self.camera.lookAt += self.camera.view * dz
        
        // Clear buffer by setting iteration = 0
        self.iteration = 0
    }
}

