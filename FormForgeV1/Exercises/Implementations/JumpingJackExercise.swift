//
//  JumpingJackExercise.swift
//  FormForgeV1
//
//  Created by Pawel Kowalewski on 06/05/2025.
//


import Foundation
import MediaPipeTasksVision
import UIKit

class JumpingJackExercise: Exercise {
    let name = "Jumping Jacks"
    let description = "Start with feet together and arms at sides, jump to spread legs and raise arms overhead, then return to starting position."
    let targetReps: Int
    let referenceImages: [UIImage]?
    let referenceVideo: URL?
    
    // Thresholds for detecting jumping jacks
    private let armRaisedAngleThreshold: Float = 150.0  // Higher angle when arms raised
    private let armLoweredAngleThreshold: Float = 60.0  // Lower angle when arms at sides
    private let legSpreadThreshold: Float = 0.25        // Distance between ankles when legs spread
    private let legClosedThreshold: Float = 0.1         // Distance between ankles when legs together
    private let confidenceThreshold: Float = 0.7        // Minimum landmark visibility
    
    // State tracking
    private var isInOpenPosition = false
    private var consecutiveOpenFrames = 0
    private var consecutiveClosedFrames = 0
    private let requiredConsecutiveFrames = 3
    
    init(targetReps: Int = 10, referenceImages: [UIImage]? = nil, referenceVideo: URL? = nil) {
        self.targetReps = targetReps
        self.referenceImages = referenceImages
        self.referenceVideo = referenceVideo
    }
    
    func checkForm(landmarks: [[NormalizedLandmark]]) -> String? {
        guard !landmarks.isEmpty, areLandmarksVisible(landmarks[0]) else { return nil }
        
        let poseLandmarks = landmarks[0]
        
        // Check if arms are raising symmetrically
        let armSymmetry = checkArmSymmetry(landmarks: poseLandmarks)
        if armSymmetry > 25.0 {
            return "Arms not symmetric. Raise both arms equally."
        }
        
        // Check if legs are jumping symmetrically
        let legSymmetry = checkLegSymmetry(landmarks: poseLandmarks)
        if legSymmetry > 0.1 {
            return "Legs not symmetric. Jump with feet equal distance apart."
        }
        
        // Check if user is jumping high enough
        if isInOpenPosition {
            let jumpHeight = checkJumpHeight(landmarks: poseLandmarks)
            if jumpHeight < 0.05 {
                return "Jump higher. Get feet off the ground."
            }
        }
        
        return nil // No form issues
    }
    
    func detectRepetition(currentLandmarks: [[NormalizedLandmark]], previousLandmarks: [[NormalizedLandmark]]?) -> Bool {
        guard !currentLandmarks.isEmpty, areLandmarksVisible(currentLandmarks[0]) else { return false }
        
        let poseLandmarks = currentLandmarks[0]
        let armAngle = calculateArmAngle(landmarks: poseLandmarks)
        let legDistance = calculateLegDistance(landmarks: poseLandmarks)
        
        // Detect open position (arms up, legs spread)
        if !isInOpenPosition && armAngle >= armRaisedAngleThreshold && legDistance >= legSpreadThreshold {
            consecutiveOpenFrames += 1
            if consecutiveOpenFrames >= requiredConsecutiveFrames {
                isInOpenPosition = true
                consecutiveOpenFrames = 0
                consecutiveClosedFrames = 0
            }
            return false
        } else if !isInOpenPosition {
            consecutiveOpenFrames = 0
        }
        
        // Detect closed position (arms down, legs together)
        if isInOpenPosition && armAngle <= armLoweredAngleThreshold && legDistance <= legClosedThreshold {
            consecutiveClosedFrames += 1
            if consecutiveClosedFrames >= requiredConsecutiveFrames {
                isInOpenPosition = false
                consecutiveClosedFrames = 0
                consecutiveOpenFrames = 0
                return true // Rep completed
            }
            return false
        } else if isInOpenPosition {
            consecutiveClosedFrames = 0
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
            PoseLandmarkerHelper.Landmark.leftAnkle.rawValue,
            PoseLandmarkerHelper.Landmark.rightAnkle.rawValue
        ]
        
        for index in keyIndices {
            if index >= landmarks.count || landmarks[index].visibility?.floatValue ?? 0 < confidenceThreshold {
                return false
            }
        }
        
        return true
    }
    
