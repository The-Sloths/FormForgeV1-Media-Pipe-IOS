//
//  CameraManager.swift
//  FormForgeV1
//
//  Created by Pawel Kowalewski on 06/05/2025.
//

import AVFoundation
import SwiftUI
import Combine

class CameraManager: NSObject, ObservableObject {
    enum Status {
        case unconfigured
        case configured
        case unauthorized
        case failed
    }
    
    @Published var error: CameraError?
    @Published var frame: CGImage?
    @Published var status = Status.unconfigured
    @Published var cameraPosition: AVCaptureDevice.Position = .front
    
    // Performance monitoring
    @Published var processingPerformance: Double = 0 // milliseconds per frame
    private var frameProcessingTimes: [TimeInterval] = []
    private let maxTimeHistoryCount = 30
    
    private let cameraQueue = DispatchQueue(label: "com.sloths.formforgev1.cameraqueue", qos: .userInteractive)
    private var captureSession: AVCaptureSession?
    private var videoOutput = AVCaptureVideoDataOutput()
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    
    private var lastProcessingTime: Date?
    private var minimumProcessingInterval: TimeInterval = 0.2 // Dynamic based on performance
    private let targetProcessingInterval: TimeInterval = 0.1 // 10 FPS target
    
    // Image size control
    private let processingScale: CGFloat = 0.5 // Downsample images to 50%
    private var imageBufferSize: CGSize?
    
    func switchCamera() {
        // Stop current session
        self.stop()
        
        // Toggle camera position
        cameraPosition = cameraPosition == .back ? .front : .back
        
        // Reset performance metrics when switching camera
        frameProcessingTimes.removeAll()
        processingPerformance = 0
        
        // Reconfigure and restart
        DispatchQueue.main.async {
            self.configureSession()
        }
    }
    
