//
//  for.swift
//  FormForgeV1
//
//  Created by Pawel Kowalewski on 06/05/2025.
//


import MediaPipeTasksVision
import SwiftUI
import Combine
import Foundation

// Main protocol for any exercise
protocol Exercise {
    var name: String { get }
    var description: String { get }
    var targetReps: Int { get }
    var referenceImages: [UIImage]? { get }
    var referenceVideo: URL? { get }
    
    // Form checking function - returns feedback if form is incorrect
    func checkForm(landmarks: [[NormalizedLandmark]]) -> String?
    
    // Rep detection - determines if a rep was completed
    func detectRepetition(currentLandmarks: [[NormalizedLandmark]], previousLandmarks: [[NormalizedLandmark]]?) -> Bool
}

// Exercise tracker to handle state management
class ExerciseTracker: ObservableObject {
    @Published var currentExercise: Exercise?
    @Published var repCount: Int = 0
    @Published var formFeedback: String?
    @Published var isExerciseActive: Bool = false
    
    private var previousLandmarks: [[NormalizedLandmark]]?
    private let speechManager = TextSpeechManager()
    
    // Debounce feedback to prevent too frequent speech
    private var lastFeedbackTime: Date = Date.distantPast
    private let feedbackDebounceTime: TimeInterval = 3.0
    private var isVoiceFeedbackEnabled = true
    
    // Process landmarks with debouncing for form feedback
    func processLandmarks(_ landmarks: [[NormalizedLandmark]]) {
        guard let exercise = currentExercise, isExerciseActive, !landmarks.isEmpty else { return }
        
        // Check for repetition
        if exercise.detectRepetition(currentLandmarks: landmarks, previousLandmarks: previousLandmarks) {
            repCount += 1
            if isVoiceFeedbackEnabled {
                speechManager.speak("Rep \(repCount)")
            }
        }
        
        // Only check form with debouncing to reduce processing
        let now = Date()
        if now.timeIntervalSince(lastFeedbackTime) >= feedbackDebounceTime {
            // Check on background thread to avoid UI hitches
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                if let feedback = exercise.checkForm(landmarks: landmarks) {
                    DispatchQueue.main.async {
                        self.formFeedback = feedback
                        if self.isVoiceFeedbackEnabled {
                            self.speechManager.speak(feedback)
                        }
                    }
                    self.lastFeedbackTime = Date()
                } else if self.formFeedback != nil {
                    // Clear feedback when form is corrected
                    DispatchQueue.main.async {
                        self.formFeedback = nil
                    }
                }
            }
        }
        
        // Update previous landmarks
        previousLandmarks = landmarks
    }
    
    func startExercise(_ exercise: Exercise) {
        currentExercise = exercise
        repCount = 0
        formFeedback = nil
        isExerciseActive = true
        previousLandmarks = nil
        
        if isVoiceFeedbackEnabled {
            speechManager.speak("Starting \(exercise.name)")
        }
    }
    
    func endExercise() {
        if isExerciseActive && isVoiceFeedbackEnabled {
            speechManager.speak("Exercise complete")
        }
        isExerciseActive = false
    }
    
    func setVoiceFeedbackEnabled(_ enabled: Bool) {
        isVoiceFeedbackEnabled = enabled
        
        if !enabled {
            speechManager.stopSpeaking()
        }
    }
}
