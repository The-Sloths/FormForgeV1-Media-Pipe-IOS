//
//  SquatExercise.swift
//  FormForgeV1
//
//  Created by Pawel Kowalewski on 06/05/2025.
//

import Foundation
import MediaPipeTasksVision // Assuming this provides NormalizedLandmark
import UIKit

// Define a global constant for debug mode to easily toggle print statements
struct GlobalConstants {
    static let debugMode = true // Set to false for release builds
}




// Ensure you have a definition for NormalizedLandmark
// This is a typical structure.
/*
struct NormalizedLandmark {
    var x: Float
    var y: Float
    var z: Float? // Optional
    var visibility: NSNumber? // Using NSNumber to match `floatValue` usage

    // Initializer for convenience
    init(x: Float, y: Float, z: Float? = nil, visibility: Float? = nil) {
        self.x = x
        self.y = y
        self.z = z
        if let vis = visibility {
            self.visibility = NSNumber(value: vis)
        } else {
            self.visibility = nil
        }
    }
}
*/


class SquatExercise: Exercise {
    let name = "Squats"
    let description = "Stand with feet shoulder-width apart, lower body until thighs are parallel to floor, then return to standing."
    let targetReps: Int
    let referenceImages: [UIImage]?
    let referenceVideo: URL?

    // Tunable parameters for detection
    private let minKeypointScore: Float = 0.2 // Minimum confidence score for a landmark to be considered visible
    private var isInSquatState = false         // Tracks if the user is currently considered to be in the "down" phase of a squat
    private var squatStateFrameCount = 0       // Frames user has been in the current squat position (down)
    private var standingStateFrameCount = 0    // Frames user has been in the current standing position (up)
    private let requiredFramesForStateChange = 4 // Number of consecutive frames to confirm a state change (tune for stability vs. responsiveness)

    // Thresholds for squat detection (crucial for accuracy)
    // Knee angle: A squat involves bending the knees. Standing is ~170-180 deg. Full squat < 90 deg.
    private let squatKneeAngleMaxThreshold: CGFloat = 140.0 // User is in squat if avg knee angle is LESS than this
    private let standingKneeAngleMinThreshold: CGFloat = 160.0 // User is considered standing if avg knee angle is GREATER than this

    // Hip height relative to knee for squat detection: (hipY > kneeY - hipToKneeYTolerance)
    // In normalized coordinates, Y typically increases downwards.
    // So hipY > kneeY means hip is physically lower than the knee.
    // A small negative tolerance means hip can be slightly above the knee and still count as "lowered".
    // A positive tolerance would mean hips must be definitively below the knee.
    private let hipToKneeYToleranceForSquat: Float = 0.05 // Hips are considered lowered if avgHipY > (avgKneeY - this_value)

    init(targetReps: Int = 10, referenceImages: [UIImage]? = nil, referenceVideo: URL? = nil) {
        self.targetReps = targetReps
        self.referenceImages = referenceImages
        self.referenceVideo = referenceVideo
    }

    /// Checks for common form issues during a squat.
    func checkForm(landmarks: [[NormalizedLandmark]]) -> String? {
        guard !landmarks.isEmpty, let poseLandmarks = landmarks.first,
              areCriticalLandmarksVisibleForForm(poseLandmarks) else {
            return "Ensure your whole body is visible." // Or nil if you prefer no message
        }

        // Only check form if the user is determined to be in the squat (down) position
        if isUserInSquatDownPosition(landmarks: poseLandmarks) {
            if isKneesCavingIn(landmarks: poseLandmarks) {
                return "Keep knees aligned with toes."
            }
            if isBackRounded(landmarks: poseLandmarks) {
                return "Keep your back straight."
            }
            if areHeelsRaised(landmarks: poseLandmarks) {
                return "Keep weight in your heels."
            }
        }
        return nil // No form issues detected or not in a position to check
    }

