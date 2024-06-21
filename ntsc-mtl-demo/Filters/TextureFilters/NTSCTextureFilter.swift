//
//  IIRTextureFilter.swift
//  ntsc-mtl-demo
//
//  Created by Jeffrey Blagdon on 2024-06-03.
//

import Foundation
import CoreImage
import Metal

enum TextureFilterError: Swift.Error {
    case cantMakeTexture
    case cantMakeCommandQueue
    case cantMakeCommandBuffer
    case cantMakeComputeEncoder
    case cantMakeLibrary
    case cantMakeRandomImage
    case cantMakeFunction(String)
    case cantMakeBlitEncoder
    case logicHole(String)
    case notImplemented
}

class NTSCTextureFilter {
    typealias Error = TextureFilterError

    private let effect: NTSCEffect
    private let device: MTLDevice
    private let context: CIContext
    private let commandQueue: MTLCommandQueue
    private let pipelineCache: MetalPipelineCache
    private var textureA: MTLTexture?
    private var textureB: MTLTexture?
    private var textureC: MTLTexture?
    private var outTexture1: MTLTexture?
    private var outTexture2: MTLTexture?
    private var outTexture3: MTLTexture?
    
    // MARK: -Filters

    
    var inputImage: CIImage?
    
    init(effect: NTSCEffect, device: MTLDevice, ciContext: CIContext) throws {
        self.effect = effect
        self.device = device
        self.context = ciContext
        guard let commandQueue = device.makeCommandQueue() else {
            throw Error.cantMakeTexture
        }
        self.commandQueue = commandQueue
        guard let library = device.makeDefaultLibrary() else {
            throw Error.cantMakeLibrary
        }
        self.pipelineCache = try MetalPipelineCache(device: device, library: library)
    }
        
    static func convertToYIQ(_ texture: (any MTLTexture), output: (any MTLTexture), commandBuffer: MTLCommandBuffer, device: MTLDevice, pipelineCache: MetalPipelineCache) throws {
        // Create a command buffer and encoder
        guard let commandEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw Error.cantMakeComputeEncoder
        }
        let pipelineState = try pipelineCache.pipelineState(function: .convertToYIQ)
        commandEncoder.setComputePipelineState(pipelineState)
        
        // Set the texture and dispatch threads
        commandEncoder.setTexture(texture, index: 0)
        commandEncoder.setTexture(output, index: 1)
        commandEncoder.dispatchThreads(textureWidth: texture.width, textureHeight: texture.height)
        
