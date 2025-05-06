//
//  TextSpeechManager.swift
//  FormForgeV1
//
//  Created by Pawel Kowalewski on 06/05/2025.
//


import Foundation
import AVFoundation

class TextSpeechManager {
    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenText: String = ""
    private var lastSpeechTime: Date = Date.distantPast
    private let minTimeBetweenSpeech: TimeInterval = 2.0 // Minimum seconds between utterances
    
    // Use a lighter voice setting for better performance
    var speechRate: Float = 0.5
    var speechVolume: Float = 1.0
    
    func speak(_ text: String) {
        // Don't repeat the same message within the minimum time window
        let now = Date()
        if text == lastSpokenText && now.timeIntervalSince(lastSpeechTime) < minTimeBetweenSpeech {
            return
        }
        
        // Use a background queue for speech preparation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // If already speaking, finish the current utterance before starting new one
            if self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(at: .word)
            }
            
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = self.speechRate
            utterance.volume = self.speechVolume
            
            // Use default voice - custom voices can be resource-intensive
            if let voice = AVSpeechSynthesisVoice(language: "en-US") {
                utterance.voice = voice
            }
            
            self.lastSpokenText = text
            self.lastSpeechTime = now
            
            self.synthesizer.speak(utterance)
        }
    }
    
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
