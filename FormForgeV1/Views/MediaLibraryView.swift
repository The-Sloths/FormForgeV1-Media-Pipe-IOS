import SwiftUI
import PhotosUI
import AVKit
import MediaPipeTasksVision

struct MediaLibraryView: View {
    @StateObject private var poseLandmarkerService: PoseLandmarkerService
    @ObservedObject var inferenceConfig = InferenceConfig.shared
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var selectedVideoURL: URL?
    @State private var selectedImage: UIImage?
    @State private var player: AVPlayer?
    @State private var overlays: [PoseOverlay] = []
    @State private var imageSize: CGSize = .zero
    @State private var isProcessing = false
    @State private var progressValue: Float = 0
    
    init() {
        let config = InferenceConfig.shared
        
        guard let modelPath = config.model.modelPath else {
            fatalError("Model path not found")
        }
        
        let service = PoseLandmarkerService(
            modelPath: modelPath,
            runningMode: .image,
            numPoses: config.numPoses,
            minPoseDetectionConfidence: config.minPoseDetectionConfidence,
            minPosePresenceConfidence: config.minPosePresenceConfidence,
            minTrackingConfidence: config.minTrackingConfidence,
            delegate: config.delegate.delegate
        )
        
        _poseLandmarkerService = StateObject(wrappedValue: service)
    }
    
    var body: some View {
        ZStack {
            // Media display
            if let image = selectedImage {
                GeometryReader { geometry in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .overlay(
                            PoseOverlayView(
                                overlays: overlays,
                                imageSize: imageSize,
                                contentMode: .fit
                            )
                        )
                }
            } else if let player = player {
                VideoPlayer(player: player)
                    .overlay(
                        PoseOverlayView(
                            overlays: overlays,
                            imageSize: imageSize,
                            contentMode: .fit
                        )
                    )
            } else {
                VStack {
                    Text("Select an image or video")
                        .font(.title)
                        .foregroundColor(.gray)
                    
                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .any(of: [.images, .videos])
                    ) {
                        Label("Select from library", systemImage: "photo.on.rectangle")
                            .frame(minWidth: 200, minHeight: 50)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .padding()
                }
            }
            
            // Progress overlay
            if isProcessing {
                Color.black.opacity(0.5)
                    .overlay(
                        VStack {
                            ProgressView(value: progressValue, total: 1.0)
                                .frame(width: 200)
                                .padding()
                            Text("Processing...")
                                .foregroundColor(.white)
                        }
                    )
            }
            
            // Bottom settings panel
            VStack {
                Spacer()
                SettingsPanelView()
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    .padding()
            }
        }
        .onChange(of: selectedItem) { item in
            Task {
                if let item = item {
                    await loadTransferable(from: item)
                }
            }
        }
        .onReceive(poseLandmarkerService.$resultBundle) { resultBundle in
            if let resultBundle = resultBundle,
               let poseLandmarkerResult = resultBundle.poseLandmarkerResults.first as? PoseLandmarkerResult {
                overlays = PoseOverlayView.createPoseOverlays(
                    from: poseLandmarkerResult.landmarks,
                    imageSize: imageSize
                )
            }
        }
    }
    
    private func loadTransferable(from item: PhotosPickerItem) async {
        // Reset previous selection
        selectedImage = nil
        selectedVideoURL = nil
        player = nil
        overlays = []
        
        do {
            // Try loading as image
            if let data = try await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                
                await MainActor.run {
                    selectedImage = uiImage
                    imageSize = uiImage.size
                    isProcessing = true
                }
                
                // Process image with PoseLandmarker
                let result = poseLandmarkerService.detect(image: uiImage)
                if let result = result,
                   let poseLandmarkerResult = result.poseLandmarkerResults.first as? PoseLandmarkerResult {
                    
                    await MainActor.run {
                        overlays = PoseOverlayView.createPoseOverlays(
                            from: poseLandmarkerResult.landmarks,
                            imageSize: imageSize
                        )
                        isProcessing = false
                    }
                } else {
                    await MainActor.run {
                        isProcessing = false
                    }
                }
                return
            }
            
            // Try loading as video
            if let videoURL = try await item.loadTransferable(type: URL.self) {
                await MainActor.run {
                    selectedVideoURL = videoURL
                    player = AVPlayer(url: videoURL)
                    isProcessing = true
                }
                
                // Process video with PoseLandmarker
                let asset = AVAsset(url: videoURL)
                let result = await poseLandmarkerService.detect(videoAsset: asset) { progress in
                    self.progressValue = progress
                }
                
                if let result = result {
                    await MainActor.run {
                        imageSize = result.size
                        isProcessing = false
                        
                        // Set up video player observer to update overlays at appropriate times
                        setupVideoObserver(with: result)
                    }
                } else {
                    await MainActor.run {
                        isProcessing = false
                    }
                }
            }
        } catch {
            print("Failed to load media: \(error)")
            await MainActor.run {
                isProcessing = false
            }
        }
    }
    
    private func setupVideoObserver(with result: ResultBundle) {
        guard let player = player else { return }
        
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        
        player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = CMTimeGetSeconds(time)
            let index = Int(seconds * 10) // Assuming 10 fps (0.1s interval)
            
            if index < result.poseLandmarkerResults.count,
               let poseLandmarkerResult = result.poseLandmarkerResults[index] as? PoseLandmarkerResult {
                
                overlays = PoseOverlayView.createPoseOverlays(
                    from: poseLandmarkerResult.landmarks,
                    imageSize: imageSize
                )
            }
        }
        
        player.play()
    }
}