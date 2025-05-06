//
//  PushupExercise.swift
//  FormForgeV1
//
//  Created by Pawel Kowalewski on 06/05/2025.
//


import Foundation
import MediaPipeTasksVision
import UIKit

class PushupExercise: Exercise {
    let name = "Pushups"
    let description = "Start in plank position, lower body until chest nearly touches ground, then push back up."
    let targetReps: Int
    let referenceImages: [UIImage]?
    let referenceVideo: URL?
    
    // Thresholds for detecting pushups
    private let bottomElbowAngleThreshold: Float = 90.0  // Lower angle when in bottom position
    private let topElbowAngleThreshold: Float = 160.0    // Higher angle when in top position
    private let confidenceThreshold: Float = 0.7         // Minimum landmark visibility
    
    // State tracking
    private var isInBottomPosition = false
    private var consecutiveTopFrames = 0
    private var consecutiveBottomFrames = 0
    private let requiredConsecutiveFrames = 3
    
    // For detecting bad form
    private let minBackStraightnessAngle: Float = 160.0  // Back should be straight
    private let backStraightnessTolerance: Float = 20.0  // Tolerance for back angle
    
    init(targetReps: Int = 10, referenceImages: [UIImage]? = nil, referenceVideo: URL? = nil) {
        self.targetReps = targetReps
        self.referenceImages = referenceImages
        self.referenceVideo = referenceVideo
    }
    
    func checkForm(landmarks: [[NormalizedLandmark]]) -> String? {
        guard !landmarks.isEmpty, areLandmarksVisible(landmarks[0]) else { return nil }
        
        let poseLandmarks = landmarks[0]
        
        // Check if back is straight (shoulders, hips, and ankles alignment)
        let backStraightness = calculateBackStraightness(landmarks: poseLandmarks)
        if abs(backStraightness - 180.0) > backStraightnessTolerance {
            if backStraightness < minBackStraightnessAngle {
                return "Hips too low. Keep body straight."
            } else {
                return "Hips too high. Lower body to straight position."
            }
        }
        
        // Check elbow positioning (shouldn't flare out too much)
        let elbowAlignment = checkElbowAlignment(landmarks: poseLandmarks)
        if elbowAlignment > 30.0 {
            return "Elbows flaring too wide. Keep them closer to body."
        }
        
        return nil // No form issues
    }
    
    func detectRepetition(currentLandmarks: [[NormalizedLandmark]], previousLandmarks: [[NormalizedLandmark]]?) -> Bool {
        guard !currentLandmarks.isEmpty, areLandmarksVisible(currentLandmarks[0]) else { return false }
        
        let poseLandmarks = currentLandmarks[0]
        let elbowAngle = calculateElbowAngle(landmarks: poseLandmarks)
        
        // Detect bottom position (body lowered)
        if !isInBottomPosition && elbowAngle <= bottomElbowAngleThreshold {
            consecutiveBottomFrames += 1
            if consecutiveBottomFrames >= requiredConsecutiveFrames {
                isInBottomPosition = true
                consecutiveBottomFrames = 0
                consecutiveTopFrames = 0
            }
            return false
        } else if !isInBottomPosition {
            consecutiveBottomFrames = 0
        }
        
        // Detect top position (arms extended)
        if isInBottomPosition && elbowAngle >= topElbowAngleThreshold {
            consecutiveTopFrames += 1
            if consecutiveTopFrames >= requiredConsecutiveFrames {
                isInBottomPosition = false
                consecutiveTopFrames = 0
                consecutiveBottomFrames = 0
                return true // Rep completed
            }
            return false
        } else if isInBottomPosition {
            consecutiveTopFrames = 0
        }
        
        return false
    }
    
    // Helper methods
    private func areLandmarksVisible(_ landmarks: [NormalizedLandmark]) -> Bool {
        let keyIndices = [
            PoseLandmarkerHelper.Landmark.leftShoulder.rawValue,
            PoseLandmarkerHelper.Landmark.rightShoulder.rawValue,
            PoseLandmarkerHelper.Landmark.leftElbow.rawValue,
            PoseLandmarkerHelper.Landmark.rightElbow.rawValue,
            PoseLandmarkerHelper.Landmark.leftWrist.rawValue,
            PoseLandmarkerHelper.Landmark.rightWrist.rawValue,
            PoseLandmarkerHelper.Landmark.leftHip.rawValue,
            PoseLandmarkerHelper.Landmark.rightHip.rawValue
        ]
        
        for index in keyIndices {
            if index >= landmarks.count || landmarks[index].visibility?.floatValue ?? 0 < confidenceThreshold {
                return false
            }
        }
        
        return true
    }
    
    private func calculateElbowAngle(landmarks: [NormalizedLandmark]) -> Float {
        // Average of both elbows for more stable detection
        let leftElbowAngle = PoseLandmarkerHelper.calculateAngle(
            point1: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftShoulder.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftShoulder.rawValue].y)),
            point2: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftElbow.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftElbow.rawValue].y)),
            point3: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftWrist.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftWrist.rawValue].y))
        )
        
        let rightElbowAngle = PoseLandmarkerHelper.calculateAngle(
            point1: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightShoulder.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightShoulder.rawValue].y)),
            point2: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightElbow.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightElbow.rawValue].y)),
            point3: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightWrist.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightWrist.rawValue].y))
        )
        
        return (leftElbowAngle + rightElbowAngle) / 2.0
    }
    
    private func calculateBackStraightness(landmarks: [NormalizedLandmark]) -> Float {
        // Calculate angle between shoulders, hips, and ankles to determine back straightness
        let shoulderMidpoint = CGPoint(
            x: (CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftShoulder.rawValue].x) + 
                CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightShoulder.rawValue].x)) / 2.0,
            y: (CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftShoulder.rawValue].y) + 
                CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightShoulder.rawValue].y)) / 2.0
        )
        
        let hipMidpoint = CGPoint(
            x: (CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftHip.rawValue].x) + 
                CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightHip.rawValue].x)) / 2.0,
            y: (CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftHip.rawValue].y) + 
                CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightHip.rawValue].y)) / 2.0
        )
        
        let ankleMidpoint = CGPoint(
            x: (CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftAnkle.rawValue].x) + 
                CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightAnkle.rawValue].x)) / 2.0,
            y: (CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftAnkle.rawValue].y) + 
                CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightAnkle.rawValue].y)) / 2.0
        )
        
        return PoseLandmarkerHelper.calculateAngle(
            point1: shoulderMidpoint,
            point2: hipMidpoint,
            point3: ankleMidpoint
        )
    }
    
    private func checkElbowAlignment(landmarks: [NormalizedLandmark]) -> Float {
        // Check how much elbows are flaring out (angle between shoulders, elbows, and hips)
        let leftElbowAlignment = PoseLandmarkerHelper.calculateAngle(
            point1: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftShoulder.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftShoulder.rawValue].y)),
            point2: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftElbow.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftElbow.rawValue].y)),
            point3: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftHip.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftHip.rawValue].y))
        )
        
        let rightElbowAlignment = PoseLandmarkerHelper.calculateAngle(
            point1: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightShoulder.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightShoulder.rawValue].y)),
            point2: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightElbow.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightElbow.rawValue].y)),
            point3: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightHip.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightHip.rawValue].y))
        )
        
        return (leftElbowAlignment + rightElbowAlignment) / 2.0
    }
}
