#!/usr/bin/env swift
// Genera las variantes del icono macOS según la plantilla de Apple:
// el artwork ocupa ~840 de ancho visible dentro de un lienzo de 1024x1024 (margen transparente
// ~85px) con una sombra suave. Uso: swift scripts/make_icons.swift <source.png> <appiconset-dir> <out.iconset-dir>
import AppKit

let args = CommandLine.arguments
guard args.count == 4, let src = NSImage(contentsOfFile: args[1]),
      let srcCG = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("uso: make_icons.swift <source.png> <appiconset-dir> <iconset-dir>"); exit(1)
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let art = s * 856 / 1024
    let rect = CGRect(x: (s - art) / 2, y: (s - art) / 2, width: art, height: art)
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 10 / 1024), blur: s * 20 / 1024,
                  color: CGColor(gray: 0, alpha: 0.30))
    ctx.draw(srcCG, in: rect)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
try? fm.removeItem(atPath: args[3])
try fm.createDirectory(atPath: args[3], withIntermediateDirectories: true)

// appiconset: nombres usados por Contents.json
for px in [16, 32, 64, 128, 256, 512, 1024] {
    try render(px).write(to: URL(fileURLWithPath: "\(args[2])/icon_\(px)x\(px).png"))
}
// iconset para iconutil
let sets: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sets {
    try render(px).write(to: URL(fileURLWithPath: "\(args[3])/\(name).png"))
}
