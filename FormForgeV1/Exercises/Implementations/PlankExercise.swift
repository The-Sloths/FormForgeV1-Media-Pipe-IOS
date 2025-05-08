//
//  would.swift
//  FormForgeV1
//
//  Created by Pawel Kowalewski on 08/05/2025.
//


import Foundation
import MediaPipeTasksVision // Assuming this provides NormalizedLandmark
import UIKit

// (GlobalConstants and PoseLandmarkerHelper.Landmark enum would be defined as in previous examples)
// struct GlobalConstants { static let debugMode = true }
// struct PoseLandmarkerHelper { enum Landmark: Int, CaseIterable { ... } }
// protocol Exercise { ... } // Ensure this is defined, but detectRepetition might change or be unused

// Modify the Exercise protocol or create a new one for timed exercises if needed
protocol TimedExercise: Exercise {
    // Returns the currently held duration in seconds for the last processed frame.
    // The caller is responsible for accumulating total time if the exercise is paused/resumed.
    func updatePoseStateAndGetDuration(
        currentLandmarks: [[NormalizedLandmark]],
        timestamp: TimeInterval // Current frame timestamp for accurate duration calculation
    ) -> (isCorrectPose: Bool, currentDurationIncrement: TimeInterval, feedback: String?)

    func getTotalAccumulatedTime() -> TimeInterval
    func resetTimer()
}


class PlankExercise: TimedExercise { // Conform to the new or modified protocol
    let name = "Plank"
    let description = "Hold your body in a straight line, supported by forearms (or hands) and toes."
    var targetReps: Int // For TimedExercise, this might mean target duration in seconds
    let referenceImages: [UIImage]?
    let referenceVideo: URL?

    enum PlankType {
        case forearm
        case straightArm
    }
    private let plankType: PlankType

    // Tunable parameters
    private let minKeypointScore: Float = 0.25
    private var isActivelyHoldingPlank = false // True if user is currently in correct plank pose for consecutive frames
    private var poseConfirmationFrameCount = 0
    private let requiredFramesToConfirmPose = 5 // Frames to confirm entering/exiting plank

    // Body alignment thresholds (Shoulder-Hip-Ankle or Shoulder-Hip-Knee)
    private let minBodyStraightAngle: CGFloat = 160.0 // Min angle for Shoulder-Hip-Ankle/Knee
    private let maxBodyStraightAngle: CGFloat = 200.0 // Max angle (180 +/- 20-ish)
    
    // Forearm plank specific: Elbows under shoulders (X-coordinate check)
    private let maxShoulderElbowXDiff: Float = 0.15 // Max normalized X distance between shoulder and elbow

    // Straight-arm plank specific: Elbow angle
    private let straightArmElbowAngleMinThreshold: CGFloat = 150.0

    // Timing
    private var accumulatedHoldTime: TimeInterval = 0
    private var lastFrameTimestamp: TimeInterval? = nil

    // To satisfy Exercise protocol if needed, though not primary for plank
    func detectRepetition(currentLandmarks: [[NormalizedLandmark]], previousLandmarks: [[NormalizedLandmark]]?) -> Bool {
        // This method is not the primary interaction for Plank.
        // You could make it update the timer and return true if time increased, but it's awkward.
        // Prefer using updatePoseStateAndGetDuration.
        if let timestamp = previousLandmarks == nil ? lastFrameTimestamp : CACurrentMediaTime() { // Crude timestamp
             _ = updatePoseStateAndGetDuration(currentLandmarks: currentLandmarks, timestamp: timestamp)
        }
        return false // Not rep-based
    }


    init(targetDurationSeconds: Int = 30,
         plankType: PlankType = .forearm, // Default to forearm plank
         referenceImages: [UIImage]? = nil,
         referenceVideo: URL? = nil) {
        self.targetReps = targetDurationSeconds // Re-purposing targetReps for duration
        self.plankType = plankType
        self.referenceImages = referenceImages
        self.referenceVideo = referenceVideo
    }

