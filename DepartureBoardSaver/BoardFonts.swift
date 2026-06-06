//
//  BoardFonts.swift
//  DepartureBoardSaver
//
//  Created by Justyn Henman on 06/06/2026.
//
import CoreText
import AppKit

// MARK: - Font loading
public struct BoardFonts {
    let regular:   NSFont
    let bold:      NSFont
    let boldTall:  NSFont
    let boldLarge: NSFont

    init(bundle: Bundle) {
        regular   = Self.load("Dot Matrix Regular",   size: 10, bundle: bundle)
        bold      = Self.load("Dot Matrix Bold",      size: 10, bundle: bundle)
        boldTall  = Self.load("Dot Matrix Bold Tall", size: 10, bundle: bundle)
        boldLarge = Self.load("Dot Matrix Bold",      size: 20, bundle: bundle)
    }

    // Load directly from the bundle URL to bypass PostScript-name guessing.
    // Searches both the bundle root and a Fonts/ subdirectory.
    private static func load(_ name: String, size: CGFloat, bundle: Bundle) -> NSFont {
        let url = bundle.url(forResource: name, withExtension: "ttf")
               ?? bundle.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
        if let url,
           let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
           let desc = descs.first {
            return CTFontCreateWithFontDescriptor(desc, size, nil) as NSFont
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
