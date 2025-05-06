import SwiftUI

struct MainView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            CameraView()
                .tabItem {
                    Label("Camera", systemImage: "camera")
                }
                .tag(0)
            
            MediaLibraryView()
                .tabItem {
                    Label("Library", systemImage: "photo.on.rectangle")
                }
                .tag(1)
        }
        .onAppear {
            // Ensure models are downloaded
            // You can call your model download function here or do it in App startup
        }
    }
}