//
//  PoseLandmarkerService.swift
//  FormForgeV1
//
//  Created by Pawel Kowalewski on 06/05/2025.
//


import Foundation
import MediaPipeTasksVision
import Combine
import UIKit
import AVFoundation

class PoseLandmarkerService: NSObject, ObservableObject {
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
        super.init()  // Call super.init() before using self
        
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

enum PoseLandmarkerHelper {
    enum Landmark: Int, CaseIterable {
            case nose = 0
            case leftEyeInner = 1
            case leftEye = 2
            case leftEyeOuter = 3
            case rightEyeInner = 4
            case rightEye = 5
            case rightEyeOuter = 6
            case leftEar = 7
            case rightEar = 8
            case mouthLeft = 9
            case mouthRight = 10
            case leftShoulder = 11
            case rightShoulder = 12
            case leftElbow = 13
            case rightElbow = 14
            case leftWrist = 15
            case rightWrist = 16
            case leftPinky = 17 // Often named leftPinkyFingerMCP or similar
            case rightPinky = 18// Often named rightPinkyFingerMCP or similar
            case leftIndex = 19 // Often named leftIndexFingerMCP or similar
            case rightIndex = 20// Often named rightIndexFingerMCP or similar
            case leftThumb = 21 // Often named leftThumbMCP or similar
            case rightThumb = 22// Often named rightThumbMCP or similar
            case leftHip = 23
            case rightHip = 24
            case leftKnee = 25
            case rightKnee = 26
            case leftAnkle = 27
            case rightAnkle = 28
            case leftHeel = 29
            case rightHeel = 30
            case leftFootIndex = 31 // Tip of the foot
            case rightFootIndex = 32// Tip of the foot

            var stringValue: String {
                return "\(self)"
            }
    }
    
    // Calculate angle between three points
    static func calculateAngle(point1: CGPoint, point2: CGPoint, point3: CGPoint) -> Float {
        let vector1 = CGPoint(x: point1.x - point2.x, y: point1.y - point2.y)
        let vector2 = CGPoint(x: point3.x - point2.x, y: point3.y - point2.y)
        
        let dot = vector1.x * vector2.x + vector1.y * vector2.y
        let det = vector1.x * vector2.y - vector1.y * vector2.x
        
        let angle = atan2(det, dot)
        return abs(Float(angle) * (180.0 / Float.pi))
    }
}
