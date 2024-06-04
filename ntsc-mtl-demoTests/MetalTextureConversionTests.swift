//
//  MetalTextureConversionTests.swift
//  ntsc-mtl-demoTests
//
//  Created by Jeffrey Blagdon on 2024-06-04.
//

import XCTest
@testable import ntsc_mtl_demo
import Metal

final class MetalTextureConversionTests: XCTestCase {
    enum Error: Swift.Error {
        case noDevice
    }
    
    private var library: MTLLibrary?
    private var texture: MTLTexture?
    private var device: MTLDevice?
    private var ciContext: CIContext?
    private var commandQueue: MTLCommandQueue?

    override func setUpWithError() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw Error.noDevice
        }
        self.device = device
        self.ciContext = CIContext(mtlDevice: device)
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: 1, height: 1, mipmapped: false)
        self.texture = device.makeTexture(descriptor: textureDescriptor)
        self.commandQueue = try XCTUnwrap(device.makeCommandQueue())
        self.library = try XCTUnwrap(device.makeDefaultLibrary())
    }
    
    override func tearDownWithError() throws {
        self.library = nil
        self.commandQueue = nil
        self.texture = nil
        self.ciContext = nil
        self.device = nil
    }
    
    func testMetalRoundTrip() throws {
        let texture = try XCTUnwrap(texture)
        let input: [Float] = [0.5, 0.5, 0.5, 1]
        var rgba = input
        let region = MTLRegionMake2D(0, 0, 1, 1)
        let bytesPerRow: Int = MemoryLayout<Float>.size * 4 * 1
        texture.replace(region: region, mipmapLevel: 0, withBytes: &rgba, bytesPerRow: bytesPerRow)
        var newValue: [Float] = [0, 0, 0, 0]
        texture.getBytes(&newValue, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        XCTAssertEqual(rgba, input)
        XCTAssertEqual(newValue, input)
    }
    
    func testYIQConversion() throws {
        let texture = try XCTUnwrap(texture)
        let input: [Float] = [0.5, 0.5, 0.5, 1]
        var rgba = input
        let region = MTLRegionMake2D(0, 0, 1, 1)
        let bytesPerRow: Int = MemoryLayout<Float>.size * 4 * 1
        texture.replace(region: region, mipmapLevel: 0, withBytes: &rgba, bytesPerRow: bytesPerRow)
        try NTSCTextureFilter.convertToYIQ(
            texture,
            commandQueue: try XCTUnwrap(commandQueue),
            library: try XCTUnwrap(library),
            device: try XCTUnwrap(device)
        )
        // from Rust
        let want: [Float] = [0.5, 0, -1.4901161e-8, 1]
        var got: [Float] = [0, 0, 0, 0]
        texture.getBytes(&got, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        XCTAssertEqual(want, got)
    }
    
    func testRGBConversion() throws {
        let texture = try XCTUnwrap(texture)
        let input: [Float] = [0.5, 0.5, 0.5, 1]
        var yiqa = input
        let region = MTLRegionMake2D(0, 0, 1, 1)
        let bytesPerRow: Int = MemoryLayout<Float>.size * 4 * 1
        texture.replace(region: region, mipmapLevel: 0, withBytes: &yiqa, bytesPerRow: bytesPerRow)
        try NTSCTextureFilter.convertToRGB(
            texture,
            commandQueue: try XCTUnwrap(commandQueue),
            library: try XCTUnwrap(library),
            device: try XCTUnwrap(device)
        )
        // from Rust
        let want: [Float] = [1.2875, 0.040499985, 0.7985, 1]
        var got: [Float] = [0, 0, 0, 0]
        texture.getBytes(&got, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        XCTAssertEqual(want, got)
    }
    
    func testRGBRoundTrip() throws {
        let texture = try XCTUnwrap(texture)
        let input: [Float] = [0.5, 0.5, 0.5, 1]
        var rgba = input
        let region = MTLRegionMake2D(0, 0, 1, 1)
        let bytesPerRow: Int = MemoryLayout<Float>.size * 4 * 1
        texture.replace(region: region, mipmapLevel: 0, withBytes: &rgba, bytesPerRow: bytesPerRow)
        try NTSCTextureFilter.convertToYIQ(
            texture,
            commandQueue: try XCTUnwrap(commandQueue),
            library: try XCTUnwrap(library),
            device: try XCTUnwrap(device)
        )
        try NTSCTextureFilter.convertToRGB(
            texture,
            commandQueue: try XCTUnwrap(commandQueue),
            library: try XCTUnwrap(library),
            device: try XCTUnwrap(device)
        )
        // Expecting not to lose any precision when moving back and forth
        let want: [Float] = input
        var got: [Float] = [0, 0, 0, 0]
        texture.getBytes(&got, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        for idx in input.indices {
            XCTAssertEqual(want[idx], got[idx], accuracy: 0.00001, "Mismatch at index \(idx) -- want \(want[idx]), got \(got[idx])")
        }
    }
}