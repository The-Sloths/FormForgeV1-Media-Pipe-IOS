//
//  PushupExercise.swift
//  FormForgeV1
//
//  Created by Pawel Kowalewski on 06/05/2025.
//


import Foundation
import MediaPipeTasksVision // Assuming this provides NormalizedLandmark
import UIKit

// (GlobalConstants and PoseLandmarkerHelper.Landmark enum would be defined as in the Squat example)
// struct GlobalConstants { static let debugMode = true }
// struct PoseLandmarkerHelper { enum Landmark: Int, CaseIterable { ... } }
// protocol Exercise { ... } // Ensure this is defined

class PushupExercise: Exercise {
    let name = "Push-ups"
    let description = "Start in a plank position, lower your body until your chest nearly touches the floor, then push back up."
    let targetReps: Int
    let referenceImages: [UIImage]?
    let referenceVideo: URL?

    // Tunable parameters for detection
    private let minKeypointScore: Float = 0.4 // Can be slightly lower for push-ups if hands/wrists are sometimes less clear
    private var isInDownState = false          // Tracks if the user is currently considered to be in the "down" phase
    private var downStateFrameCount = 0        // Frames user has been in the current down position
    private var upStateFrameCount = 0          // Frames user has been in the current up position
    private let requiredFramesForStateChange = 3 // Number of consecutive frames to confirm a state change

    // Thresholds for push-up detection
    // Elbow angles (Shoulder-Elbow-Wrist)
    private let downElbowAngleMaxThreshold: CGFloat = 100.0 // User is in "down" if avg elbow angle is LESS than this
    private let upElbowAngleMinThreshold: CGFloat = 150.0   // User is in "up" if avg elbow angle is GREATER than this

    // Body alignment thresholds (Shoulder-Hip-Ankle or Shoulder-Hip-Knee)
    // Angle should be close to 180 degrees (straight)
    private let minBodyStraightAngle: CGFloat = 150.0 // Minimum angle to be considered "straight"
    private let maxBodyStraightAngle: CGFloat = 210.0 // Maximum angle (180 +/- 30)

    // Optional: Shoulder height relative to elbow for "down" state (Y coordinate)
    // In "down" position, shoulder.y should be >= elbow.y (if Y increases downwards)
    private let shoulderElbowYDiffThreshold: Float = -0.03 // Shoulder Y can be slightly above elbow Y (more negative is higher)

    init(targetReps: Int = 10, referenceImages: [UIImage]? = nil, referenceVideo: URL? = nil) {
        self.targetReps = targetReps
        self.referenceImages = referenceImages
        self.referenceVideo = referenceVideo
    }

    func checkForm(landmarks: [[NormalizedLandmark]]) -> String? {
        guard !landmarks.isEmpty, let poseLandmarks = landmarks.first,
              areCriticalLandmarksVisibleForForm(poseLandmarks) else {
            return "Ensure your whole body is visible from the side, and that you are in a push-ups position."
        }

        // Body Alignment Check (always relevant)
        if !isBodyAligned(landmarks: poseLandmarks) {
            // More specific feedback for piking vs. sagging
            if isBodyPiking(landmarks: poseLandmarks) {
                return "Hips too high. Keep your body straight."
            } else if isBodySagging(landmarks: poseLandmarks) {
                return "Hips sagging. Engage your core."
            }
            return "Keep your body straight from shoulders to ankles."
        }
        
        // Form checks specific to the "down" position
        if isUserInDownPosition(landmarks: poseLandmarks) {
            // Check for elbow flaring (complex, placeholder)
            // if areElbowsFlaring(landmarks: poseLandmarks) { return "Keep your elbows closer to your body." }
        }
        
        // Check if arms are fully extended in the "up" position
        // This might be part of rep detection rather than just form, but can be a reminder
        // ... inside checkForm
        // Check if arms are fully extended in the "up" position
        // This might be part of rep detection rather than just form, but can be a reminder
        if isUserInUpPosition(landmarks: poseLandmarks, checkBodyAlignment: false) { // Don't re-check alignment here
            // Correctly destructure or access the specific needed element
            let metrics = getPushupMetrics(landmarks: poseLandmarks)
            let avgElbowAngle = metrics.avgElbowAngle // Access just the element we need

            if let angle = avgElbowAngle {
                // This means they are "up" but not fully extended. Could be a form cue or part of rep logic.
                // For example, if they are in the "up" state but their arms aren't fully locked out.
                if angle < (upElbowAngleMinThreshold - 10.0) { // Give a bit of tolerance, e.g., 10 degrees from fully locked
                    // This is a good place for a specific form message if you want one,
                    // but for now, we're just checking.
                    // return "Extend your arms fully at the top." // Example message
                    if GlobalConstants.debugMode {
                        print("FormCheck (Pushup): In UP position but arms not fully extended. Angle: \(angle)")
                    }
                }
            }
        }


        return nil // No specific form issues detected beyond general alignment
    }

