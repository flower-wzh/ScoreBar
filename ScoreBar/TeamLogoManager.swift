import SwiftUI
import AppKit

class TeamLogoManager {
    static let shared = TeamLogoManager()

    private init() {}

    // Check if local asset exists
    func localImage(tricode: String) -> NSImage? {
        let name = "TeamLogos/\(tricode)"
        if let image = NSImage(named: name) {
            return image
        }
        return nil
    }

    // Get logo view - local first, then network fallback
    @ViewBuilder
    func logoView(tricode: String, networkURL: String, size: CGFloat = 24) -> some View {
        let name = "TeamLogos/\(tricode)"
        if NSImage(named: name) != nil {
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            AsyncImage(url: URL(string: networkURL)) { phase in
                switch phase {
                case .empty:
                    // Show tricode text while loading
                    Text(tricode)
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: size, height: size)
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    // Show tricode text on failure
                    Text(tricode)
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: size, height: size)
                @unknown default:
                    Text(tricode)
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: size, height: size)
                }
            }
            .frame(width: size, height: size)
        }
    }
}