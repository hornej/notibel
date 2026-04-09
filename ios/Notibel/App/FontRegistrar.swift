import CoreText
import Foundation

enum FontRegistrar {
    static func registerBundledFonts() {
        registerFont(named: "BerkeleyMono-Regular", fileExtension: "ttf")
    }

    private static func registerFont(named name: String, fileExtension: String) {
        guard let fontURL = Bundle.main.url(forResource: name, withExtension: fileExtension) else {
            return
        }

        CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
    }
}