    func detectRepetition(currentLandmarks: [[NormalizedLandmark]], previousLandmarks: [[NormalizedLandmark]]?) -> Bool {
        guard !currentLandmarks.isEmpty, let poseLandmarks = currentLandmarks.first,
              areCriticalLandmarksVisibleForRepDetection(poseLandmarks) else {
            downStateFrameCount = 0
            upStateFrameCount = 0
            if GlobalConstants.debugMode { print("DetectRep (Pushup): Critical landmarks for rep detection not visible. Resetting frame counts.") }
            return false
        }

        let currentlyDetectedInDownPosition = isUserInDownPosition(landmarks: poseLandmarks)
        let currentlyDetectedInUpPosition = isUserInUpPosition(landmarks: poseLandmarks) // Check for up position explicitly

        if GlobalConstants.debugMode {
            print("DetectRep (Pushup) - Input: DetectedDown: \(currentlyDetectedInDownPosition), DetectedUp: \(currentlyDetectedInUpPosition), State: isInDownState: \(isInDownState), DownFrames: \(downStateFrameCount), UpFrames: \(upStateFrameCount)")
        }
        
        var repCountedThisFrame = false

        if currentlyDetectedInDownPosition {
            upStateFrameCount = 0 // Reset up state frame count
            if !isInDownState {   // If we weren't in the down state (e.g., were up or transitioning)
                downStateFrameCount += 1
                if downStateFrameCount >= requiredFramesForStateChange {
                    if GlobalConstants.debugMode { print("DetectRep (Pushup): Transitioning TO DOWN STATE.") }
                    isInDownState = true
                    downStateFrameCount = 0 // Reset counter for this new confirmed state
                }
            } else {
                downStateFrameCount = 0 // Still in down state, reset counter
            }
        } else if currentlyDetectedInUpPosition { // Explicitly check for being in a valid "up" position
            downStateFrameCount = 0 // Reset down state frame count
            if isInDownState {      // If we previously WERE in the down state (and now we are up)
                upStateFrameCount += 1
                if upStateFrameCount >= requiredFramesForStateChange {
                    if GlobalConstants.debugMode { print("DetectRep (Pushup): Transitioning TO UP STATE from DOWN STATE. === REP COUNTED ===.") }
                    isInDownState = false
                    upStateFrameCount = 0 // Reset counter for this new confirmed state
                    repCountedThisFrame = true
                }
            } else {
                upStateFrameCount = 0 // Still in up state (or transitioning not from down), reset counter
            }
        } else {
            // Neither definitively in "down" nor "up" position (transitioning, or bad form like not straight)
            // Don't increment any counters, effectively waiting for a clear state.
            // Or, reset both if you want to be stricter:
            // downStateFrameCount = 0
            // upStateFrameCount = 0
            if GlobalConstants.debugMode { print("DetectRep (Pushup): Not clearly in UP or DOWN state.") }
        }
        
        return repCountedThisFrame
    }

    // MARK: - Private Helper Methods

    private func getLandmark(_ landmarkType: PoseLandmarkerHelper.Landmark, from landmarks: [NormalizedLandmark]) -> NormalizedLandmark? {
        let landmarkIndex = landmarkType.rawValue
        guard landmarkIndex >= 0 && landmarkIndex < landmarks.count else {
            if GlobalConstants.debugMode { print("getLandmark (Pushup): Index \(landmarkIndex) for \(landmarkType.stringValue) out of bounds (count: \(landmarks.count)).") }
            return nil
        }
        return landmarks[landmarkIndex]
    }

