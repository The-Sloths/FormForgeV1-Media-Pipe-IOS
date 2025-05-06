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
    
    private let cameraQueue = DispatchQueue(label: "com.yourapp.cameraqueue")
    private var captureSession: AVCaptureSession?
    private var videoOutput = AVCaptureVideoDataOutput()
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    
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
    
    private var imageBufferSize: CGSize?
    
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
            
            self.captureSession = AVCaptureSession()
            self.captureSession?.beginConfiguration()
            
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
            
            self.captureSession?.commitConfiguration()
            self.captureSession?.startRunning()
            self.status = .configured
        }
    }
    
    private func addVideoDeviceInput() -> Bool {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
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
            return true
        } else {
            return false
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
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        if (imageBufferSize == nil) {
            imageBufferSize = CGSize(width: CVPixelBufferGetHeight(imageBuffer), height: CVPixelBufferGetWidth(imageBuffer))
        }
        
        // Process frame and pass to PoseLandmarker service
        connection.videoOrientation = videoOrientation
        
        // Notify subscribers about the new frame
        DispatchQueue.main.async { [weak self] in
            self?.onFrameCaptured(sampleBuffer: sampleBuffer, orientation: self?.videoOrientation ?? .portrait)
        }
    }
    
    private func onFrameCaptured(sampleBuffer: CMSampleBuffer, orientation: AVCaptureVideoOrientation) {
        // This is where you'll send the frame to your pose landmarker service
        // For now, we'll just set the frame for preview
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
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