    /// Detects a squat repetition based on transitions between squatting and standing states.
    func detectRepetition(currentLandmarks: [[NormalizedLandmark]], previousLandmarks: [[NormalizedLandmark]]?) -> Bool {
        guard !currentLandmarks.isEmpty, let poseLandmarks = currentLandmarks.first,
              areCriticalLandmarksVisibleForRepDetection(poseLandmarks) else {
            // If critical landmarks for rep detection are not visible, reset frame counts.
            // This prevents getting stuck in a state if tracking is temporarily lost.
            squatStateFrameCount = 0
            standingStateFrameCount = 0
            // Optional: Consider resetting `isInSquatState` to false if visibility is lost,
            // depending on desired behavior (e.g., `if isInSquatState { isInSquatState = false }`)
            // For now, just resetting counters, which means the last valid state of isInSquatState persists.
            if GlobalConstants.debugMode { print("DetectRep: Critical landmarks for rep detection not visible. Resetting frame counts.") }
            return false
        }

        let currentlyDetectedInSquatDownPosition = isUserInSquatDownPosition(landmarks: poseLandmarks)

        if GlobalConstants.debugMode {
            print("DetectRep - Input: currentlyDetectedInSquatDownPosition: \(currentlyDetectedInSquatDownPosition), State: isInSquatState: \(isInSquatState), SquatFrames: \(squatStateFrameCount), StandingFrames: \(standingStateFrameCount)")
        }

        var repCountedThisFrame = false

        if currentlyDetectedInSquatDownPosition {
            // User is detected in the lower part of the squat
            standingStateFrameCount = 0 // Reset standing frame count
            if !isInSquatState {        // If we previously weren't in the squat state (e.g., were standing)
                squatStateFrameCount += 1
                if squatStateFrameCount >= requiredFramesForStateChange {
                    if GlobalConstants.debugMode { print("DetectRep: Transitioning TO SQUAT STATE.") }
                    isInSquatState = true
                    squatStateFrameCount = 0 // Reset counter for this new confirmed state
                }
            } else {
                // Already in squat state, reset squat frame count to indicate we are still holding/in it
                squatStateFrameCount = 0
            }
        } else {
            // User is NOT detected in the lower part of the squat (i.e., likely standing or moving up)
            squatStateFrameCount = 0 // Reset squat frame count
            if isInSquatState {      // If we previously WERE in the squat state (and now we are not)
                standingStateFrameCount += 1
                if standingStateFrameCount >= requiredFramesForStateChange {
                    if GlobalConstants.debugMode { print("DetectRep: Transitioning TO STANDING STATE from SQUAT STATE. === REP COUNTED ===.") }
                    isInSquatState = false
                    standingStateFrameCount = 0 // Reset counter for this new confirmed state
                    repCountedThisFrame = true  // A repetition is one full cycle: down then up
                }
            } else {
                 // Already in standing state, reset standing frame count
                standingStateFrameCount = 0
            }
        }
        return repCountedThisFrame
    }

    // MARK: - Private Helper Methods

    /// Safely retrieves a landmark of a specific type from the landmarks array.
    private func getLandmark(_ landmarkType: PoseLandmarkerHelper.Landmark, from landmarks: [NormalizedLandmark]) -> NormalizedLandmark? {
        let landmarkIndex = landmarkType.rawValue
        guard landmarkIndex >= 0 && landmarkIndex < landmarks.count else {
            if GlobalConstants.debugMode { print("getLandmark: Index \(landmarkIndex) for \(landmarkType.stringValue) out of bounds (count: \(landmarks.count)).") }
            return nil
        }
        return landmarks[landmarkIndex]
    }

    /// Checks if critical landmarks *specifically for rep detection* (hips, knees, ankles) are visible.
    /// This is kept minimal to ensure arm movements don't easily disrupt rep counting.
    private func areCriticalLandmarksVisibleForRepDetection(_ landmarks: [NormalizedLandmark]) -> Bool {
        let criticalTypesForRepDetection: [PoseLandmarkerHelper.Landmark] = [
            .leftHip, .rightHip,
            .leftKnee, .rightKnee,
            .leftAnkle, .rightAnkle
        ]
        for type in criticalTypesForRepDetection {
            guard let landmark = getLandmark(type, from: landmarks),
                  (landmark.visibility?.floatValue ?? 0) >= minKeypointScore else {
                if GlobalConstants.debugMode { print("VisibleForRepDetect: Landmark \(type.stringValue) not sufficiently visible or not found.") }
                return false
            }
        }
        return true
    }