        // Finalize encoding
        commandEncoder.endEncoding()
    }
    
    static func convertToRGB(
        _ texture: (any MTLTexture),
        output: (any MTLTexture),
        commandBuffer: MTLCommandBuffer,
        device: MTLDevice, 
        pipelineCache: MetalPipelineCache
    ) throws {
        // Create a command buffer and encoder
        guard let commandEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw Error.cantMakeComputeEncoder
        }
        
        let pipelineState = try pipelineCache.pipelineState(function: .convertToRGB)
        
        // Set up the compute pipeline
        commandEncoder.setComputePipelineState(pipelineState)
        
        // Set the texture and dispatch threads
        commandEncoder.setTexture(texture, index: 0)
        commandEncoder.setTexture(output, index: 1)
        commandEncoder.dispatchThreads(textureWidth: texture.width, textureHeight: texture.height)
        
        commandEncoder.endEncoding()
    }
    
    static func handle(mostRecentTexture: MTLTexture, previousTexture: MTLTexture, outTexture: MTLTexture, interlaceMode: InterlaceMode, commandBuffer: MTLCommandBuffer, device: MTLDevice, pipelineCache: MetalPipelineCache) throws {
        switch interlaceMode {
        case .full:
            try justBlit(from: mostRecentTexture, to: outTexture, commandBuffer: commandBuffer)
            
        case .interlaced:
            try interleave(mostRecentTexture: mostRecentTexture, previousTexture: previousTexture, outTexture: outTexture, commandBuffer: commandBuffer, device: device, pipelineCache: pipelineCache)
        }
    }
    
    static func interleave(mostRecentTexture: MTLTexture, previousTexture: MTLTexture, outTexture: MTLTexture, commandBuffer: MTLCommandBuffer, device: MTLDevice, pipelineCache: MetalPipelineCache) throws {
        guard let commandEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw Error.cantMakeComputeEncoder
        }
        let pipelineState = try pipelineCache.pipelineState(function: .interleave)
        commandEncoder.setComputePipelineState(pipelineState)
        commandEncoder.setTexture(mostRecentTexture, index: 0)
        commandEncoder.setTexture(previousTexture, index: 1)
        commandEncoder.setTexture(outTexture, index: 2)
        commandEncoder.dispatchThreads(textureWidth: mostRecentTexture.width, textureHeight: mostRecentTexture.height, threadgroupScale: 8)
        commandEncoder.endEncoding()
    }
    
    static func writeToFields(
        inputTexture: MTLTexture,
        frameNum: UInt32,
        interlaceMode: InterlaceMode,
        interTexA: MTLTexture,
        interTexB: MTLTexture,
        outTex: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        device: MTLDevice,
        pipelineCache: MetalPipelineCache
    ) throws {
        if frameNum % 2 == 0 {
            try justBlit(from: inputTexture, to: interTexA, commandBuffer: commandBuffer)
            try handle(mostRecentTexture: interTexA, previousTexture: interTexB, outTexture: outTex, interlaceMode: interlaceMode, commandBuffer: commandBuffer, device: device, pipelineCache: pipelineCache)
        } else {
            try justBlit(from: inputTexture, to: interTexB, commandBuffer: commandBuffer)
            try handle(mostRecentTexture: interTexB, previousTexture: interTexA, outTexture: outTex, interlaceMode: interlaceMode, commandBuffer: commandBuffer, device: device, pipelineCache: pipelineCache)
        }
    }
    
    private func setup(with inputImage: CIImage) throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw Error.cantMakeCommandBuffer
        }
        defer { commandBuffer.commit() }
        if let textureA, textureA.width == Int(inputImage.extent.width), textureA.height == Int(inputImage.extent.height) {
            self.context.render(inputImage, to: textureA, commandBuffer: commandBuffer, bounds: inputImage.extent, colorSpace: self.context.workingColorSpace ?? CGColorSpaceCreateDeviceRGB())
            return
        }
        let textures = Array(IIRTextureFilter.textures(width: Int(inputImage.extent.width), height: Int(inputImage.extent.height), pixelFormat: .rgba16Float, device: device).prefix(6))
        guard textures.count == 6 else {
            throw Error.cantMakeTexture
        }
        self.textureA = textures[0]
        self.textureB = textures[1]
        self.textureC = textures[2]
        self.outTexture1 = textures[3]
        self.outTexture2 = textures[4]
        self.outTexture3 = textures[5]
        context.render(inputImage, to: textureA!, commandBuffer: commandBuffer, bounds: inputImage.extent, colorSpace: context.workingColorSpace ?? CGColorSpaceCreateDeviceRGB())
    }
    
    private var frameNum: UInt32 = 0
    
    var outputImage: CIImage? {
        let frameNum = self.frameNum
        defer { self.frameNum += 1 }
        guard let inputImage else { return nil }
        do {
            try setup(with: inputImage)
        } catch {
            print("Error setting up texture with input image: \(error)")
            return nil
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("Couldn't make command buffer")
            return nil
        }
        let textures: [MTLTexture] = [textureA!, textureB!, textureC!]
        let iter = IteratorThing(vals: textures)
        
        do {
             // Step 0: convert to YIQ
            try Self.convertToYIQ(
                try iter.next(),
                output: try iter.next(),
                commandBuffer: commandBuffer,
                device: device,
                pipelineCache: pipelineCache
            )
            try Self.convertToRGB(
                try iter.last,
                output: try iter.next(),
                commandBuffer: commandBuffer,
                device: device,
                pipelineCache: pipelineCache
            )
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            return CIImage(mtlTexture: try iter.last)
        } catch {
            print("Error generating output image: \(error)")
            return nil
        }
    }
}
