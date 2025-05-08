//
//  ExerciseSelectionView.swift
//  FormForgeV1
//
//  Created by Pawel Kowalewski on 06/05/2025.
//

import SwiftUI

struct ExerciseSelectionView: View {
    @ObservedObject var exerciseTracker: ExerciseTracker
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List {
                Button("Squats - 10 reps") {
                    exerciseTracker.startExercise(SquatExercise(targetReps: 10))
                    presentationMode.wrappedValue.dismiss()
                }
                
                Button("Pushups - 10 reps") {
                    exerciseTracker.startExercise(PushupExercise(targetReps: 10))
                    presentationMode.wrappedValue.dismiss()
                }
                
                Button("Plank") {
                    exerciseTracker.startExercise(PlankExercise(targetDurationSeconds: 30, plankType: .forearm))
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .navigationTitle("Select Exercise")
            .navigationBarItems(trailing: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