    /// Updates the plank state based on current landmarks and calculates duration increment.
    /// - Parameter timestamp: Current frame timestamp (e.g., from `AVCaptureVideoDataOutputSampleBufferDelegate` or `DisplayLink`).
    /// - Returns: Tuple containing:
    ///   - `isCorrectPose`: Bool indicating if the plank form is currently correct.
    ///   - `currentDurationIncrement`: TimeInterval, how much duration was added in this frame (0 if form is incorrect).
    ///   - `feedback`: String? with form correction advice.
    func updatePoseStateAndGetDuration(
        currentLandmarks: [[NormalizedLandmark]],
        timestamp: TimeInterval
    ) -> (isCorrectPose: Bool, currentDurationIncrement: TimeInterval, feedback: String?) {
        
        var durationIncrement: TimeInterval = 0
        let deltaTime: TimeInterval
        
        if let lastTs = lastFrameTimestamp {
            deltaTime = timestamp - lastTs
        } else {
            deltaTime = 0 // First frame, no delta yet
        }
        lastFrameTimestamp = timestamp

        guard !currentLandmarks.isEmpty, let poseLandmarks = currentLandmarks.first,
              areCriticalLandmarksVisible(poseLandmarks) else {
            if isActivelyHoldingPlank { // If was holding and lost visibility
                isActivelyHoldingPlank = false
                poseConfirmationFrameCount = 0
                if GlobalConstants.debugMode { print("PlankUpdate: Lost visibility, stopping plank hold.") }
            }
            return (false, 0, "Ensure your whole body is visible.")
        }

        let (isCurrentlyCorrect, formFeedback) = isHoldingCorrectPlankPose(landmarks: poseLandmarks)

        if isCurrentlyCorrect {
            poseConfirmationFrameCount += 1
            if poseConfirmationFrameCount >= requiredFramesToConfirmPose {
                if !isActivelyHoldingPlank {
                    if GlobalConstants.debugMode { print("PlankUpdate: Plank hold confirmed and started/resumed.") }
                    isActivelyHoldingPlank = true // Confirmed holding
                }
                // Only add duration if actively holding and delta is reasonable
                if deltaTime > 0 && deltaTime < 0.5 { // Avoid huge jumps if timestamp is weird
                    durationIncrement = deltaTime
                    accumulatedHoldTime += durationIncrement
                }
            }
        } else { // Form is incorrect or landmarks missing
            poseConfirmationFrameCount = 0 // Reset confirmation counter
            if isActivelyHoldingPlank {
                if GlobalConstants.debugMode { print("PlankUpdate: Plank form broken, pausing hold.") }
                isActivelyHoldingPlank = false // No longer holding
            }
        }
        
        if GlobalConstants.debugMode {
            print("PlankUpdate - CorrectPose: \(isCurrentlyCorrect), ActivelyHolding: \(isActivelyHoldingPlank), ConfirmFrames: \(poseConfirmationFrameCount), Increment: \(String(format: "%.3f", durationIncrement)), Total: \(String(format: "%.2f", accumulatedHoldTime)), Feedback: \(formFeedback ?? "None")")
        }

        return (isActivelyHoldingPlank, durationIncrement, formFeedback)
    }

    func getTotalAccumulatedTime() -> TimeInterval {
        return accumulatedHoldTime
    }

    func resetTimer() {
        accumulatedHoldTime = 0
        isActivelyHoldingPlank = false
        poseConfirmationFrameCount = 0
        lastFrameTimestamp = nil
        if GlobalConstants.debugMode { print("PlankTimer: Reset.")}
    }

    func checkForm(landmarks: [[NormalizedLandmark]]) -> String? {
        // This can now directly use the feedback from isHoldingCorrectPlankPose
        guard !landmarks.isEmpty, let poseLandmarks = landmarks.first,
              areCriticalLandmarksVisible(poseLandmarks) else {
            return "Ensure your whole body is visible."
        }
        let (_, feedback) = isHoldingCorrectPlankPose(landmarks: poseLandmarks)
        return feedback // Return the detailed feedback
    }

    // MARK: - Private Helper Methods

    private func getLandmark(_ landmarkType: PoseLandmarkerHelper.Landmark, from landmarks: [NormalizedLandmark]) -> NormalizedLandmark? {
        let landmarkIndex = landmarkType.rawValue
        guard landmarkIndex >= 0 && landmarkIndex < landmarks.count else {
             if GlobalConstants.debugMode { print("getLandmark (Plank): Index \(landmarkIndex) for \(landmarkType.stringValue) out of bounds (count: \(landmarks.count)).") }
            return nil
        }
        return landmarks[landmarkIndex]
    }

