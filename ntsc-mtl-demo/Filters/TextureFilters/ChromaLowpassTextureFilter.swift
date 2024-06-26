//
//  ChromaLowpassFilter.swift
//  ntsc-mtl-demo
//
//  Created by Jeffrey Blagdon on 2024-06-04.
//

import Foundation
import Metal

class ChromaLowpassTextureFilter {
    typealias Error = IIRTextureFilter.Error
    enum Filters {
        case none
        case full(i: IIRTextureFilter, q: IIRTextureFilter)
        case light(iAndQ: IIRTextureFilter)
    }
    
    private let device: MTLDevice
    private let pipelineCache: MetalPipelineCache
    var filters: Filters = .none
    
    private var needsIIRUpdate = true
    var filterType: FilterType = NTSCEffect.default.filterType {
        didSet {
            if filterType != oldValue {
                needsIIRUpdate = true
            }
        }
    }
    var bandwidthScale: Float = NTSCEffect.default.bandwidthScale {
        didSet {
            if bandwidthScale != oldValue {
                needsIIRUpdate = true
            }
        }
    }
    var chromaLowpass: ChromaLowpass = .none {
        didSet {
            if chromaLowpass != oldValue {
                needsIIRUpdate = true
            }
        }
    }
    
    init(device: MTLDevice, pipelineCache: MetalPipelineCache) {
        self.device = device
        self.pipelineCache = pipelineCache
    }
    
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }
    
    static func lowpassFilter(cutoff: Float, rate: Float, filterType: FilterType) -> IIRTransferFunction {
        switch filterType {
        case .constantK:
            let lowpass = IIRTransferFunction.lowpassFilter(cutoff: cutoff, rate: rate)
            let result = lowpass.cascade(n: 3)
            return result
        case .butterworth:
            return IIRTransferFunction.butterworth(cutoff: cutoff, rate: rate)
        }
    }
    
    var iTexture: MTLTexture?
    var qTexture: MTLTexture?
    private var yiqCompose3PipelineState: MTLComputePipelineState?
    private var yiqComposePipelineState: MTLComputePipelineState?
    
    var pipelineState: MTLComputePipelineState {
        get throws {
            switch filters {
            case .none:
                throw MetalPipelineCache.Error.noPipelineStateAvailable
            case .light:
                return try pipelineCache.pipelineState(function: .yiqCompose)
            case .full:
                return try pipelineCache.pipelineState(function: .yiqCompose3)
            }
        }
    }
    
    func run(inputTexture: MTLTexture, outputTexture: MTLTexture, commandBuffer: MTLCommandBuffer) throws {
        let needsTextureUpdate: Bool
        if let iTexture {
            if iTexture.width != inputTexture.width {
                needsTextureUpdate = true
            } else if iTexture.height != inputTexture.height {
                needsTextureUpdate = true
            } else {
                needsTextureUpdate = false
            }
        } else {
            needsTextureUpdate = true
        }
        
        if needsTextureUpdate {
            needsIIRUpdate = true
            let textures = Array(IIRTextureFilter.textures(width: inputTexture.width, height: inputTexture.height, pixelFormat: inputTexture.pixelFormat, device: device).prefix(2))
            self.iTexture = textures[0]
            self.qTexture = textures[1]
        }
        
        if needsIIRUpdate {
            try performIIRUpdate()
            needsIIRUpdate = false
        }
        
        switch filters {
        case .none:
            try justBlit(from: inputTexture, to: outputTexture, commandBuffer: commandBuffer)
            return
        case let .light(iAndQFilter):
            try iAndQFilter.run(inputTexture: inputTexture, outputTexture: iTexture!, commandBuffer: commandBuffer)
            
        case let .full(iFilter, qFilter):
            try iFilter.run(inputTexture: inputTexture, outputTexture: iTexture!, commandBuffer: commandBuffer)
            try qFilter.run(inputTexture: inputTexture, outputTexture: qTexture!, commandBuffer: commandBuffer)
        }
        
        let pipelineState = try self.pipelineState
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw Error.cantMakeComputeEncoder
        }
        
        computeEncoder.setComputePipelineState(pipelineState)
        switch filters {
        case .none:
            throw Error.invalidState("Should have already returned if filters == .none")
        case .light:
            computeEncoder.setTexture(inputTexture, index: 0)
            computeEncoder.setTexture(iTexture!, index: 1)
            computeEncoder.setTexture(outputTexture, index: 2)
            let channels: YIQChannels = [.i, .q]
            var channelMix = channels.floatMix
            computeEncoder.setBytes(&channelMix, length: MemoryLayout<Float16>.size * 4, index: 0)
        case .full:
            computeEncoder.setTexture(inputTexture, index: 0)
            computeEncoder.setTexture(iTexture!, index: 1)
            computeEncoder.setTexture(qTexture!, index: 2)
            computeEncoder.setTexture(outputTexture, index: 3)
        }
        
        computeEncoder.dispatchThreads(textureWidth: inputTexture.width, textureHeight: inputTexture.height)
        computeEncoder.endEncoding()
    }
    
    private func performIIRUpdate() throws {
        let initialCondition: IIRTextureFilter.InitialCondition = .zero
        let rate = NTSC.rate * self.bandwidthScale
        switch chromaLowpass {
        case .none:
            self.filters = .none
        case .full:
            let iFunction = Self.lowpassFilter(cutoff: 1_300_000.0, rate: rate, filterType: filterType)
            let iFilter = IIRTextureFilter(
                device: device,
                pipelineCache: pipelineCache,
                initialCondition: initialCondition,
                channels: .i,
                delay: 2
            )
            iFilter.numerators = iFunction.numerators
            iFilter.denominators = iFunction.denominators
            iFilter.scale = 1
            let qFunction = Self.lowpassFilter(cutoff: 600_000.0, rate: rate, filterType: filterType)
            let qFilter = IIRTextureFilter(
                device: device,
                pipelineCache: pipelineCache,
                initialCondition: initialCondition,
                channels: .q,
                delay: 4
            )
            qFilter.numerators = qFunction.numerators
            qFilter.denominators = qFunction.denominators
            qFilter.scale = 1
            self.filters = .full(i: iFilter, q: qFilter)
        case .light:
            let function = Self.lowpassFilter(cutoff: 2_600_000.0, rate: rate, filterType: filterType)
            let iAndQFilter = IIRTextureFilter(
                device: device,
                pipelineCache: pipelineCache,
                initialCondition: initialCondition,
                channels: [.i, .q],
                delay: 1
            )
            iAndQFilter.numerators = function.numerators
            iAndQFilter.denominators = function.denominators
            iAndQFilter.scale = 1
            self.filters = .light(iAndQ: iAndQFilter)
        }
    }
}