    private func areCriticalLandmarksVisibleForRepDetection(_ landmarks: [NormalizedLandmark]) -> Bool {
        let criticalTypes: [PoseLandmarkerHelper.Landmark] = [
            .leftShoulder, .rightShoulder,
            .leftElbow, .rightElbow,
            .leftWrist, .rightWrist,
            .leftHip, .rightHip, // Hips are crucial for body alignment during rep counting
            // Ankles/Knees are important too but primary check on hips first
            .leftAnkle, .rightAnkle // For standard push-ups
            // .leftKnee, .rightKnee // Add if supporting knee push-ups primarily
        ]
        for type in criticalTypes {
            guard let landmark = getLandmark(type, from: landmarks),
                  (landmark.visibility?.floatValue ?? 0) >= minKeypointScore else {
                if GlobalConstants.debugMode { print("VisibleForRepDetect (Pushup): Landmark \(type.stringValue) not sufficiently visible or not found.") }
                return false
            }
        }
        return true
    }

    private func areCriticalLandmarksVisibleForForm(_ landmarks: [NormalizedLandmark]) -> Bool {
        // For form, we might want all the same ones as for rep detection,
        // potentially with more consistent high visibility requirements.
        return areCriticalLandmarksVisibleForRepDetection(landmarks) // Can be more specific if needed
    }

    /// Extracts key metrics for push-up analysis: elbow angles and body straightness.
    private func getPushupMetrics(landmarks: [NormalizedLandmark]) -> (
        avgElbowAngle: CGFloat?, leftElbowAngle: CGFloat?, rightElbowAngle: CGFloat?,
        bodyAngle: CGFloat?, shouldersVisible: Bool, elbowsVisible: Bool, wristsVisible: Bool, hipsVisible: Bool, anklesVisible: Bool
    ) {
        guard let leftShoulder = getLandmark(.leftShoulder, from: landmarks),
              let rightShoulder = getLandmark(.rightShoulder, from: landmarks),
              let leftElbow = getLandmark(.leftElbow, from: landmarks),
              let rightElbow = getLandmark(.rightElbow, from: landmarks),
              let leftWrist = getLandmark(.leftWrist, from: landmarks),
              let rightWrist = getLandmark(.rightWrist, from: landmarks),
              let leftHip = getLandmark(.leftHip, from: landmarks),
              let rightHip = getLandmark(.rightHip, from: landmarks),
              let leftAnkle = getLandmark(.leftAnkle, from: landmarks), // Assuming toe push-ups
              let rightAnkle = getLandmark(.rightAnkle, from: landmarks)
        else {
            if GlobalConstants.debugMode { print("getPushupMetrics: Core landmark type not found in array.") }
            return (nil, nil, nil, nil, false, false, false, false, false)
        }

        let shouldersVisible = (leftShoulder.visibility?.floatValue ?? 0) >= minKeypointScore && (rightShoulder.visibility?.floatValue ?? 0) >= minKeypointScore
        let elbowsVisible = (leftElbow.visibility?.floatValue ?? 0) >= minKeypointScore && (rightElbow.visibility?.floatValue ?? 0) >= minKeypointScore
        let wristsVisible = (leftWrist.visibility?.floatValue ?? 0) >= minKeypointScore && (rightWrist.visibility?.floatValue ?? 0) >= minKeypointScore
        let hipsVisible = (leftHip.visibility?.floatValue ?? 0) >= minKeypointScore && (rightHip.visibility?.floatValue ?? 0) >= minKeypointScore
        let anklesVisible = (leftAnkle.visibility?.floatValue ?? 0) >= minKeypointScore && (rightAnkle.visibility?.floatValue ?? 0) >= minKeypointScore


        var lElbowAngle: CGFloat? = nil
        var rElbowAngle: CGFloat? = nil
        var avgElbAngle: CGFloat? = nil

        if shouldersVisible && elbowsVisible && wristsVisible {
            lElbowAngle = calculateAngle(
                p1: (x: CGFloat(leftShoulder.x), y: CGFloat(leftShoulder.y)),
                p2: (x: CGFloat(leftElbow.x), y: CGFloat(leftElbow.y)), // Vertex
                p3: (x: CGFloat(leftWrist.x), y: CGFloat(leftWrist.y))
            )
            rElbowAngle = calculateAngle(
                p1: (x: CGFloat(rightShoulder.x), y: CGFloat(rightShoulder.y)),
                p2: (x: CGFloat(rightElbow.x), y: CGFloat(rightElbow.y)), // Vertex
                p3: (x: CGFloat(rightWrist.x), y: CGFloat(rightWrist.y))
            )
            if let lAngle = lElbowAngle, let rAngle = rElbowAngle {
                avgElbAngle = (lAngle + rAngle) / 2
            } else if let lAngle = lElbowAngle { // One side visible
                avgElbAngle = lAngle
            } else if let rAngle = rElbowAngle { // Other side visible
                avgElbAngle = rAngle
            }
        }
        
        var bodyAng: CGFloat? = nil
        if shouldersVisible && hipsVisible && anklesVisible { // For toe push-ups
            // Mid-points for body line calculation
            let midShoulder = (x: (leftShoulder.x + rightShoulder.x) / 2, y: (leftShoulder.y + rightShoulder.y) / 2)
            let midHip = (x: (leftHip.x + rightHip.x) / 2, y: (leftHip.y + rightHip.y) / 2)
            let midAnkle = (x: (leftAnkle.x + rightAnkle.x) / 2, y: (leftAnkle.y + rightAnkle.y) / 2)
            
            bodyAng = calculateAngle(
                p1: (x: CGFloat(midShoulder.x), y: CGFloat(midShoulder.y)),
                p2: (x: CGFloat(midHip.x), y: CGFloat(midHip.y)), // Vertex
                p3: (x: CGFloat(midAnkle.x), y: CGFloat(midAnkle.y))
            )
        }

        return (avgElbAngle, lElbowAngle, rElbowAngle, bodyAng, shouldersVisible, elbowsVisible, wristsVisible, hipsVisible, anklesVisible)
    }
    