    private func areCriticalLandmarksVisible(_ landmarks: [NormalizedLandmark]) -> Bool {
        var criticalTypes: [PoseLandmarkerHelper.Landmark] = [
            .leftShoulder, .rightShoulder,
            .leftHip, .rightHip
        ]

        // Determine end support based on your plank setup (toes or knees)
        // For this example, assuming toe plank. Modify if you intend knee plank support.
        let endSupportLeft: PoseLandmarkerHelper.Landmark = .leftAnkle
        let endSupportRight: PoseLandmarkerHelper.Landmark = .rightAnkle
        criticalTypes.append(contentsOf: [endSupportLeft, endSupportRight])

        if plankType == .forearm {
            criticalTypes.append(contentsOf: [.leftElbow, .rightElbow])
        } else { // .straightArm
            criticalTypes.append(contentsOf: [.leftElbow, .rightElbow, .leftWrist, .rightWrist])
        }

        if GlobalConstants.debugMode {
            print("\n--- Checking Critical Landmark Visibility (PlankType: \(plankType), MinScore: \(minKeypointScore)) ---")
            var allActuallyVisible = true
            for type in criticalTypes {
                let landmark = getLandmark(type, from: landmarks)
                let visibilityScore = landmark?.visibility?.floatValue ?? -1.0 // -1.0 if landmark itself is nil (not found by getLandmark)

                if landmark != nil && visibilityScore >= minKeypointScore {
                    print("  ✅ \(type.stringValue): VISIBLE (Score: \(String(format: "%.2f", visibilityScore)))")
                } else {
                    let reason = landmark == nil ? "NOT FOUND" : "LOW VISIBILITY"
                    print("  ❌ \(type.stringValue): FAILED (Score: \(String(format: "%.2f", visibilityScore))) - Reason: \(reason)")
                    allActuallyVisible = false
                    // Don't return false immediately in debug mode; print all landmark statuses
                }
            }

            if allActuallyVisible {
                print("--- Critical Landmark Visibility Check: PASSED ---")
                return true
            } else {
                print("--- Critical Landmark Visibility Check: FAILED ---")
                return false
            }
        } else {
            // Original non-debug logic for efficiency
            for type in criticalTypes {
                guard let landmark = getLandmark(type, from: landmarks),
                      (landmark.visibility?.floatValue ?? 0) >= minKeypointScore else {
                    return false // Fail fast if any landmark is not sufficiently visible
                }
            }
            return true
        }
    }

    /// Checks if the user is holding a correct plank pose.
    /// Returns a boolean indicating correctness and a feedback string.
    private func isHoldingCorrectPlankPose(landmarks: [NormalizedLandmark]) -> (isCorrect: Bool, feedback: String?) {
        // 1. Body Alignment (Shoulder-Hip-Ankle/Knee)
        guard let (isBodyStraight, bodyAngle, bodyAlignmentFeedback) = checkBodyAlignment(landmarks: landmarks) else {
            return (false, "Could not determine body alignment.")
        }
        if !isBodyStraight {
            return (false, bodyAlignmentFeedback)
        }

        // 2. Plank Type Specific Checks
        var plankTypeSpecificCheckMet = false
        var plankTypeFeedback: String? = nil

        switch plankType {
        case .forearm:
            let (isCorrectForearm, forearmFeedback) = checkForearmPlankSpecifics(landmarks: landmarks)
            plankTypeSpecificCheckMet = isCorrectForearm
            plankTypeFeedback = forearmFeedback
        case .straightArm:
            let (isCorrectStraightArm, straightArmFeedback) = checkStraightArmPlankSpecifics(landmarks: landmarks)
            plankTypeSpecificCheckMet = isCorrectStraightArm
            plankTypeFeedback = straightArmFeedback
        }
        
        if !plankTypeSpecificCheckMet {
            return (false, plankTypeFeedback)
        }

        if GlobalConstants.debugMode && isBodyStraight && plankTypeSpecificCheckMet {
           // print("isHoldingCorrectPlankPose: Pose is correct. BodyAngle: \(bodyAngle ?? -1)")
        }
        return (true, nil) // All checks passed
    }
    
