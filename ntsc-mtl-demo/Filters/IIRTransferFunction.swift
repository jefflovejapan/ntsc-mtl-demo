//
//  IIRFunction.swift
//  ntsc-mtl-demo
//
//  Created by Jeffrey Blagdon on 2024-05-26.
//

import Foundation

struct IIRTransferFunction {
    var numerators: [Float]
    var denominators: [Float]
    
    enum Error: Swift.Error {
        case notchFrequencyOutOfBounds
    }
    
    static let lumaNotch = try! notchFilter(frequency: 0.5, quality: 2)
    static let rustLumaNotch = try! rustNotchFilter(frequency: 0.5, quality: 2)
    
    static func notchFilter(frequency: Float, quality: Float) throws -> IIRTransferFunction {
        guard (0...1).contains(frequency) else {
            throw Error.notchFrequencyOutOfBounds
        }
        
        let normalizedBandwidth = (frequency / quality) * .pi
        let normalizedFrequency = frequency * .pi
        let gb: Float = 1 / (sqrt(2))
        let beta = (sqrt(1 - (pow(gb, 2)))/gb) * tan(normalizedBandwidth / 2)
        let gain = 1.0 / (1.0 + beta)
        let middleParam = -2.0 * cos(normalizedFrequency) * gain
        let numerators: [Float] = [gain, middleParam, gain]
        let denominators: [Float] = [1, middleParam, (2 * gain) - 1]
        return IIRTransferFunction(numerators: numerators, denominators: denominators)
    }
    
    static func rustNotchFilter(frequency: Float, quality: Float) throws -> IIRTransferFunction {
        guard (0...1).contains(frequency) else {
            throw Error.notchFrequencyOutOfBounds
        }
        
        let bandwidth: Float = (frequency / quality) * .pi
        let normalizedFrequency = frequency * .pi
        let beta = tan(bandwidth * 0.5)
        let gain: Float = pow(1 + beta, -1)
        let middleTerm = -2 * cos(normalizedFrequency) * gain
        let num: [Float] = [gain, middleTerm, gain]
        let den: [Float] = [1, middleTerm, (2 * gain) - 1]
        return IIRTransferFunction(numerators: num, denominators: den)
    }
    
    static func hardCodedLumaNotch() -> IIRTransferFunction {
        return IIRTransferFunction(numerators: [0.70710677, 6.181724e-08, 0.70710677, 0.0], denominators: [1.0, 6.181724e-8, 0.41421354, 0.0])
    }
    
    static func compositePreemphasis(bandwidthScale: Float) -> IIRTransferFunction {
        let cutoff: Float = (315000000.0 / 88.0 / 2.0) * bandwidthScale
        let rate = NTSC.rate * bandwidthScale
        return lowpassFilter(cutoff: cutoff, rate: rate)
    }
    
    /*
    if self.composite_preemphasis != 0.0 {
        let preemphasis_filter = make_lowpass(
            (315000000.0 / 88.0 / 2.0) * self.bandwidth_scale,
            NTSC_RATE * self.bandwidth_scale,
        );
        filter_plane(
            yiq.y,
            width,
            &preemphasis_filter,
            InitialCondition::Zero,
            -self.composite_preemphasis,
            0,
        );
    }
     */
    
    static func lowpassFilter(cutoff: Float, rate: Float) -> IIRTransferFunction {
        let timeInterval = 1.0 / rate
        let tau = 1.0 / (cutoff * 2.0 * .pi)
        let alpha = timeInterval / (tau + timeInterval)
        
        let numerators: [Float] = [alpha]
        let denominators: [Float] = [1, -(1 - alpha)]
        return IIRTransferFunction(
            numerators: numerators,
            denominators: denominators
        )
    }
    
    static func butterworth(cutoff: Float, rate: Float) -> IIRTransferFunction {
        let newCutoff = min(cutoff, rate * 0.5)
        
        // Calculate normalized frequency
        let omega = 2.0 * .pi * newCutoff / rate
        let cosOmega = cos(omega)
        let sinOmega = sin(omega)
        let alpha = sinOmega / 2.0
        
        // Butterworth filter (Q factor is sqrt(2)/2 for a Butterworth filter)
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cosOmega
        let a2 = 1.0 - alpha
        let b0 = (1.0 - cosOmega) / 2.0
        let b1 = 1.0 - cosOmega
        let b2 = (1.0 - cosOmega) / 2.0
        
        // Normalize coefficients
        let nums = [b0 / a0, b1 / a0, b2 / a0]
        let denoms = [1.0, a1 / a0, a2 / a0]
        
        return IIRTransferFunction(numerators: nums, denominators: denoms)
    }
}

private func trimZeroes<A: Comparable & SignedNumeric>(_ a: [A]) -> [A] {
    var idx = a.count - 1
    while abs(a[idx]) == .zero {
        idx -= 1
    }
    return Array(a[0...idx])
}

extension IIRTransferFunction {
    static func *(lhs: IIRTransferFunction, rhs: IIRTransferFunction) -> IIRTransferFunction {
        let lNums = trimZeroes(lhs.numerators)
        let rNums = trimZeroes(rhs.numerators)
        let nums = polynomialMultiply(lNums, rNums)
        let lDenoms = trimZeroes(lhs.denominators)
        let rDenoms = trimZeroes(rhs.denominators)
        let denoms = polynomialMultiply(lDenoms, rDenoms)
        return IIRTransferFunction(numerators: nums, denominators: denoms)
    }
    
    func cascade(n: UInt) -> IIRTransferFunction {
        var fn = self
        for _ in 0..<n {
            fn = fn * fn
        }
        return fn
    }
}
