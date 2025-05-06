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
    
    // Process new landmarks from pose detection
    func processLandmarks(_ landmarks: [[NormalizedLandmark]]) {
        guard let exercise = currentExercise, isExerciseActive, !landmarks.isEmpty else { return }
        
        // Check form and provide feedback
        formFeedback = exercise.checkForm(landmarks: landmarks)
        
        // Check for repetition
        if exercise.detectRepetition(currentLandmarks: landmarks, previousLandmarks: previousLandmarks) {
            repCount += 1
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
    }
    
    func endExercise() {
        isExerciseActive = false
    }
}