    /// Checks if landmarks needed for *form checking* are visible. This can be more comprehensive.
    private func areCriticalLandmarksVisibleForForm(_ landmarks: [NormalizedLandmark]) -> Bool {
        let criticalTypesForForm: [PoseLandmarkerHelper.Landmark] = [
            .leftShoulder, .rightShoulder, // Shoulders needed for back rounding check
            .leftHip, .rightHip,
            .leftKnee, .rightKnee,
            .leftAnkle, .rightAnkle,
            .leftHeel, .rightHeel,         // Optional, but good for heel raise check
            .leftFootIndex, .rightFootIndex // Optional, for heel raise check
        ]
        for type in criticalTypesForForm {
            // For optional landmarks in form checking, we might be more lenient or have fallbacks.
            // Here, we'll require them if listed.
            guard let landmark = getLandmark(type, from: landmarks),
                  (landmark.visibility?.floatValue ?? 0) >= minKeypointScore else {
                if GlobalConstants.debugMode { print("VisibleForForm: Landmark \(type.stringValue) not sufficiently visible or not found.") }
                return false
            }
        }
        return true
    }


    /// Determines if the user is in the "down" position of a squat based on knee angles and hip height.
    /// This function focuses ONLY on leg and hip landmarks to avoid interference from arm movements.
    private func isUserInSquatDownPosition(landmarks: [NormalizedLandmark]) -> Bool {
        guard let leftHip = getLandmark(.leftHip, from: landmarks),
              let rightHip = getLandmark(.rightHip, from: landmarks),
              let leftKnee = getLandmark(.leftKnee, from: landmarks),
              let rightKnee = getLandmark(.rightKnee, from: landmarks),
              let leftAnkle = getLandmark(.leftAnkle, from: landmarks),
              let rightAnkle = getLandmark(.rightAnkle, from: landmarks) else {
            // If any primary leg/hip landmark is missing from the array, we can't determine.
            if GlobalConstants.debugMode { print("SquatDownPos: Essential leg/hip landmark type not found in array.")}
            return false
        }

        // Ensure these specific landmarks meet visibility criteria
        let legLandmarksAreVisible = [leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle].allSatisfy {
            ($0.visibility?.floatValue ?? 0) >= minKeypointScore
        }

        if !legLandmarksAreVisible {
            if GlobalConstants.debugMode { print("SquatDownPos: Essential leg/hip landmark visibility too low.") }
            return false
        }

        let leftKneeAngle = calculateAngle(
            p1: (x: CGFloat(leftHip.x), y: CGFloat(leftHip.y)),
            p2: (x: CGFloat(leftKnee.x), y: CGFloat(leftKnee.y)), // Vertex
            p3: (x: CGFloat(leftAnkle.x), y: CGFloat(leftAnkle.y))
        )
        let rightKneeAngle = calculateAngle(
            p1: (x: CGFloat(rightHip.x), y: CGFloat(rightHip.y)),
            p2: (x: CGFloat(rightKnee.x), y: CGFloat(rightKnee.y)), // Vertex
            p3: (x: CGFloat(rightAnkle.x), y: CGFloat(rightAnkle.y))
        )
        let avgKneeAngle = (leftKneeAngle + rightKneeAngle) / 2

        let avgHipY = (leftHip.y + rightHip.y) / 2
        let avgKneeY = (leftKnee.y + rightKnee.y) / 2

        // Condition 1: Knees are sufficiently bent for a squat.
        let kneesBentEnough = avgKneeAngle < squatKneeAngleMaxThreshold && avgKneeAngle > 10 // Lower bound to avoid issues with collapsed poses

        // Condition 2: Hips are lowered relative to knees.
        // hipY > kneeY means hip is physically lower on the screen (Y increases downwards).
        // avgHipY > (avgKneeY - hipToKneeYToleranceForSquat)
        let hipsLoweredEnough = avgHipY > (avgKneeY - hipToKneeYToleranceForSquat)

        if GlobalConstants.debugMode {
            let visLHip = leftHip.visibility?.floatValue ?? -1
            let visRHip = rightHip.visibility?.floatValue ?? -1
            // ... and so on for other landmarks if detailed per-landmark visibility is needed for this print
            print(String(format: "SquatDownPos - Angles: L:%.1f, R:%.1f, Avg:%.1f (Bent: %@). Heights: HipY:%.2f, KneeY:%.2f (Lowered: %@. Tol:%.2f). Vis: LHip:%.2f, RHip:%.2f",
                         leftKneeAngle, rightKneeAngle, avgKneeAngle, String(describing: kneesBentEnough),
                         avgHipY, avgKneeY, String(describing: hipsLoweredEnough), hipToKneeYToleranceForSquat, visLHip, visRHip))
        }

        return kneesBentEnough && hipsLoweredEnough
    }