    private func calculateArmAngle(landmarks: [NormalizedLandmark]) -> Float {
        // Average angle of both arms relative to body
        let leftArmAngle = PoseLandmarkerHelper.calculateAngle(
            point1: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftHip.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftHip.rawValue].y)),
            point2: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftShoulder.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftShoulder.rawValue].y)),
            point3: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftWrist.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftWrist.rawValue].y))
        )
        
        let rightArmAngle = PoseLandmarkerHelper.calculateAngle(
            point1: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightHip.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightHip.rawValue].y)),
            point2: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightShoulder.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightShoulder.rawValue].y)),
            point3: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightWrist.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightWrist.rawValue].y))
        )
        
        return (leftArmAngle + rightArmAngle) / 2.0
    }
    
    private func calculateLegDistance(landmarks: [NormalizedLandmark]) -> Float {
        // Distance between ankles normalized by hip width for better scale-invariance
        let leftAnkle = landmarks[PoseLandmarkerHelper.Landmark.leftAnkle.rawValue]
        let rightAnkle = landmarks[PoseLandmarkerHelper.Landmark.rightAnkle.rawValue]
        let ankleDistance = abs(leftAnkle.x - rightAnkle.x)
        
        // Normalize by hip width
        let leftHip = landmarks[PoseLandmarkerHelper.Landmark.leftHip.rawValue]
        let rightHip = landmarks[PoseLandmarkerHelper.Landmark.rightHip.rawValue]
        let hipWidth = abs(leftHip.x - rightHip.x)
        
        if hipWidth > 0 {
            return ankleDistance / hipWidth
        }
        
        return ankleDistance
    }
    
    private func checkArmSymmetry(landmarks: [NormalizedLandmark]) -> Float {
        // Check if both arms are raised to similar heights
        let leftWristHeight = landmarks[PoseLandmarkerHelper.Landmark.leftWrist.rawValue].y
        let rightWristHeight = landmarks[PoseLandmarkerHelper.Landmark.rightWrist.rawValue].y
        
        return abs(leftWristHeight - rightWristHeight) * 100.0 // Scale to make it more readable
    }
    
    private func checkLegSymmetry(landmarks: [NormalizedLandmark]) -> Float {
        // Check if both legs are spread to similar distances
        let leftHip = landmarks[PoseLandmarkerHelper.Landmark.leftHip.rawValue]
        let leftAnkle = landmarks[PoseLandmarkerHelper.Landmark.leftAnkle.rawValue]
        let rightHip = landmarks[PoseLandmarkerHelper.Landmark.rightHip.rawValue]
        let rightAnkle = landmarks[PoseLandmarkerHelper.Landmark.rightAnkle.rawValue]
        
        let leftLegSpread = abs(leftAnkle.x - leftHip.x)
        let rightLegSpread = abs(rightHip.x - rightAnkle.x)
        
        return abs(leftLegSpread - rightLegSpread)
    }
    
    private func checkJumpHeight(landmarks: [NormalizedLandmark]) -> Float {
        // Estimate jump height by looking at ankle height relative to hips
        let leftAnkle = landmarks[PoseLandmarkerHelper.Landmark.leftAnkle.rawValue]
        let rightAnkle = landmarks[PoseLandmarkerHelper.Landmark.rightAnkle.rawValue]
        let leftHip = landmarks[PoseLandmarkerHelper.Landmark.leftHip.rawValue]
        let rightHip = landmarks[PoseLandmarkerHelper.Landmark.rightHip.rawValue]
        
        let ankleHeight = (leftAnkle.y + rightAnkle.y) / 2.0
        let hipHeight = (leftHip.y + rightHip.y) / 2.0
        
        // In jumping, ankles should be higher than normal (relative to hips)
        // Lower Y value means higher position in the image
        return hipHeight - ankleHeight
    }
}
