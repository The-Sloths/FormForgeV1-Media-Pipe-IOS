//
//  CameraView.swift
//  FormForgeV1
//
//  Created by Pawel Kowalewski on 06/05/2025.
//


import SwiftUI
import AVFoundation
import MediaPipeTasksVision

struct CameraView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var poseLandmarkerService: PoseLandmarkerService
    @StateObject private var exerciseTracker = ExerciseTracker()
    @ObservedObject var inferenceConfig = InferenceConfig.shared
    
    @State private var overlays: [PoseOverlay] = []
    @State private var imageSize: CGSize = .zero
    @State private var showExerciseSelection = false
    init() {
        let config = InferenceConfig.shared
        
        guard let modelPath = config.model.modelPath else {
            fatalError("Model path not found")
        }
        
        let service = PoseLandmarkerService(
            modelPath: modelPath,
            runningMode: .liveStream,
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
            // Camera preview
            if let frame = cameraManager.frame {
                GeometryReader { geometry in
                    Image(frame, scale: 1.0, orientation: .up, label: Text("Camera"))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .overlay(
                            PoseOverlayView(
                                overlays: overlays,
                                imageSize: imageSize,
                                contentMode: .fill
                            )
                        )
                }
                
                if exerciseTracker.isExerciseActive {
                                ExerciseView(
                                    exerciseTracker: exerciseTracker,
                                    poseLandmarkerService: poseLandmarkerService
                                )
                            } else {
                                // Exercise selection button
                                VStack {
                                    Spacer()
                                    Button(action: {
                                        showExerciseSelection = true
                                    }) {
                                        Text("Start Exercise")
                                            .font(.headline)
                                            .padding()
                                            .background(Color.blue)
                                            .foregroundColor(.white)
                                            .cornerRadius(10)
                                    }
                                    .padding(.bottom, 100)
                                }
                            }
                
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            cameraManager.switchCamera()
                        }) {
                            Image(systemName: "camera.rotate")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 40)
                    }
                    Spacer()
                }
                .sheet(isPresented: $showExerciseSelection) {
                            ExerciseSelectionView(exerciseTracker: exerciseTracker)
                        }
            } else {
                Color.black
                    .overlay(
                        Text("Camera initializing...")
                            .foregroundColor(.white)
                    )
            }
            
            // Settings panel at the bottom
            VStack {
                Spacer()
                SettingsPanelView(poseLandmarkerService: poseLandmarkerService)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    .padding()
            }
        }
        .onAppear {
            cameraManager.checkPermissions()
        }
        .onReceive(poseLandmarkerService.$resultBundle) { resultBundle in
            if let resultBundle = resultBundle,
               let poseLandmarkerResult = resultBundle.poseLandmarkerResults.first as? PoseLandmarkerResult {
                imageSize = cameraManager.videoResolution
                overlays = PoseOverlayView.createPoseOverlays(
                    from: poseLandmarkerResult.landmarks,
                    imageSize: imageSize,
                    orientation: .up
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateOverlaysForCurrentOrientation()
        }
        .onChange(of: cameraManager.frame) { frame in
            if let frame = frame {
                let uiImage = UIImage(cgImage: frame)  // This is not optional
                processFrame(uiImage)
            }
        }
    }
    
    private func processFrame(_ image: UIImage) {
        // Convert UIImage to sample buffer and process
        let orientation = UIImage.Orientation.from(deviceOrientation: UIDevice.current.orientation)
        
        if let cgImage = image.cgImage {
            let ciImage = CIImage(cgImage: cgImage)
            let context = CIContext()
            let pixelBuffer = context.createPixelBuffer(from: ciImage)
            
            if let pixelBuffer = pixelBuffer {
                poseLandmarkerService.detectAsync(pixelBuffer: pixelBuffer, orientation: orientation)
            }
        }
    }
    
    private func updateOverlaysForCurrentOrientation() {
        // If needed, update overlays based on device orientation
        if let resultBundle = poseLandmarkerService.resultBundle,
           let poseLandmarkerResult = resultBundle.poseLandmarkerResults.first as? PoseLandmarkerResult {
            imageSize = cameraManager.videoResolution
            overlays = PoseOverlayView.createPoseOverlays(
                from: poseLandmarkerResult.landmarks,
                imageSize: imageSize,
                orientation: UIImage.Orientation.from(deviceOrientation: UIDevice.current.orientation)
            )
        }
    }
}

// Extension to handle device orientation
extension UIImage.Orientation {
    static func from(deviceOrientation: UIDeviceOrientation) -> UIImage.Orientation {
        switch deviceOrientation {
        case .portrait:
            return .up
        case .landscapeLeft:
            return .left
        case .landscapeRight:
            return .right
        default:
            return .up
        }
    }
}

// CIContext extension for creating pixel buffers
extension CIContext {
    func createPixelBuffer(from ciImage: CIImage) -> CVPixelBuffer? {
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(ciImage.extent.width),
            Int(ciImage.extent.height),
            kCVPixelFormatType_32BGRA,
            attributes,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        let context = CIContext()
        context.render(ciImage, to: buffer)
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return buffer
    }
}

struct ExerciseSelectionView: View {
    @ObservedObject var exerciseTracker: ExerciseTracker
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List {
                Button("Wall Slide - 10 reps") {
                    exerciseTracker.startExercise(WallSlideExercise(targetReps: 10))
                    presentationMode.wrappedValue.dismiss()
                }
                // Add more exercises here as you implement them
            }
            .navigationTitle("Select Exercise")
            .navigationBarItems(trailing: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