    /// Calculates the angle (in degrees) between three points (p2 is the vertex).
    private func calculateAngle(p1: (x: CGFloat, y: CGFloat), p2: (x: CGFloat, y: CGFloat), p3: (x: CGFloat, y: CGFloat)) -> CGFloat {
        let vector1 = (x: p1.x - p2.x, y: p1.y - p2.y)
        let vector2 = (x: p3.x - p2.x, y: p3.y - p2.y)

        let dotProduct = vector1.x * vector2.x + vector1.y * vector2.y
        let magnitude1 = sqrt(vector1.x * vector1.x + vector1.y * vector1.y)
        let magnitude2 = sqrt(vector2.x * vector2.x + vector2.y * vector2.y)

        guard magnitude1 * magnitude2 != 0 else { return 0 } // Avoid division by zero if points are coincident

        let cosineTheta = dotProduct / (magnitude1 * magnitude2)
        let angleRad = acos(max(-1.0, min(1.0, cosineTheta))) // Clamp cosineTheta to avoid domain errors with acos

        return angleRad * 180 / .pi // Convert to degrees
    }

    // MARK: - Form Checking Details

    private func isKneesCavingIn(landmarks: [NormalizedLandmark]) -> Bool {
        guard let leftKnee = getLandmark(.leftKnee, from: landmarks),
              let rightKnee = getLandmark(.rightKnee, from: landmarks),
              let leftAnkle = getLandmark(.leftAnkle, from: landmarks),
              let rightAnkle = getLandmark(.rightAnkle, from: landmarks),
              [leftKnee, rightKnee, leftAnkle, rightAnkle].allSatisfy({ ($0.visibility?.floatValue ?? 0) >= minKeypointScore })
        else { return false }

        let kneeDistance = abs(leftKnee.x - rightKnee.x)
        let ankleDistance = abs(leftAnkle.x - rightAnkle.x)

        guard ankleDistance > 0.01 else { return false } // Avoid issues if ankles are too close or on top of each other
        // Knees are caving if distance between them is significantly less than distance between ankles.
        return kneeDistance < (ankleDistance * 0.75) // Adjusted threshold, tune as needed
    }

    private func isBackRounded(landmarks: [NormalizedLandmark]) -> Bool {
        guard let leftShoulder = getLandmark(.leftShoulder, from: landmarks),
              let rightShoulder = getLandmark(.rightShoulder, from: landmarks),
              let leftHip = getLandmark(.leftHip, from: landmarks),
              let rightHip = getLandmark(.rightHip, from: landmarks),
              // Optional: include knees for a more complex back angle check relative to thighs
              // let leftKnee = getLandmark(.leftKnee, from: landmarks),
              // let rightKnee = getLandmark(.rightKnee, from: landmarks),
              [leftShoulder, rightShoulder, leftHip, rightHip].allSatisfy({ ($0.visibility?.floatValue ?? 0) >= minKeypointScore })
        else { return false }

        let midShoulderY = (leftShoulder.y + rightShoulder.y) / 2
        let midHipY = (leftHip.y + rightHip.y) / 2
        // let midKneeY = (leftKnee.y + rightKnee.y) / 2 // If using knees

        // A simple proxy: if shoulders are significantly lower than hips (indicating excessive forward slump beyond normal lean)
        // This assumes Y increases downwards. Shoulder.y > Hip.y means shoulder is physically lower.
        // This needs to be contextualized with overall body lean.
        // A more robust method involves the angle of the torso (shoulder-hip line) relative to vertical or horizontal.
        // Or, checking for a "break" in the spine line (e.g. shoulder-hip angle vs hip-knee angle).

        // Calculate torso angle with the vertical (assuming Y is down, X is right)
        // Vector Hip -> Shoulder
        let torsoVectorX = ((leftShoulder.x + rightShoulder.x) / 2) - ((leftHip.x + rightHip.x) / 2)
        let torsoVectorY = midShoulderY - midHipY // Negative if shoulders above hips

        // Angle with positive Y-axis (downwards vertical)
        let torsoAngleWithVerticalRad = atan2(torsoVectorX, -torsoVectorY) // -torsoVectorY to point "up" from hip to shoulder for angle calc
        let torsoAngleWithVerticalDeg = torsoAngleWithVerticalRad * 180 / .pi

        // A "good" squat lean might be between 30 to 70 degrees forward from vertical (0 degrees).
        // So, if angle is, say, > 75-80 degrees (very horizontal), it could be "rounded" or "excessive lean".
        // This is highly dependent on squat style and requires tuning.
        let excessiveLeanThresholdDegrees: CGFloat = 75.0
        let isTooHorizontal = abs(torsoAngleWithVerticalDeg) > Float(excessiveLeanThresholdDegrees)

        if GlobalConstants.debugMode {
            print(String(format:"FormCheck - BackRound: TorsoAngleFromVertical: %.1f deg (TooHorizontal: %@)", torsoAngleWithVerticalDeg, String(describing: isTooHorizontal)))
        }
        return isTooHorizontal // True if back is rounded (too horizontal)
    }