    /// Checks if the body is reasonably straight (Shoulder-Hip-Ankle).
    private func isBodyAligned(landmarks: [NormalizedLandmark]) -> Bool {
        let metrics = getPushupMetrics(landmarks: landmarks)
        guard metrics.shouldersVisible && metrics.hipsVisible && metrics.anklesVisible, // For standard push-up
              let bodyAngle = metrics.bodyAngle else {
            if GlobalConstants.debugMode { print("isBodyAligned: Not enough visible landmarks for body angle.")}
            return false // Cannot determine alignment if key points are not visible
        }
        let aligned = bodyAngle >= minBodyStraightAngle && bodyAngle <= maxBodyStraightAngle
        if GlobalConstants.debugMode && !aligned { print("isBodyAligned: Failed. Angle: \(bodyAngle)")}
        return aligned
    }
    
    private func isBodyPiking(landmarks: [NormalizedLandmark]) -> Bool {
        let metrics = getPushupMetrics(landmarks: landmarks)
        guard metrics.shouldersVisible && metrics.hipsVisible && metrics.anklesVisible,
              let bodyAngle = metrics.bodyAngle else {
            return false
        }
        // Piking means angle is too small (hips too high relative to straight line)
        return bodyAngle < minBodyStraightAngle
    }

    private func isBodySagging(landmarks: [NormalizedLandmark]) -> Bool {
        let metrics = getPushupMetrics(landmarks: landmarks)
        guard metrics.shouldersVisible && metrics.hipsVisible && metrics.anklesVisible,
              let bodyAngle = metrics.bodyAngle else {
            return false
        }
        // Sagging means angle is too large (hips too low relative to straight line),
        // or more intuitively, the hip is below the line from shoulder to ankle.
        // For simplicity with the current angle calculation (where 180 is straight):
        // Our current `calculateAngle` gives the internal angle. If it goes beyond 180 (e.g. 200),
        // it means it's bent in the "other" direction. So maxBodyStraightAngle handles this.
        // We could also check Y-coordinate of hip vs. line from shoulder to ankle.
        // If bodyAngle > 180, it's sagging.
        return bodyAngle > maxBodyStraightAngle // Or simply bodyAngle > 180 + some_tolerance
    }


