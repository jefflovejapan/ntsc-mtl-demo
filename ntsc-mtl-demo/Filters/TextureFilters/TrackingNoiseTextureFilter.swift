//
//  TrackingNoiseTextureFilter.swift
//  ntsc-mtl-demo
//
//  Created by Jeffrey Blagdon on 2024-06-15.
//

import Foundation
import Metal
import CoreImage

class TrackingNoiseTextureFilter {
    typealias Error = TextureFilterError
    private let device: MTLDevice
    private let ciContext: CIContext
    private let randomGenerator = CIFilter.randomGenerator()
    private var rng = SystemRandomNumberGenerator()
    private let pipelineCache: MetalPipelineCache
    private var wipTextureA: MTLTexture?
    private var wipTextureB: MTLTexture?
    private var randomTexture: MTLTexture?
        
    var trackingNoiseSettings: TrackingNoiseSettings = .default
    var bandwidthScale: Float = NTSCEffect.default.bandwidthScale
    init(device: MTLDevice, ciContext: CIContext, pipelineCache: MetalPipelineCache) {
        self.device = device
        self.ciContext = ciContext
        self.pipelineCache = pipelineCache
    }
    
    func run(inputTexture: MTLTexture, outputTexture: MTLTexture, commandBuffer: MTLCommandBuffer) throws {
        let needsUpdate: Bool
        if let wipTextureA {
            needsUpdate = !(wipTextureA.width == inputTexture.width && wipTextureA.height == inputTexture.height)
        } else {
            needsUpdate = true
        }
        if needsUpdate {
            let texs = Array(IIRTextureFilter.textures(from: inputTexture, device: device).prefix(3))
            self.wipTextureA = texs[0]
            self.wipTextureB = texs[1]
            self.randomTexture = texs[2]
        }

        guard let wipTextureA, let wipTextureB, let randomTexture else {
            throw Error.cantMakeTexture
        }
        let iter = IteratorThing(vals: [wipTextureA, wipTextureB])
        
        /*
         - Blit inputTexture to another tex
         - run shiftRow on it
         - run videoNoiseLine on it
         - run snow on it
         */
//        try justBlit(from: inputTexture, to: iter.next(), commandBuffer: commandBuffer)
//        try justBlit(from: iter.last, to: outputTexture, commandBuffer: commandBuffer)
        try writeNoise(to: randomTexture, commandBuffer: commandBuffer)
        try shiftRow(input: inputTexture, randomTexture: randomTexture, output: outputTexture, commandBuffer: commandBuffer)
//        try addSnow(input: try iter.last, output: try iter.next(), commandBuffer: commandBuffer)
//        try blend(input: iter.last, altered: iter.last, output: outputTexture, commandBuffer: commandBuffer)
    }
    
    private func shiftRow(input: MTLTexture, randomTexture: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw Error.cantMakeComputeEncoder
        }
        let pipelineState = try pipelineCache.pipelineState(function: .trackingNoiseShiftRow)
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(randomTexture, index: 1)
        encoder.setTexture(output, index: 2)
        var effectHeight: UInt = 100
        encoder.setBytes(&effectHeight, length: MemoryLayout<UInt>.size, index: 0)
        var waveIntensity = trackingNoiseSettings.waveIntensity
        encoder.setBytes(&waveIntensity, length: MemoryLayout<Float>.size, index: 1)
        var bandwidthScale = bandwidthScale
        encoder.setBytes(&bandwidthScale, length: MemoryLayout<Float>.size, index: 2)
        encoder.dispatchThreads(textureWidth: input.width, textureHeight: input.height)
        encoder.endEncoding()
    }
    private func writeNoise(to texture: MTLTexture, commandBuffer: MTLCommandBuffer) throws {
        let randomX: UInt = rng.next(upperBound: 500)
        let randomY: UInt = rng.next(upperBound: 500)
        guard let randomImage = randomGenerator.outputImage else {
            throw Error.cantMakeRandomImage
        }
        let shiftedImage = randomImage.transformed(by: CGAffineTransform(translationX: CGFloat(randomX), y: CGFloat(randomY)))
        let croppedImage = shiftedImage.cropped(to: CGRect(origin: .zero, size: CGSize(width: texture.width, height: texture.height)))
        ciContext.render(croppedImage, to: texture, commandBuffer: commandBuffer, bounds: croppedImage.extent, colorSpace: ciContext.workingColorSpace ?? CGColorSpaceCreateDeviceRGB())
    }
    
    private func addSnow(input: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw Error.cantMakeComputeEncoder
        }
        let pipelineState = try pipelineCache.pipelineState(function: .snow)
        encoder.setComputePipelineState(pipelineState)
        encoder.dispatchThreads(textureWidth: input.width, textureHeight: input.height)
        encoder.endEncoding()
    }
    private func blend(input: MTLTexture, altered: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw Error.cantMakeComputeEncoder
        }
        let pipelineState = try pipelineCache.pipelineState(function: .yiqCompose3)
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(altered, index: 1)
        encoder.setTexture(output, index: 2)
        encoder.dispatchThreads(textureWidth: input.width, textureHeight: input.height)
        encoder.endEncoding()
    }
}