    private func areHeelsRaised(landmarks: [NormalizedLandmark]) -> Bool {
        guard let leftHeel = getLandmark(.leftHeel, from: landmarks),
              let rightHeel = getLandmark(.rightHeel, from: landmarks),
              let leftFootIndex = getLandmark(.leftFootIndex, from: landmarks), // Tip of foot
              let rightFootIndex = getLandmark(.rightFootIndex, from: landmarks),
              [leftHeel, rightHeel, leftFootIndex, rightFootIndex].allSatisfy({ ($0.visibility?.floatValue ?? 0) >= minKeypointScore })
        else {
            // Fallback if specific heel/foot landmarks aren't good
            guard let leftAnkle = getLandmark(.leftAnkle, from: landmarks),
                  let rightAnkle = getLandmark(.rightAnkle, from: landmarks),
                  let leftKnee = getLandmark(.leftKnee, from: landmarks),
                  let rightKnee = getLandmark(.rightKnee, from: landmarks),
                  [leftAnkle,rightAnkle,leftKnee,rightKnee].allSatisfy({ ($0.visibility?.floatValue ?? 0) >= minKeypointScore })
            else { return false }

            // Original logic: if ankles are significantly in front of knees (x-coord).
            // This is very dependent on camera angle.
            // If person faces right, ankle.x < knee.x means ankle is to the left of knee.
            // `leftAnkle.x - leftKnee.x < -0.1` means `leftAnkle.x < leftKnee.x - 0.1`
            // This is true if ankle is significantly to the "left" (camera view) of the knee.
            let leftAnkleKneeDiffX = leftAnkle.x - leftKnee.x
            let rightAnkleKneeDiffX = rightAnkle.x - rightKnee.x
            let raisedBasedOnAnkleKneeX = leftAnkleKneeDiffX < -0.08 || rightAnkleKneeDiffX < -0.08 // Tuned threshold
            if GlobalConstants.debugMode { print("FormCheck - HeelsRaised (Fallback X-Logic): LDiff: \(leftAnkleKneeDiffX), RDiff: \(rightAnkleKneeDiffX). Raised: \(raisedBasedOnAnkleKneeX)")}
            return raisedBasedOnAnkleKneeX
        }

        // Primary check using heel and foot tip:
        // If heel.y is significantly smaller (higher on screen) than foot_index.y, heel is lifted.
        // Assumes Y increases downwards.
        let heelRaiseYTolerance: Float = 0.025 // Normalized Y distance. Tune this.
        let leftHeelRaised = leftHeel.y < (leftFootIndex.y - heelRaiseYTolerance)
        let rightHeelRaised = rightHeel.y < (rightFootIndex.y - heelRaiseYTolerance)

        if GlobalConstants.debugMode {
             print(String(format:"FormCheck - HeelsRaised: LHeelY:%.2f, LFootIdxY:%.2f (Raised:%@). RHeelY:%.2f, RFootIdxY:%.2f (Raised:%@). Tol:%.3f",
                          leftHeel.y, leftFootIndex.y, String(describing: leftHeelRaised),
                          rightHeel.y, rightFootIndex.y, String(describing: rightHeelRaised), heelRaiseYTolerance))
        }
        return leftHeelRaised || rightHeelRaised
    }
}
