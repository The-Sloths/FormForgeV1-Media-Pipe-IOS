//
//  SquatExercise.swift
//  FormForgeV1
//
//  Created by Pawel Kowalewski on 06/05/2025.
//

import Foundation
import MediaPipeTasksVision
import UIKit

class SquatExercise: Exercise {
    let name = "Squats"
    let description = "Stand with feet shoulder-width apart, lower body until thighs are parallel to floor, then return to standing."
    let targetReps: Int
    let referenceImages: [UIImage]?
    let referenceVideo: URL?
    
    // Thresholds for detecting squats
    private let bottomKneeAngleThreshold: Float = 100.0 // Lower means deeper squat
    private let topKneeAngleThreshold: Float = 160.0    // Higher means straighter legs
    private let confidenceThreshold: Float = 0.7        // Minimum landmark visibility
    
    // State tracking
    private var isInBottomPosition = false
    private var consecutiveTopFrames = 0
    private var consecutiveBottomFrames = 0
    private let requiredConsecutiveFrames = 3
    
    // For detecting bad form
    private let minHipAngle: Float = 45.0  // To detect if not squatting deep enough
    private let maxKneeForwardThreshold: Float = 0.1 // Knees shouldn't go too far forward
    
    init(targetReps: Int = 10, referenceImages: [UIImage]? = nil, referenceVideo: URL? = nil) {
        self.targetReps = targetReps
        self.referenceImages = referenceImages
        self.referenceVideo = referenceVideo
    }
    
    func checkForm(landmarks: [[NormalizedLandmark]]) -> String? {
        guard !landmarks.isEmpty, areLandmarksVisible(landmarks[0]) else { return nil }
        
        let poseLandmarks = landmarks[0]
        
        // Calculate relevant angles
        let kneeAngle = calculateKneeAngle(landmarks: poseLandmarks)
        let hipAngle = calculateHipAngle(landmarks: poseLandmarks)
        let kneePosition = checkKneePosition(landmarks: poseLandmarks)
        
        // Check form issues
        if kneePosition > maxKneeForwardThreshold {
            return "Knees too far forward. Keep weight in heels."
        }
        
        if isInBottomPosition && hipAngle < minHipAngle {
            return "Squat deeper. Lower hips more."
        }
        
        // Check if feet are too close or too wide
        let ankleDistance = calculateAnkleDistance(landmarks: poseLandmarks)
        if ankleDistance < 0.1 {
            return "Feet too close together. Widen stance."
        } else if ankleDistance > 0.5 {
            return "Feet too wide apart. Narrow stance slightly."
        }
        
        return nil // No form issues
    }
    
    func detectRepetition(currentLandmarks: [[NormalizedLandmark]], previousLandmarks: [[NormalizedLandmark]]?) -> Bool {
        guard !currentLandmarks.isEmpty, areLandmarksVisible(currentLandmarks[0]) else { return false }
        
        let poseLandmarks = currentLandmarks[0]
        let kneeAngle = calculateKneeAngle(landmarks: poseLandmarks)
        
        // Detect bottom position (squat)
        if !isInBottomPosition && kneeAngle <= bottomKneeAngleThreshold {
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
        
        // Detect top position (standing)
        if isInBottomPosition && kneeAngle >= topKneeAngleThreshold {
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
            PoseLandmarkerHelper.Landmark.leftHip.rawValue,
            PoseLandmarkerHelper.Landmark.rightHip.rawValue,
            PoseLandmarkerHelper.Landmark.leftKnee.rawValue,
            PoseLandmarkerHelper.Landmark.rightKnee.rawValue,
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
    
    private func calculateKneeAngle(landmarks: [NormalizedLandmark]) -> Float {
        // Average of both knees for more stable detection
        let leftKneeAngle = PoseLandmarkerHelper.calculateAngle(
            point1: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftHip.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftHip.rawValue].y)),
            point2: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftKnee.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftKnee.rawValue].y)),
            point3: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftAnkle.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftAnkle.rawValue].y))
        )
        
        let rightKneeAngle = PoseLandmarkerHelper.calculateAngle(
            point1: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightHip.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightHip.rawValue].y)),
            point2: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightKnee.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightKnee.rawValue].y)),
            point3: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightAnkle.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightAnkle.rawValue].y))
        )
        
        return (leftKneeAngle + rightKneeAngle) / 2.0
    }
    
    private func calculateHipAngle(landmarks: [NormalizedLandmark]) -> Float {
        // Average of both hips
        let leftHipAngle = PoseLandmarkerHelper.calculateAngle(
            point1: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftShoulder.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftShoulder.rawValue].y)),
            point2: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftHip.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftHip.rawValue].y)),
            point3: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftKnee.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.leftKnee.rawValue].y))
        )
        
        let rightHipAngle = PoseLandmarkerHelper.calculateAngle(
            point1: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightShoulder.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightShoulder.rawValue].y)),
            point2: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightHip.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightHip.rawValue].y)),
            point3: CGPoint(x: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightKnee.rawValue].x),
                           y: CGFloat(landmarks[PoseLandmarkerHelper.Landmark.rightKnee.rawValue].y))
        )
        
        return (leftHipAngle + rightHipAngle) / 2.0
    }
    
    private func checkKneePosition(landmarks: [NormalizedLandmark]) -> Float {
        // Check if knees are extending too far forward relative to ankles
        let leftKneeForward = landmarks[PoseLandmarkerHelper.Landmark.leftKnee.rawValue].z -
                             landmarks[PoseLandmarkerHelper.Landmark.leftAnkle.rawValue].z
        
        let rightKneeForward = landmarks[PoseLandmarkerHelper.Landmark.rightKnee.rawValue].z -
                              landmarks[PoseLandmarkerHelper.Landmark.rightAnkle.rawValue].z
        
        return max(leftKneeForward, rightKneeForward)
    }
    
    private func calculateAnkleDistance(landmarks: [NormalizedLandmark]) -> Float {
        let leftAnkle = landmarks[PoseLandmarkerHelper.Landmark.leftAnkle.rawValue]
        let rightAnkle = landmarks[PoseLandmarkerHelper.Landmark.rightAnkle.rawValue]
        
        return abs(leftAnkle.x - rightAnkle.x)
    }
}
