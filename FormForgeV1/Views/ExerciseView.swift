//
//  ExerciseView.swift
//  FormForgeV1
//
//  Created by Pawel Kowalewski on 06/05/2025.
//

import SwiftUI
import MediaPipeTasksVision

struct ExerciseView: View {
    @ObservedObject var exerciseTracker: ExerciseTracker
    @ObservedObject var poseLandmarkerService: PoseLandmarkerService
    
    var body: some View {
        ZStack {
            // Your camera view (already implemented)
            // ...
            
            // Exercise overlay
            if exerciseTracker.isExerciseActive {
                VStack {
                    // Exercise info
                    HStack {
                        VStack(alignment: .leading) {
                            Text(exerciseTracker.currentExercise?.name ?? "")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("Reps: \(exerciseTracker.repCount)/\(exerciseTracker.currentExercise?.targetReps ?? 0)")
                                .font(.title2)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Form feedback
                    if let feedback = exerciseTracker.formFeedback {
                        Text(feedback)
                            .font(.headline)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .padding()
                    }
                }
            }
        }
        .onReceive(poseLandmarkerService.$resultBundle) { resultBundle in
            if let result = resultBundle,
               let poseLandmarkerResult = result.poseLandmarkerResults.first as? PoseLandmarkerResult {
                exerciseTracker.processLandmarks(poseLandmarkerResult.landmarks)
            }
        }
    }
}
