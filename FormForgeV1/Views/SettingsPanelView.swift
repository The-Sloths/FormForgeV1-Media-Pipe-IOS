//
//  SettingsPanelView.swift
//  FormForgeV1
//
//  Created by Pawel Kowalewski on 06/05/2025.
//


import SwiftUI
import MediaPipeTasksVision

struct SettingsPanelView: View {
    @ObservedObject var inferenceConfig = InferenceConfig.shared
    @ObservedObject var poseLandmarkerService: PoseLandmarkerService
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 10) {
            // Expand/collapse button
            HStack {
                Spacer()
                Button(action: {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
                Spacer()
            }
            
            if isExpanded {
                // Inference time
                if let resultBundle = poseLandmarkerService.resultBundle {
                    HStack {
                        Text("Inference Time:")
                            .foregroundColor(.white)
                        Spacer()
                        Text(String(format: "%.2f ms", resultBundle.inferenceTime))
                            .foregroundColor(.white)
                    }
                    Divider().background(Color.white)
                }
                
                // Model selection
                HStack {
                    Text("Model:")
                        .foregroundColor(.white)
                    Spacer()
                    Picker("Model", selection: $inferenceConfig.model) {
                        ForEach(Model.allCases) { model in
                            Text(model.name).tag(model)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                // Delegate selection
                HStack {
                    Text("Delegate:")
                        .foregroundColor(.white)
                    Spacer()
                    Picker("Delegate", selection: $inferenceConfig.delegate) {
                        ForEach(PoseLandmarkerDelegate.allCases) { delegate in
                            Text(delegate.name).tag(delegate)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                // Num poses stepper
                HStack {
                    Text("Number of Poses:")
                        .foregroundColor(.white)
                    Spacer()
                    Stepper(value: $inferenceConfig.numPoses, in: 1...5) {
                        Text("\(inferenceConfig.numPoses)")
                            .foregroundColor(.white)
                    }
                }
                
                // Min pose detection confidence slider
                VStack(alignment: .leading) {
                    Text("Min Pose Detection Confidence: \(inferenceConfig.minPoseDetectionConfidence, specifier: "%.2f")")
                        .foregroundColor(.white)
                    Slider(value: $inferenceConfig.minPoseDetectionConfidence, in: 0...1, step: 0.05)
                }
                
                // Min pose presence confidence slider
                VStack(alignment: .leading) {
                    Text("Min Pose Presence Confidence: \(inferenceConfig.minPosePresenceConfidence, specifier: "%.2f")")
                        .foregroundColor(.white)
                    Slider(value: $inferenceConfig.minPosePresenceConfidence, in: 0...1, step: 0.05)
                }
                
                // Min tracking confidence slider
                VStack(alignment: .leading) {
                    Text("Min Tracking Confidence: \(inferenceConfig.minTrackingConfidence, specifier: "%.2f")")
                        .foregroundColor(.white)
                    Slider(value: $inferenceConfig.minTrackingConfidence, in: 0...1, step: 0.05)
                }
            }
        }
    }
}