    private func checkBodyAlignment(landmarks: [NormalizedLandmark]) -> (isStraight: Bool, angle: CGFloat?, feedback: String?)? {
        // Using Ankles for full plank. For knee plank, replace Ankles with Knees.
        // For knee planks, you'd pass a different landmark type here or make it a parameter.
        let endSupportLandmarkTypeLeft: PoseLandmarkerHelper.Landmark = .leftAnkle // Or .leftKnee for knee plank
        let endSupportLandmarkTypeRight: PoseLandmarkerHelper.Landmark = .rightAnkle // Or .rightKnee for knee plank

        guard let leftShoulder = getLandmark(.leftShoulder, from: landmarks),
              let rightShoulder = getLandmark(.rightShoulder, from: landmarks),
              let leftHip = getLandmark(.leftHip, from: landmarks),
              let rightHip = getLandmark(.rightHip, from: landmarks),
              let leftEndSupport = getLandmark(endSupportLandmarkTypeLeft, from: landmarks), // Renamed variable
              let rightEndSupport = getLandmark(endSupportLandmarkTypeRight, from: landmarks) else { // Renamed variable
            return (false, nil, "Key alignment points not visible (landmarks not found in array).")
        }

        // Check visibility of the unwrapped landmarks
        let essentialLandmarks: [NormalizedLandmark] = [leftShoulder, rightShoulder, leftHip, rightHip, leftEndSupport, rightEndSupport]
        guard essentialLandmarks.allSatisfy({ ($0.visibility?.floatValue ?? 0) >= minKeypointScore }) else {
            if GlobalConstants.debugMode {
                // Find which landmark failed visibility for better debugging
                for landmark in essentialLandmarks {
                    if (landmark.visibility?.floatValue ?? 0) < minKeypointScore {
                        // To get the name, you'd need a way to map back from the landmark object to its type,
                        // or check their types before adding to essentialLandmarks and print the type.
                        // For now, a general message:
                        print("checkBodyAlignment: A key alignment point's visibility is too low.")
                        break
                    }
                }
            }
            return (false, nil, "Key alignment points visibility too low.")
        }

        let midShoulder = (x: (leftShoulder.x + rightShoulder.x) / 2, y: (leftShoulder.y + rightShoulder.y) / 2)
        let midHip = (x: (leftHip.x + rightHip.x) / 2, y: (leftHip.y + rightHip.y) / 2)
        let midEndSupport = (x: (leftEndSupport.x + rightEndSupport.x) / 2, y: (leftEndSupport.y + rightEndSupport.y) / 2) // Renamed variable

        let bodyAngle = calculateAngle(
            p1: (x: CGFloat(midShoulder.x), y: CGFloat(midShoulder.y)),
            p2: (x: CGFloat(midHip.x), y: CGFloat(midHip.y)), // Vertex is Hip
            p3: (x: CGFloat(midEndSupport.x), y: CGFloat(midEndSupport.y))
        )

        if bodyAngle < minBodyStraightAngle {
            return (false, bodyAngle, "Hips too high (piking). Lower your hips.")
        } else if bodyAngle > maxBodyStraightAngle {
            return (false, bodyAngle, "Hips too low (sagging). Engage your core.")
        }
        
        if GlobalConstants.debugMode {
            print("checkBodyAlignment: Body is straight. Angle: \(String(format: "%.1f", bodyAngle))")
        }
        return (true, bodyAngle, nil)
    }

