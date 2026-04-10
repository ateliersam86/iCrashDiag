import SwiftUI
import AppKit

struct DeviceScreenshotBackground: View {
    let screenshotPath: String?
    @State private var image: NSImage? = nil

    var body: some View {
        ZStack {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 45)
                    .saturation(0.7)
                    .brightness(-0.1)
                    .ignoresSafeArea()
                    .clipped()
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.07, blue: 0.15),
                        Color(red: 0.12, green: 0.10, blue: 0.22),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            // Dark veil for readability
            Color.black.opacity(0.4).ignoresSafeArea()
        }
        .onAppear { loadImage() }
        .onChange(of: screenshotPath) { loadImage() }
    }

    private func loadImage() {
        guard let path = screenshotPath else { return }
        Task.detached(priority: .userInitiated) {
            let img = NSImage(contentsOfFile: path)
            await MainActor.run { self.image = img }
        }
    }
}