    /// Determines if the user is in the "down" position of a push-up.
    private func isUserInDownPosition(landmarks: [NormalizedLandmark]) -> Bool {
        let metrics = getPushupMetrics(landmarks: landmarks)
        
        guard metrics.shouldersVisible && metrics.elbowsVisible && metrics.wristsVisible, // For arm bend
              let avgElbowAngle = metrics.avgElbowAngle else {
            if GlobalConstants.debugMode { print("isUserInDownPosition: Not enough arm landmarks for elbow angle.")}
            return false
        }

        let armsBentEnough = avgElbowAngle < downElbowAngleMaxThreshold

        // Optional: Check if shoulders are low enough relative to elbows (Y-coordinates)
        var shouldersLowEnough = true // Default to true if not checking this specifically
        if let leftShoulder = getLandmark(.leftShoulder, from: landmarks),
           let rightShoulder = getLandmark(.rightShoulder, from: landmarks),
           let leftElbow = getLandmark(.leftElbow, from: landmarks),
           let rightElbow = getLandmark(.rightElbow, from: landmarks),
           (leftShoulder.visibility?.floatValue ?? 0) >= minKeypointScore,
           (rightShoulder.visibility?.floatValue ?? 0) >= minKeypointScore,
           (leftElbow.visibility?.floatValue ?? 0) >= minKeypointScore,
           (rightElbow.visibility?.floatValue ?? 0) >= minKeypointScore {
            
            let avgShoulderY = (leftShoulder.y + rightShoulder.y) / 2
            let avgElbowY = (leftElbow.y + rightElbow.y) / 2
            // Y typically increases downwards. Shoulder Y should be >= Elbow Y for a deep push-up.
            // shoulderElbowYDiffThreshold is negative, so avgShoulderY >= avgElbowY + shoulderElbowYDiffThreshold
            // which means avgShoulderY can be slightly above avgElbowY.
            shouldersLowEnough = avgShoulderY >= (avgElbowY + shoulderElbowYDiffThreshold)
        }
        
        let bodyAligned = isBodyAligned(landmarks: landmarks) // Crucial: maintain form

        if GlobalConstants.debugMode {
            print(String(format: "isUserInDownPosition - ElbowAngle: %.1f (BentEnough: %@), BodyAligned: %@, ShouldersLowEnough: %@",
                         avgElbowAngle, String(describing: armsBentEnough), String(describing: bodyAligned), String(describing: shouldersLowEnough)))
        }
        
        return armsBentEnough && bodyAligned && shouldersLowEnough
    }

    /// Determines if the user is in the "up" position of a push-up.
    private func isUserInUpPosition(landmarks: [NormalizedLandmark], checkBodyAlignment: Bool = true) -> Bool {
        let metrics = getPushupMetrics(landmarks: landmarks)
        
        guard metrics.shouldersVisible && metrics.elbowsVisible && metrics.wristsVisible, // For arm bend
              let avgElbowAngle = metrics.avgElbowAngle else {
            if GlobalConstants.debugMode { print("isUserInUpPosition: Not enough arm landmarks for elbow angle.")}
            return false
        }

        let armsStraightEnough = avgElbowAngle > upElbowAngleMinThreshold
        
        var bodyAligned = true
        if checkBodyAlignment {
            bodyAligned = isBodyAligned(landmarks: landmarks)
        }

        if GlobalConstants.debugMode {
            print(String(format: "isUserInUpPosition - ElbowAngle: %.1f (StraightEnough: %@), BodyAligned: %@",
                         avgElbowAngle, String(describing: armsStraightEnough), String(describing: bodyAligned)))
        }
        
        return armsStraightEnough && bodyAligned
    }
    
    private func calculateAngle(p1: (x: CGFloat, y: CGFloat), p2: (x: CGFloat, y: CGFloat), p3: (x: CGFloat, y: CGFloat)) -> CGFloat {
        let vector1 = (x: p1.x - p2.x, y: p1.y - p2.y)
        let vector2 = (x: p3.x - p2.x, y: p3.y - p2.y)
        let dotProduct = vector1.x * vector2.x + vector1.y * vector2.y
        let magnitude1 = sqrt(vector1.x * vector1.x + vector1.y * vector1.y)
        let magnitude2 = sqrt(vector2.x * vector2.x + vector2.y * vector2.y)
        guard magnitude1 * magnitude2 != 0 else { return 0 }
        let cosineTheta = dotProduct / (magnitude1 * magnitude2)
        let angleRad = acos(max(-1.0, min(1.0, cosineTheta)))
        return angleRad * 180 / .pi
    }
}
