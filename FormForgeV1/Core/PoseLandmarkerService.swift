import Foundation
import MediaPipeTasksVision
import Combine
import UIKit
import AVFoundation

class PoseLandmarkerService: ObservableObject {
    enum LandmarkerError: Error {
        case failedToCreateLandmarker
        case failedToDetect
        case invalidImage
    }
    
    @Published var resultBundle: ResultBundle?
    @Published var inferenceTime: Double = 0
    
    private var poseLandmarker: PoseLandmarker?
    private var runningMode: RunningMode
    
    init(
        modelPath: String,
        runningMode: RunningMode = .liveStream,
        numPoses: Int = 1,
        minPoseDetectionConfidence: Float = 0.5,
        minPosePresenceConfidence: Float = 0.5,
        minTrackingConfidence: Float = 0.5,
        delegate: Delegate = .CPU
    ) {
        self.runningMode = runningMode
        createPoseLandmarker(
            modelPath: modelPath,
            runningMode: runningMode,
            numPoses: numPoses,
            minPoseDetectionConfidence: minPoseDetectionConfidence,
            minPosePresenceConfidence: minPosePresenceConfidence,
            minTrackingConfidence: minTrackingConfidence,
            delegate: delegate
        )
    }
    
    private func createPoseLandmarker(
        modelPath: String,
        runningMode: RunningMode,
        numPoses: Int,
        minPoseDetectionConfidence: Float,
        minPosePresenceConfidence: Float,
        minTrackingConfidence: Float,
        delegate: Delegate
    ) {
        let poseLandmarkerOptions = PoseLandmarkerOptions()
        poseLandmarkerOptions.runningMode = runningMode
        poseLandmarkerOptions.numPoses = numPoses
        poseLandmarkerOptions.minPoseDetectionConfidence = minPoseDetectionConfidence
        poseLandmarkerOptions.minPosePresenceConfidence = minPosePresenceConfidence
        poseLandmarkerOptions.minTrackingConfidence = minTrackingConfidence
        poseLandmarkerOptions.baseOptions.modelAssetPath = modelPath
        poseLandmarkerOptions.baseOptions.delegate = delegate
        
        if runningMode == .liveStream {
            poseLandmarkerOptions.poseLandmarkerLiveStreamDelegate = self
        }
        
        do {
            poseLandmarker = try PoseLandmarker(options: poseLandmarkerOptions)
        } catch {
            print("Failed to create pose landmarker: \(error)")
        }
    }
    
    func detect(image: UIImage) -> ResultBundle? {
        guard let mpImage = try? MPImage(uiImage: image) else {
            return nil
        }
        
        do {
            let startDate = Date()
            let result = try poseLandmarker?.detect(image: mpImage)
            let inferenceTime = Date().timeIntervalSince(startDate) * 1000
            let resultBundle = ResultBundle(inferenceTime: inferenceTime, poseLandmarkerResults: [result])
            
            DispatchQueue.main.async {
                self.resultBundle = resultBundle
                self.inferenceTime = inferenceTime
            }
            
            return resultBundle
        } catch {
            print("Failed to detect pose: \(error)")
            return nil
        }
    }
    
    func detectAsync(sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation) {
        guard let image = try? MPImage(sampleBuffer: sampleBuffer, orientation: orientation) else {
            return
        }
        
        do {
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            try poseLandmarker?.detectAsync(image: image, timestampInMilliseconds: timestamp)
        } catch {
            print("Failed to detect pose asynchronously: \(error)")
        }
    }
    
    func detectAsync(pixelBuffer: CVPixelBuffer, orientation: UIImage.Orientation) {
        do {
            let mpImage = try MPImage(pixelBuffer: pixelBuffer, orientation: orientation)
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            try poseLandmarker?.detectAsync(image: mpImage, timestampInMilliseconds: timestamp)
        } catch {
            print("Failed to detect pose on pixel buffer: \(error)")
        }
    }
    
    // For video processing
    func detect(videoAsset: AVAsset, progressHandler: @escaping (Float) -> Void) async -> ResultBundle? {
        let generator = AVAssetImageGenerator(asset: videoAsset)
        generator.requestedTimeToleranceBefore = CMTimeMake(value: 1, timescale: 25)
        generator.requestedTimeToleranceAfter = CMTimeMake(value: 1, timescale: 25)
        generator.appliesPreferredTrackTransform = true
        
        guard let videoDuration = try? await videoAsset.load(.duration) else {
            return nil
        }
        
        let durationInSeconds = CMTimeGetSeconds(videoDuration)
        let frameInterval = 0.1 // Process a frame every 100ms
        let frameCount = Int(durationInSeconds / frameInterval)
        
        var poseLandmarkerResults: [PoseLandmarkerResult?] = []
        var videoSize = CGSize.zero
        let startDate = Date()
        
        for i in 0..<frameCount {
            let time = CMTimeMakeWithSeconds(Double(i) * frameInterval, preferredTimescale: 600)
            do {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                let uiImage = UIImage(cgImage: cgImage)
                videoSize = uiImage.size
                
                if let mpImage = try? MPImage(uiImage: uiImage) {
                    let result = try poseLandmarker?.detect(videoFrame: mpImage, timestampInMilliseconds: Int(time.seconds * 1000))
                    poseLandmarkerResults.append(result)
                }
                
                // Report progress
                let progress = Float(i) / Float(frameCount)
                DispatchQueue.main.async {
                    progressHandler(progress)
                }
            } catch {
                print("Error generating frame at time \(time): \(error)")
            }
        }
        
        let inferenceTime = Date().timeIntervalSince(startDate) / Double(frameCount) * 1000
        let result = ResultBundle(inferenceTime: inferenceTime, poseLandmarkerResults: poseLandmarkerResults, size: videoSize)
        
        DispatchQueue.main.async {
            self.resultBundle = result
            self.inferenceTime = inferenceTime
        }
        
        return result
    }
}

// MARK: - PoseLandmarkerLiveStreamDelegate
extension PoseLandmarkerService: PoseLandmarkerLiveStreamDelegate {
    func poseLandmarker(_ poseLandmarker: PoseLandmarker, didFinishDetection result: PoseLandmarkerResult?, timestampInMilliseconds: Int, error: (any Error)?) {
        let resultBundle = ResultBundle(
            inferenceTime: Date().timeIntervalSince1970 * 1000 - Double(timestampInMilliseconds),
            poseLandmarkerResults: [result]
        )
        
        DispatchQueue.main.async { [weak self] in
            self?.resultBundle = resultBundle
            self?.inferenceTime = resultBundle.inferenceTime
        }
    }
}

// Result bundle struct
struct ResultBundle {
    let inferenceTime: Double
    let poseLandmarkerResults: [PoseLandmarkerResult?]
    var size: CGSize = .zero
}