    private func checkForearmPlankSpecifics(landmarks: [NormalizedLandmark]) -> (isCorrect: Bool, feedback: String?) {
        guard let leftShoulder = getLandmark(.leftShoulder, from: landmarks),
              let rightShoulder = getLandmark(.rightShoulder, from: landmarks),
              let leftElbow = getLandmark(.leftElbow, from: landmarks),
              let rightElbow = getLandmark(.rightElbow, from: landmarks) else {
            return (false, "Shoulder or elbow landmarks not visible for forearm plank check.")
        }
        guard [leftShoulder, rightShoulder, leftElbow, rightElbow].allSatisfy({($0.visibility?.floatValue ?? 0) >= minKeypointScore}) else {
             return (false, "Shoulder or elbow landmark visibility too low.")
        }


        // Check if elbows are roughly under shoulders (X-coordinate difference)
        let avgShoulderX = (leftShoulder.x + rightShoulder.x) / 2
        let avgElbowX = (leftElbow.x + rightElbow.x) / 2
        
        if abs(avgShoulderX - avgElbowX) > maxShoulderElbowXDiff {
            let feedback = avgElbowX < avgShoulderX ? "Elbows too far back. Move them under your shoulders." : "Elbows too far forward. Move them under your shoulders."
            if GlobalConstants.debugMode { print("ForearmPlankSpecifics: Elbows not under shoulders. DiffX: \(abs(avgShoulderX - avgElbowX))")}
            return (false, feedback)
        }
        
        // Could also check Y-coordinates if desired, e.g., shoulders not significantly higher than elbows
        // let avgShoulderY = (leftShoulder.y + rightShoulder.y) / 2
        // let avgElbowY = (leftElbow.y + rightElbow.y) / 2
        // if avgShoulderY < avgElbowY - 0.05 { /* Shoulders much higher than elbows */ return (false, "Lower your shoulders closer to elbow height.")}

        return (true, nil)
    }

    private func checkStraightArmPlankSpecifics(landmarks: [NormalizedLandmark]) -> (isCorrect: Bool, feedback: String?) {
        guard let leftShoulder = getLandmark(.leftShoulder, from: landmarks),
              let rightShoulder = getLandmark(.rightShoulder, from: landmarks),
              let leftElbow = getLandmark(.leftElbow, from: landmarks),
              let rightElbow = getLandmark(.rightElbow, from: landmarks),
              let leftWrist = getLandmark(.leftWrist, from: landmarks),
              let rightWrist = getLandmark(.rightWrist, from: landmarks) else {
            return (false, "Key arm landmarks not visible for straight-arm plank check.")
        }
         guard [leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist].allSatisfy({($0.visibility?.floatValue ?? 0) >= minKeypointScore}) else {
             return (false, "Key arm landmark visibility too low.")
        }


        // 1. Elbows straight enough
        let lElbowAngle = calculateAngle(
            p1: (x: CGFloat(leftShoulder.x), y: CGFloat(leftShoulder.y)),
            p2: (x: CGFloat(leftElbow.x), y: CGFloat(leftElbow.y)),
            p3: (x: CGFloat(leftWrist.x), y: CGFloat(leftWrist.y))
        )
        let rElbowAngle = calculateAngle(
            p1: (x: CGFloat(rightShoulder.x), y: CGFloat(rightShoulder.y)),
            p2: (x: CGFloat(rightElbow.x), y: CGFloat(rightElbow.y)),
            p3: (x: CGFloat(rightWrist.x), y: CGFloat(rightWrist.y))
        )
        // Consider using the average or ensuring both are straight if both visible
        let avgElbowAngle = (lElbowAngle + rElbowAngle) / 2 // Simple average; could be more robust if one side isn't visible

        if avgElbowAngle < straightArmElbowAngleMinThreshold {
             if GlobalConstants.debugMode { print("StraightArmPlankSpecifics: Elbows bent. Angle: \(avgElbowAngle)")}
            return (false, "Straighten your arms.")
        }

        // 2. Wrists roughly under shoulders (X-coordinate difference)
        let avgShoulderX = (leftShoulder.x + rightShoulder.x) / 2
        let avgWristX = (leftWrist.x + rightWrist.x) / 2
        
        // Using maxShoulderElbowXDiff for wrists as well, can be a separate threshold
        if abs(avgShoulderX - avgWristX) > maxShoulderElbowXDiff { // Renamed in mind: maxShoulderSupportXDiff
            let feedback = avgWristX < avgShoulderX ? "Hands too far back. Move them under your shoulders." : "Hands too far forward. Move them under your shoulders."
            if GlobalConstants.debugMode { print("StraightArmPlankSpecifics: Wrists not under shoulders. DiffX: \(abs(avgShoulderX - avgWristX))")}
            return (false, feedback)
        }
        return (true, nil)
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