    var videoOrientation: AVCaptureVideoOrientation {
        switch UIDevice.current.orientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            return .portrait
        }
    }
    
    var videoResolution: CGSize {
        get {
            guard let size = imageBufferSize else {
                return CGSize.zero
            }
            let minDimension = min(size.width, size.height)
            let maxDimension = max(size.width, size.height)
            switch UIDevice.current.orientation {
            case .portrait:
                return CGSize(width: minDimension, height: maxDimension)
            case .landscapeLeft, .landscapeRight:
                return CGSize(width: maxDimension, height: minDimension)
            default:
                return CGSize(width: minDimension, height: maxDimension)
            }
        }
    }
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            requestPermissions()
        case .authorized:
            configureSession()
        case .denied, .restricted:
            status = .unauthorized
            error = .deniedAuthorization
        @unknown default:
            status = .unauthorized
            error = .unknownAuthorization
        }
    }
    
    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.configureSession()
                } else {
                    self?.status = .unauthorized
                    self?.error = .deniedAuthorization
                }
            }
        }
    }
    
    func configureSession() {
        cameraQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Create a new session
            self.captureSession = AVCaptureSession()
            self.captureSession?.beginConfiguration()
            
            // Use lowest resolution that still gives good results
            self.captureSession?.sessionPreset = .vga640x480 // Lower resolution for better performance
            
            // Remove any existing inputs and outputs
            if let inputs = self.captureSession?.inputs as? [AVCaptureInput] {
                for input in inputs {
                    self.captureSession?.removeInput(input)
                }
            }
            
            if let outputs = self.captureSession?.outputs as? [AVCaptureOutput] {
                for output in outputs {
                    self.captureSession?.removeOutput(output)
                }
            }
            
            guard self.addVideoDeviceInput() else {
                self.status = .failed
                self.error = .cameraUnavailable
                self.captureSession?.commitConfiguration()
                return
            }
            
            guard self.addVideoDataOutput() else {
                self.status = .failed
                self.error = .cannotAddOutput
                self.captureSession?.commitConfiguration()
                return
            }
            
            // Apply advanced configuration
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.cameraPosition) {
                do {
                    try device.lockForConfiguration()
                    // Disable unnecessary features for performance
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                    // Reduce frame rate if needed (especially important for older devices)
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 20) // Limit to 20 FPS max
                    device.unlockForConfiguration()
                } catch {
                    print("Error configuring camera device: \(error)")
                }
            }
            
            self.captureSession?.commitConfiguration()
            self.captureSession?.startRunning()
            self.status = .configured
        }
    }
    
    private func addVideoDeviceInput() -> Bool {
        // Use the current cameraPosition
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition) else {
            return false
        }
        
        do {
            let videoDeviceInput = try AVCaptureDeviceInput(device: camera)
            if captureSession?.canAddInput(videoDeviceInput) == true {
                captureSession?.addInput(videoDeviceInput)
                return true
            } else {
                return false
            }
        } catch {
            self.error = .cannotAddInput
            return false
        }
    }
    
    private func addVideoDataOutput() -> Bool {
        videoOutput.setSampleBufferDelegate(self, queue: cameraQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [String(kCVPixelBufferPixelFormatTypeKey): kCMPixelFormat_32BGRA]
        
        if captureSession?.canAddOutput(videoOutput) == true {
            captureSession?.addOutput(videoOutput)
            videoOutput.connection(with: .video)?.videoOrientation = .portrait
            
            // Add mirroring for front camera
            if cameraPosition == .front {
                videoOutput.connection(with: .video)?.isVideoMirrored = true
            } else {
                videoOutput.connection(with: .video)?.isVideoMirrored = false
            }
            
            return true
        } else {
            return false
        }
    }
    
    // Dynamically adjust frame processing rate based on performance
    private func updateProcessingInterval(_ processingTime: TimeInterval) {
        frameProcessingTimes.append(processingTime)
        if frameProcessingTimes.count > maxTimeHistoryCount {
            frameProcessingTimes.removeFirst()
        }
        
        if frameProcessingTimes.count >= 10 {
            let avgProcessingTime = frameProcessingTimes.reduce(0, +) / Double(frameProcessingTimes.count)
            
            // Publish the performance metric (in milliseconds)
            DispatchQueue.main.async {
                self.processingPerformance = avgProcessingTime * 1000
            }
            
            // If processing takes longer than our target, reduce frame rate
            if avgProcessingTime > targetProcessingInterval * 0.8 {
                minimumProcessingInterval = min(0.5, minimumProcessingInterval * 1.2) // Increase interval, but cap at 0.5s (2 FPS)
            } else if avgProcessingTime < targetProcessingInterval * 0.5 {
                minimumProcessingInterval = max(0.033, minimumProcessingInterval * 0.8) // Decrease interval, but not below 30 FPS
            }
        }
    }
    
    func start() {
        cameraQueue.async { [weak self] in
            guard let self = self, self.status == .configured else { return }
            self.captureSession?.startRunning()
        }
    }
    
    func stop() {
        cameraQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }
    
    deinit {
        stop()
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Dynamic frame rate control - skip frames when needed
        let currentTime = Date()
        guard lastProcessingTime == nil || currentTime.timeIntervalSince(lastProcessingTime!) >= minimumProcessingInterval else {
            return // Skip this frame
        }
        
        let frameStartTime = Date()
        lastProcessingTime = currentTime
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        if (imageBufferSize == nil) {
            imageBufferSize = CGSize(width: CVPixelBufferGetHeight(imageBuffer), height: CVPixelBufferGetWidth(imageBuffer))
        }
        
        // Process frame and pass to PoseLandmarker service
        connection.videoOrientation = videoOrientation
        
        // Create a downsampled image to reduce processing requirements
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext(options: [.cacheIntermediates: false, .priorityRequestLow: true])
        
        // Calculate scaled dimensions
        let originalWidth = ciImage.extent.width
        let originalHeight = ciImage.extent.height
        let scaledWidth = originalWidth * processingScale
        let scaledHeight = originalHeight * processingScale
        
        // Create a scaled ciImage
        let scale = CGAffineTransform(scaleX: processingScale, y: processingScale)
        let scaledCIImage = ciImage.transformed(by: scale)
        
        guard let cgImage = context.createCGImage(scaledCIImage, from: scaledCIImage.extent) else { return }
        
        // Update performance metrics
        let processingTime = Date().timeIntervalSince(frameStartTime)
        updateProcessingInterval(processingTime)
        
        // Notify subscribers about the new frame
        DispatchQueue.main.async { [weak self] in
            self?.frame = cgImage
        }
    }
}

enum CameraError: Error {
    case deniedAuthorization
    case restrictedAuthorization
    case unknownAuthorization
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
    case createCaptureInput(Error)
    case createCaptureOutput(Error)
    case createCaptureSession(Error)
}

// Extension to UIImage for downsampling if needed elsewhere
extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        return UIGraphicsImageRenderer(size: size).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
