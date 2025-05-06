//
//  WallSlideExercise.swift
//  FormForgeV1
//
//  Created by Pawel Kowalewski on 06/05/2025.
//

import SwiftUI
import Foundation
import MediaPipeTasksVision
import UIKit

class WallSlideExercise: Exercise {
    let name = "Wall Slide"
    let description = "Stand with your back against a wall, slide down into a squat position with arms raised, then return to standing."
    let targetReps: Int
    let referenceImages: [UIImage]?
    let referenceVideo: URL?
    
    // Angle thresholds for proper form
    private let minKneeAngle: Float = 80.0
    private let maxKneeAngle: Float = 160.0
    private let properBackAngle: Float = 180.0
    private let backAngleTolerance: Float = 15.0
    private let minArmRaiseAngle: Float = 150.0
    
    // State tracking for rep counting
    private var isInBottomPosition = false
    private let bottomPositionKneeAngleThreshold: Float = 100.0
    private let topPositionKneeAngleThreshold: Float = 150.0
    
    init(targetReps: Int = 10, referenceImages: [UIImage]? = nil, referenceVideo: URL? = nil) {
        self.targetReps = targetReps
        self.referenceImages = referenceImages
        self.referenceVideo = referenceVideo
    }
    
    // Form check implementation
    func checkForm(landmarks: [[NormalizedLandmark]]) -> String? {
        guard !landmarks.isEmpty else { return nil }
        
        let poseLandmarks = landmarks[0] // Get first detected pose
        
        // Calculate key angles
        let kneeAngle = calculateKneeAngle(landmarks: poseLandmarks)
        let backAngle = calculateBackAngle(landmarks: poseLandmarks)
        let armAngle = calculateArmAngle(landmarks: poseLandmarks)
        
        // Check form issues and return feedback
        if kneeAngle < minKneeAngle {
            return "Knees are bent too much. Don't go too low."
        }
        
        if abs(backAngle - properBackAngle) > backAngleTolerance {
            return "Keep your back straight against the wall."
        }
        
        if armAngle < minArmRaiseAngle {
            return "Raise your arms higher."
        }
        
        return nil // No form issues
    }
    
    // Rep detection implementation
    func detectRepetition(currentLandmarks: [[NormalizedLandmark]], previousLandmarks: [[NormalizedLandmark]]?) -> Bool {
        guard !currentLandmarks.isEmpty else { return false }
        
        let poseLandmarks = currentLandmarks[0]
        let kneeAngle = calculateKneeAngle(landmarks: poseLandmarks)
        
        // Detect bottom position (squat)
        if !isInBottomPosition && kneeAngle <= bottomPositionKneeAngleThreshold {
            isInBottomPosition = true
            return false
        }
        
        // Detect return to top position (standing) - this completes a rep
        if isInBottomPosition && kneeAngle >= topPositionKneeAngleThreshold {
            isInBottomPosition = false
            return true // Rep completed
        }
        
        return false
    }
    
    // Helper function to calculate knee angle
    private func calculateKneeAngle(landmarks: [NormalizedLandmark]) -> Float {
        // Using hip, knee, and ankle landmarks to calculate angle
        let hipLandmark = landmarks[PoseLandmarkerHelper.Landmark.rightHip.rawValue]
        let kneeLandmark = landmarks[PoseLandmarkerHelper.Landmark.rightKnee.rawValue]
        let ankleLandmark = landmarks[PoseLandmarkerHelper.Landmark.rightAnkle.rawValue]
        
        return calculateAngle(
            point1: CGPoint(x: CGFloat(hipLandmark.x), y: CGFloat(hipLandmark.y)),
            point2: CGPoint(x: CGFloat(kneeLandmark.x), y: CGFloat(kneeLandmark.y)),
            point3: CGPoint(x: CGFloat(ankleLandmark.x), y: CGFloat(ankleLandmark.y))
        )
    }
    
    private func calculateBackAngle(landmarks: [NormalizedLandmark]) -> Float {
        // Calculate angle between shoulders and hips
        let shoulderLandmark = landmarks[PoseLandmarkerHelper.Landmark.rightShoulder.rawValue]
        let hipLandmark = landmarks[PoseLandmarkerHelper.Landmark.rightHip.rawValue]
        let kneeLandmark = landmarks[PoseLandmarkerHelper.Landmark.rightKnee.rawValue]
        
        return calculateAngle(
            point1: CGPoint(x: CGFloat(shoulderLandmark.x), y: CGFloat(shoulderLandmark.y)),
            point2: CGPoint(x: CGFloat(hipLandmark.x), y: CGFloat(hipLandmark.y)),
            point3: CGPoint(x: CGFloat(kneeLandmark.x), y: CGFloat(kneeLandmark.y))
        )
    }
    
    private func calculateArmAngle(landmarks: [NormalizedLandmark]) -> Float {
        // Calculate angle of arms (shoulder-elbow-wrist)
        let shoulderLandmark = landmarks[PoseLandmarkerHelper.Landmark.rightShoulder.rawValue]
        let elbowLandmark = landmarks[PoseLandmarkerHelper.Landmark.rightElbow.rawValue]
        let wristLandmark = landmarks[PoseLandmarkerHelper.Landmark.rightWrist.rawValue]
        
        return calculateAngle(
            point1: CGPoint(x: CGFloat(shoulderLandmark.x), y: CGFloat(shoulderLandmark.y)),
            point2: CGPoint(x: CGFloat(elbowLandmark.x), y: CGFloat(elbowLandmark.y)),
            point3: CGPoint(x: CGFloat(wristLandmark.x), y: CGFloat(wristLandmark.y))
        )
    }
    
    // General function to calculate angle between three points
    private func calculateAngle(point1: CGPoint, point2: CGPoint, point3: CGPoint) -> Float {
        let vector1 = CGPoint(x: point1.x - point2.x, y: point1.y - point2.y)
        let vector2 = CGPoint(x: point3.x - point2.x, y: point3.y - point2.y)
        
        let dot = vector1.x * vector2.x + vector1.y * vector2.y
        let det = vector1.x * vector2.y - vector1.y * vector2.x
        
        let angle = atan2(det, dot)
        return abs(Float(angle) * (180.0 / Float.pi))
    }
}

// Helper enum to access landmark indices
enum PoseLandmarkerHelper {
    enum Landmark: Int {
        case nose = 0
        case leftEye = 1
        case rightEye = 2
        case leftEar = 3
        case rightEar = 4
        case leftShoulder = 5
        case rightShoulder = 6
        case leftElbow = 7
        case rightElbow = 8
        case leftWrist = 9
        case rightWrist = 10
        case leftHip = 11
        case rightHip = 12
        case leftKnee = 13
        case rightKnee = 14
        case leftAnkle = 15
        case rightAnkle = 16
        // Add more as needed
    }
}
