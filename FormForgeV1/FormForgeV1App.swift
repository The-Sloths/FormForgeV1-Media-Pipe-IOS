//
//  FormForgeV1App.swift
//  FormForgeV1
//
//  Created by Pawel Kowalewski on 06/05/2025.
//

import SwiftUI

@main
struct FormForgeV1App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Download models if needed
        downloadModelsIfNeeded()
        return true
    }
    
    private func downloadModelsIfNeeded() {
        // Check if models exist and download if necessary
        let fileManager = FileManager.default
        let bundlePath = Bundle.main.resourcePath!
        
        let modelNames = ["pose_landmarker_lite", "pose_landmarker_full", "pose_landmarker_heavy"]
        
        for modelName in modelNames {
            let modelPath = "\(bundlePath)/\(modelName).task"
            
            if !fileManager.fileExists(atPath: modelPath) {
                // Model doesn't exist, download it
                downloadModel(named: modelName)
            }
        }
    }
    
    private func downloadModel(named modelName: String) {
        let urlString = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/\(modelName)/float16/latest/\(modelName).task"
        
        guard let url = URL(string: urlString),
              let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let destinationPath = documentsDir.appendingPathComponent("\(modelName).task")
        
        let downloadTask = URLSession.shared.downloadTask(with: url) { tempURL, _, error in
            guard let tempURL = tempURL, error == nil else {
                print("Error downloading model \(modelName): \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            do {
                // Remove any existing file
                if FileManager.default.fileExists(atPath: destinationPath.path) {
                    try FileManager.default.removeItem(at: destinationPath)
                }
                
                // Copy downloaded file to destination
                try FileManager.default.copyItem(at: tempURL, to: destinationPath)
                print("Successfully downloaded \(modelName) to \(destinationPath.path)")
            } catch {
                print("Error saving model \(modelName): \(error.localizedDescription)")
            }
        }
        
        downloadTask.resume()
    }
}
