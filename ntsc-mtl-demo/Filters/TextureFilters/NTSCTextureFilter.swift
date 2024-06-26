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
    private var textureA: MTLTexture!
    private var textureB: MTLTexture!
    private var textureC: MTLTexture!
    
    private var outTexture1: MTLTexture!
    private var outTexture2: MTLTexture!
    private var outTexture3: MTLTexture!
    private let device: MTLDevice
    private let context: CIContext
    private let commandQueue: MTLCommandQueue
    private let pipelineCache: MetalPipelineCache
    var effect: NTSCEffect
    
    // MARK: -Filters
    private let lumaBoxFilter: LumaBoxTextureFilter
    private let lumaNotchFilter: IIRTextureFilter
    private let lightChromaLowpassFilter: ChromaLowpassTextureFilter
    private let fullChromaLowpassFilter: ChromaLowpassTextureFilter
    private let chromaIntoLumaFilter: ChromaIntoLumaTextureFilter
    private let compositePreemphasisFilter: IIRTextureFilter
    private let compositeNoiseFilter: CompositeNoiseTextureFilter
    private let snowFilter: SnowTextureFilter
    private let headSwitchingFilter: HeadSwitchingTextureFilter
    private let lumaSmearFilter: IIRTextureFilter
    private let ringingFilter: IIRTextureFilter
    private let chromaPhaseErrorFilter: PhaseErrorTextureFilter
    private let chromaPhaseNoiseFilter: PhaseNoiseTextureFilter
    private let chromaDelayFilter: ChromaDelayTextureFilter
    private let vhsFilter: VHSTextureFilter
    
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
        self.lumaBoxFilter = LumaBoxTextureFilter(device: device, commandQueue: commandQueue, pipelineCache: pipelineCache)
        let lumaNotchTransferFunction = IIRTransferFunction.lumaNotch
        let lumaNotchFilter = IIRTextureFilter(
            device: device,
            pipelineCache: pipelineCache,
            initialCondition: .firstSample,
            channels: .y,
            delay: 0
        )
        lumaNotchFilter.numerators = lumaNotchTransferFunction.numerators
        lumaNotchFilter.denominators = lumaNotchTransferFunction.denominators
        lumaNotchFilter.scale = 1
        self.lumaNotchFilter = lumaNotchFilter
        self.lightChromaLowpassFilter = ChromaLowpassTextureFilter(
            device: device,
            pipelineCache: pipelineCache
        )
        self.fullChromaLowpassFilter = ChromaLowpassTextureFilter(
            device: device,
            pipelineCache: pipelineCache
        )
        self.chromaIntoLumaFilter = ChromaIntoLumaTextureFilter(
            device: device,
            pipelineCache: pipelineCache
        )
        let compositePreemphasisFunction = IIRTransferFunction.compositePreemphasis(
            bandwidthScale: effect.bandwidthScale
        )
        let compositePreemphasisFilter = IIRTextureFilter(
            device: device,
            pipelineCache: pipelineCache,
            initialCondition: .zero,
            channels: .y,
            delay: 0
        )
        compositePreemphasisFilter.numerators = compositePreemphasisFunction.numerators
        compositePreemphasisFilter.denominators = compositePreemphasisFunction.denominators
        compositePreemphasisFilter.scale = -effect.compositePreemphasis
        self.compositePreemphasisFilter = compositePreemphasisFilter
        self.compositeNoiseFilter = CompositeNoiseTextureFilter(device: device, ciContext: ciContext, pipelineCache: pipelineCache)
        self.snowFilter = SnowTextureFilter(device: device, ciContext: ciContext, pipelineCache: pipelineCache)
        self.headSwitchingFilter = HeadSwitchingTextureFilter(device: device, ciContext: ciContext, pipelineCache: pipelineCache)
        let lumaSmearFunction = IIRTransferFunction.lumaSmear(amount: effect.lumaSmear, bandwidthScale: effect.bandwidthScale)
        let lumaSmearFilter = IIRTextureFilter(
            device: device,
            pipelineCache: pipelineCache,
            initialCondition: .zero,
            channels: .y,
            delay: 0
        )
        lumaSmearFilter.numerators = lumaSmearFunction.numerators
        lumaSmearFilter.denominators = lumaSmearFunction.denominators
        lumaSmearFilter.scale = 1
        self.lumaSmearFilter = lumaSmearFilter

        let ringingSettings = RingingSettings.default
        let ringingFunction = try IIRTransferFunction.ringing(ringingSettings: ringingSettings, bandwidthScale: effect.bandwidthScale)
        let ringingFilter = IIRTextureFilter(
            device: device,
            pipelineCache: pipelineCache,
            initialCondition: .firstSample,
            channels: .y,
            delay: 1
        )
        ringingFilter.numerators = ringingFunction.numerators
        ringingFilter.denominators = ringingFunction.denominators
        ringingFilter.scale = ringingSettings.intensity
        self.ringingFilter = ringingFilter
        self.chromaPhaseErrorFilter = PhaseErrorTextureFilter(device: device, pipelineCache: pipelineCache)
        self.chromaPhaseNoiseFilter = PhaseNoiseTextureFilter(device: device, pipelineCache: pipelineCache, ciContext: ciContext)
        self.chromaDelayFilter = ChromaDelayTextureFilter(device: device, pipelineCache: pipelineCache)
        self.vhsFilter = VHSTextureFilter(device: device, pipelineCache: pipelineCache, ciContext: ciContext)
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
    
    static func inputLuma(
        _ texture: (any MTLTexture),
        output: (any MTLTexture),
        commandBuffer: MTLCommandBuffer,
        lumaLowpass: LumaLowpass,
        lumaBoxFilter: LumaBoxTextureFilter,
        lumaNotchFilter: IIRTextureFilter
    ) throws {
        switch lumaLowpass {
        case .none:
            try justBlit(from: texture, to: output, commandBuffer: commandBuffer)
        case .box:
            try lumaBoxFilter.run(inputTexture: texture, outputTexture: output, commandBuffer: commandBuffer)
        case .notch:
            try lumaNotchFilter.run(inputTexture: texture, outputTexture: output, commandBuffer: commandBuffer)
        }
    }
    
    static func chromaLowpass(
        _ texture: (any MTLTexture),
        output: (any MTLTexture),
        commandBuffer: MTLCommandBuffer,
        chromaLowpass: ChromaLowpass,
        bandwidthScale: Float,
        lightFilter: ChromaLowpassTextureFilter,
        fullFilter: ChromaLowpassTextureFilter
    ) throws {
        switch chromaLowpass {
        case .none:
            return
        case .light:
            lightFilter.bandwidthScale = bandwidthScale
            lightFilter.chromaLowpass = chromaLowpass
            try lightFilter.run(inputTexture: texture, outputTexture: output, commandBuffer: commandBuffer)
        case .full:
            fullFilter.bandwidthScale = bandwidthScale
            fullFilter.chromaLowpass = chromaLowpass
            try fullFilter.run(inputTexture: texture, outputTexture: output, commandBuffer: commandBuffer)
        }
    }
    
    static func chromaIntoLuma(inputTexture: MTLTexture, outputTexture: MTLTexture, timestamp: UInt32, phaseShift: PhaseShift, phaseShiftOffset: Int, filter: ChromaIntoLumaTextureFilter, device: MTLDevice, commandBuffer: MTLCommandBuffer) throws {
        filter.phaseShift = phaseShift
        filter.phaseShiftOffset = phaseShiftOffset
        filter.timestamp = timestamp
        try filter.run(inputTexture: inputTexture, outputTexture: outputTexture, commandBuffer: commandBuffer)
    }
    
    static func compositePreemphasis(inputTexture: MTLTexture, outputTexture: MTLTexture, filter: IIRTextureFilter, bandwidthScale: Float, compositePreemphasis: Float16,  commandBuffer: MTLCommandBuffer) throws {
        let fn = IIRTransferFunction.compositePreemphasis(bandwidthScale: bandwidthScale)
        filter.numerators = fn.numerators
        filter.denominators = fn.denominators
        filter.scale = -compositePreemphasis
        
        try filter.run(inputTexture: inputTexture, outputTexture: outputTexture, commandBuffer: commandBuffer)
    }
    
    static func compositeNoise(inputTexture: MTLTexture, outputTexture: MTLTexture, filter: CompositeNoiseTextureFilter, noise: FBMNoiseSettings?, bandwidthScale: Float, commandBuffer: MTLCommandBuffer) throws {
        filter.noise = noise
        filter.bandwidthScale = bandwidthScale
        try filter.run(inputTexture: inputTexture, outputTexture: outputTexture, commandBuffer: commandBuffer)
    }
    
    static func snow(inputTexture: MTLTexture, outputTexture: MTLTexture, filter: SnowTextureFilter, snowIntensity: Float, snowAnisotropy: Float, bandwidthScale: Float, commandBuffer: MTLCommandBuffer) throws {
        filter.intensity = snowIntensity
        filter.anisotropy = snowAnisotropy
        filter.bandwidthScale = bandwidthScale
        try filter.run(inputTexture: inputTexture, outputTexture: outputTexture, commandBuffer: commandBuffer)
    }
    
    static func headSwitching(
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        filter: HeadSwitchingTextureFilter,
        headSwitchingEnabled: Bool,
        headSwitching: HeadSwitchingSettings,
        bandwidthScale: Float,
        commandBuffer: MTLCommandBuffer
    ) throws {
        guard headSwitchingEnabled else {
            try justBlit(from: inputTexture, to: outputTexture, commandBuffer: commandBuffer)
            return
        }
        filter.settings = headSwitching
        filter.bandwidthScale = bandwidthScale
        try filter.run(inputTexture: inputTexture, outputTexture: outputTexture, commandBuffer: commandBuffer)
    }
    
    static func trackingNoise(inputTexture: MTLTexture, outputTexture: MTLTexture, trackingNoise: TrackingNoiseSettings?, commandBuffer: MTLCommandBuffer) throws {
        try justBlit(from: inputTexture, to: outputTexture, commandBuffer: commandBuffer)
    }
    
    static func lumaIntoChroma(inputTexture: MTLTexture, outputTexture: MTLTexture, commandBuffer: MTLCommandBuffer) throws {
        try justBlit(from: inputTexture, to: outputTexture, commandBuffer: commandBuffer)
    }
    
    static func lumaSmear(inputTexture: MTLTexture, outputTexture: MTLTexture, filter: IIRTextureFilter, lumaSmear: Float, bandwidthScale: Float, commandBuffer: MTLCommandBuffer) throws {
        if lumaSmear.isZero {
            try justBlit(from: inputTexture, to: outputTexture, commandBuffer: commandBuffer)
            return
        }
        let fn = IIRTransferFunction.lumaSmear(amount: lumaSmear, bandwidthScale: bandwidthScale)
        filter.numerators = fn.numerators
        filter.denominators = fn.denominators
        try filter.run(inputTexture: inputTexture, outputTexture: outputTexture, commandBuffer: commandBuffer)
    }
    
    static func ringing(inputTexture: MTLTexture, outputTexture: MTLTexture, filter: IIRTextureFilter, ringingEnabled: Bool, ringing: RingingSettings, bandwidthScale: Float, commandBuffer: MTLCommandBuffer) throws {
        guard ringingEnabled else {
            try justBlit(from: inputTexture, to: outputTexture, commandBuffer: commandBuffer)
            return
        }
        let fn = try IIRTransferFunction.ringing(ringingSettings: ringing, bandwidthScale: bandwidthScale)
        filter.numerators = fn.numerators
        filter.denominators = fn.denominators
        filter.scale = ringing.intensity
        try filter.run(inputTexture: inputTexture, outputTexture: outputTexture, commandBuffer: commandBuffer)
    }
    
    static func lumaNoise(inputTexture: MTLTexture, outputTexture: MTLTexture, commandBuffer: MTLCommandBuffer) throws {
        try justBlit(from: inputTexture, to: outputTexture, commandBuffer: commandBuffer)
    }
    
    static func chromaNoise(inputTexture: MTLTexture, outputTexture: MTLTexture, commandBuffer: MTLCommandBuffer) throws {
        try justBlit(from: inputTexture, to: outputTexture, commandBuffer: commandBuffer)
    }
    static func chromaPhaseError(inputTexture: MTLTexture, outputTexture: MTLTexture, filter: PhaseErrorTextureFilter, chromaPhaseError: Float16, commandBuffer: MTLCommandBuffer) throws {
        if chromaPhaseError.isZero {
            try justBlit(from: inputTexture, to: outputTexture, commandBuffer: commandBuffer)
            return
        }
        filter.phaseError = chromaPhaseError
        try filter.run(inputTexture: inputTexture, outputTexture: outputTexture, commandBuffer: commandBuffer)
    }
    static func chromaPhaseNoise(
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        filter: PhaseNoiseTextureFilter,
        chromaPhaseNoiseIntensity: Float16,
        commandBuffer: MTLCommandBuffer
    ) throws {
        if chromaPhaseNoiseIntensity.isZero {
            try justBlit(from: inputTexture, to: outputTexture, commandBuffer: commandBuffer)
        }
        filter.phaseError = chromaPhaseNoiseIntensity
        try filter.run(inputTexture: inputTexture, outputTexture: outputTexture, commandBuffer: commandBuffer)
    }
    static func chromaDelay(inputTexture: MTLTexture, outputTexture: MTLTexture, filter: ChromaDelayTextureFilter, delay: (Float16, Int), commandBuffer: MTLCommandBuffer) throws {
        filter.chromaDelay = delay
        try filter.run(inputTexture: inputTexture, outputTexture: outputTexture, commandBuffer: commandBuffer)
    }
    static func vhs(inputTexture: MTLTexture, outputTexture: MTLTexture, filter: VHSTextureFilter, isVHSEnabled: Bool, settings: VHSSettings, bandwidthScale: Float, commandBuffer: MTLCommandBuffer) throws {
        guard isVHSEnabled else {
            try justBlit(from: inputTexture, to: outputTexture, commandBuffer: commandBuffer)
            return
        }
        filter.settings = settings
        filter.bandwidthScale = bandwidthScale
        try filter.run(inputTexture: inputTexture, outputTexture: outputTexture, commandBuffer: commandBuffer)
    }
    
    static func chromaVertBlend(inputTexture: MTLTexture, outputTexture: MTLTexture, commandBuffer: MTLCommandBuffer) throws {
        try justBlit(from: inputTexture, to: outputTexture, commandBuffer: commandBuffer)
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
    
    static func handle(mostRecentTexture: MTLTexture, previousTexture: MTLTexture, outTexture: MTLTexture, useField: UseField, commandBuffer: MTLCommandBuffer, device: MTLDevice, pipelineCache: MetalPipelineCache) throws {
        switch useField {
        case .alternating, .upper, .lower:
            throw Error.notImplemented
        case .both:
            try justBlit(from: mostRecentTexture, to: outTexture, commandBuffer: commandBuffer)
        case .interleavedUpper, .interleavedLower:
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
        useField: UseField,
        interTexA: MTLTexture,
        interTexB: MTLTexture,
        outTex: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        device: MTLDevice,
        pipelineCache: MetalPipelineCache
    ) throws {
        if frameNum % 2 == 0 {
            try justBlit(from: inputTexture, to: interTexA, commandBuffer: commandBuffer)
            try handle(mostRecentTexture: interTexA, previousTexture: interTexB, outTexture: outTex, useField: useField, commandBuffer: commandBuffer, device: device, pipelineCache: pipelineCache)
        } else {
            try justBlit(from: inputTexture, to: interTexB, commandBuffer: commandBuffer)
            try handle(mostRecentTexture: interTexB, previousTexture: interTexA, outTexture: outTex, useField: useField, commandBuffer: commandBuffer, device: device, pipelineCache: pipelineCache)
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
        self.textureA = textures[0]
        self.textureB = textures[1]
        self.textureC = textures[2]
        self.outTexture1 = textures[3]
        self.outTexture2 = textures[4]
        self.outTexture3 = textures[5]
        context.render(inputImage, to: textureA, commandBuffer: commandBuffer, bounds: inputImage.extent, colorSpace: context.workingColorSpace ?? CGColorSpaceCreateDeviceRGB())
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
        let textures: [MTLTexture] = [textureA, textureB, textureC]
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
            // Step 1: luma in
            try Self.inputLuma(
                try iter.last,
                output: try iter.next(),
                commandBuffer: commandBuffer,
                lumaLowpass: effect.inputLumaFilter, 
                lumaBoxFilter: lumaBoxFilter,
                lumaNotchFilter: lumaNotchFilter
            )
            // Step 2: chroma lowpass in
            try Self.chromaLowpass(
                try iter.last,
                output: try iter.next(),
                commandBuffer: commandBuffer,
                chromaLowpass: effect.chromaLowpassIn, 
                bandwidthScale: effect.bandwidthScale,
                lightFilter: lightChromaLowpassFilter,
                fullFilter: fullChromaLowpassFilter
            )
            // Step 3: chroma into luma
            try Self.chromaIntoLuma(
                inputTexture: try iter.last,
                outputTexture: try iter.next(),
                timestamp: frameNum,
                phaseShift: effect.videoScanlinePhaseShift,
                phaseShiftOffset: effect.videoScanlinePhaseShiftOffset,
                filter: self.chromaIntoLumaFilter,
                device: device,
                commandBuffer: commandBuffer
            )
            // Step 4: composite preemphasis
            try Self.compositePreemphasis(
                inputTexture: try iter.last,
                outputTexture: try iter.next(),
                filter: compositePreemphasisFilter,
                bandwidthScale: effect.bandwidthScale, 
                compositePreemphasis: effect.compositePreemphasis,
                commandBuffer: commandBuffer
            )
            // Step 5: composite noise
            try Self.compositeNoise(
                inputTexture: try iter.last,
                outputTexture: try iter.next(),
                filter: compositeNoiseFilter,
                noise: effect.compositeNoise, 
                bandwidthScale: effect.bandwidthScale,
                commandBuffer: commandBuffer
            )
            // Step 6: snow
            try Self.snow(
                inputTexture: try iter.last,
                outputTexture: try iter.next(),
                filter: snowFilter,
                snowIntensity: effect.snowIntensity,
                snowAnisotropy: effect.snowAnisotropy, 
                bandwidthScale: effect.bandwidthScale,
                commandBuffer: commandBuffer
            )
            // Step 7: head switching
            try Self.headSwitching(
                inputTexture: try iter.last,
                outputTexture: try iter.next(),
                filter: headSwitchingFilter, 
                headSwitchingEnabled: effect.headSwitchingEnabled,
                headSwitching: effect.headSwitching,
                bandwidthScale: effect.bandwidthScale,
                commandBuffer: commandBuffer
            )
            // Step 8: tracking noise
            try Self.trackingNoise(
                inputTexture: try iter.last,
                outputTexture: try iter.next(),
                trackingNoise: effect.trackingNoise,
                commandBuffer: commandBuffer
            )
            // Step 9: luma into chroma
            try Self.lumaIntoChroma(
                inputTexture: try iter.last,
                outputTexture: try iter.next(),
                commandBuffer: commandBuffer
            )
            
            // Step 10: luma smear
            try Self.lumaSmear(
                inputTexture: try iter.last,
                outputTexture: try iter.next(),
                filter: lumaSmearFilter,
                lumaSmear: effect.lumaSmear,
                bandwidthScale: effect.bandwidthScale,
                commandBuffer: commandBuffer
            )
            // Step 11: ringing
            try Self.ringing(
                inputTexture: try iter.last,
                outputTexture: try iter.next(),
                filter: ringingFilter, 
                ringingEnabled: effect.ringingEnabled,
                ringing: effect.ringing,
                bandwidthScale: effect.bandwidthScale,
                commandBuffer: commandBuffer
            )
            // Step 12: luma noise
            try Self.lumaNoise(
                inputTexture: try iter.last,
                outputTexture: try iter.next(),
                commandBuffer: commandBuffer
            )
            // Step 13: chroma noise
            try Self.chromaNoise(
                inputTexture: try iter.last,
                outputTexture: try iter.next(),
                commandBuffer: commandBuffer
            )
            // Step 14: chroma phase error
            try Self.chromaPhaseError(
                inputTexture: try iter.last,
                outputTexture: try iter.next(), 
                filter: chromaPhaseErrorFilter,
                chromaPhaseError: effect.chromaPhaseError,
                commandBuffer: commandBuffer
            )
            // Step 15: chroma phase noise
            try Self.chromaPhaseNoise(
                inputTexture: try iter.last,
                outputTexture: try iter.next(), 
                filter: chromaPhaseNoiseFilter,
                chromaPhaseNoiseIntensity: effect.chromaPhaseNoiseIntensity,
                commandBuffer: commandBuffer
            )
            
            // Step 16: chroma delay
            try Self.chromaDelay(
                inputTexture: try iter.last,
                outputTexture: try iter.next(),
                filter: chromaDelayFilter,
                delay: effect.chromaDelay,
                commandBuffer: commandBuffer
            )
            // Step 17: vhs
            try Self.vhs(
                inputTexture: try iter.last,
                outputTexture: try iter.next(),
                filter: vhsFilter,
                isVHSEnabled: effect.isVHSEnabled,
                settings: effect.vhsSettings, 
                bandwidthScale: effect.bandwidthScale,
                commandBuffer: commandBuffer
            )
            // Step 18: chroma vert blend
            try Self.chromaVertBlend(
                inputTexture: try iter.last,
                outputTexture: try iter.next(),
                commandBuffer: commandBuffer
            )
            // Step 19: chroma lowpass out
            try Self.chromaLowpass(
                try iter.last,
                output: try iter.next(),
                commandBuffer: commandBuffer,
                chromaLowpass: effect.chromaLowpassOut, 
                bandwidthScale: effect.bandwidthScale,
                lightFilter: lightChromaLowpassFilter,
                fullFilter: fullChromaLowpassFilter
            )
            try Self.writeToFields(
                inputTexture: try iter.last,
                frameNum: frameNum,
                useField: effect.useField,
                interTexA: outTexture1,
                interTexB: outTexture2,
                outTex: try iter.next(),
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
