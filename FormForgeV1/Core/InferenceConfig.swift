//
//  InferenceConfig.swift
//  FormForgeV1
//
//  Created by Pawel Kowalewski on 06/05/2025.
//


import Foundation
import MediaPipeTasksVision
import Combine

class InferenceConfig: ObservableObject {
    static let shared = InferenceConfig()
    
    @Published var model: Model = .pose_landmarker_lite
    @Published var delegate: PoseLandmarkerDelegate = .CPU
    @Published var numPoses: Int = 1
    @Published var minPoseDetectionConfidence: Float = 0.5
    @Published var minPosePresenceConfidence: Float = 0.5
    @Published var minTrackingConfidence: Float = 0.5
    
    private init() {}
}

// MARK: Model
enum Model: Int, CaseIterable, Identifiable {
    case pose_landmarker_lite
    case pose_landmarker_full
    case pose_landmarker_heavy
    
    var id: Int { rawValue }
    
    var name: String {
        switch self {
        case .pose_landmarker_lite:
            return "Pose landmarker (lite)"
        case .pose_landmarker_full:
            return "Pose landmarker (Full)"
        case .pose_landmarker_heavy:
            return "Pose landmarker (Heavy)"
        }
    }
    
    var modelPath: String? {
        switch self {
        case .pose_landmarker_lite:
            return Bundle.main.path(forResource: "pose_landmarker_lite", ofType: "task")
        case .pose_landmarker_full:
            return Bundle.main.path(forResource: "pose_landmarker_full", ofType: "task")
        case .pose_landmarker_heavy:
            return Bundle.main.path(forResource: "pose_landmarker_heavy", ofType: "task")
        }
    }
}

// MARK: PoseLandmarkerDelegate
enum PoseLandmarkerDelegate: Int, CaseIterable, Identifiable {
    case GPU
    case CPU
    
    var id: Int { rawValue }
    
    var name: String {
        switch self {
        case .GPU:
            return "GPU"
        case .CPU:
            return "CPU"
        }
    }
    
    var delegate: Delegate {
        switch self {
        case .GPU:
            return .GPU
        case .CPU:
            return .CPU
        }
    }
}