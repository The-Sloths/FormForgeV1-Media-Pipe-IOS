//
//  Line.swift
//  FormForgeV1
//
//  Created by Pawel Kowalewski on 06/05/2025.
//


import SwiftUI
import MediaPipeTasksVision

struct Line {
    let from: CGPoint
    let to: CGPoint
}

struct PoseOverlay {
    let dots: [CGPoint]
    let lines: [Line]
}

struct PoseOverlayView: View {
    var overlays: [PoseOverlay]
    var imageSize: CGSize
    var contentMode: ContentMode
    
    init(overlays: [PoseOverlay], imageSize: CGSize, contentMode: ContentMode = .fit) {
        self.overlays = overlays
        self.imageSize = imageSize
        self.contentMode = contentMode
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<overlays.count, id: \.self) { index in
                    PoseOverlayShape(overlay: overlays[index], 
                                    imageSize: imageSize, 
                                    viewSize: geometry.size, 
                                    contentMode: contentMode)
                        .stroke(Color.green, lineWidth: 2)
                    
                    ForEach(0..<overlays[index].dots.count, id: \.self) { dotIndex in
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                            .position(
                                transformPoint(
                                    overlays[index].dots[dotIndex],
                                    fromImageSize: imageSize,
                                    toViewSize: geometry.size,
                                    contentMode: contentMode
                                )
                            )
                    }
                }
            }
        }
    }
    
    private func transformPoint(_ point: CGPoint, fromImageSize imageSize: CGSize, toViewSize viewSize: CGSize, contentMode: ContentMode) -> CGPoint {
        let scale: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat
        
        if contentMode == .fit {
            let scaleX = viewSize.width / imageSize.width
            let scaleY = viewSize.height / imageSize.height
            scale = min(scaleX, scaleY)
            
            let scaledW = imageSize.width * scale
            let scaledH = imageSize.height * scale
            offsetX = (viewSize.width - scaledW) / 2
            offsetY = (viewSize.height - scaledH) / 2
        } else { // .fill
            let scaleX = viewSize.width / imageSize.width
            let scaleY = viewSize.height / imageSize.height
            scale = max(scaleX, scaleY)
            
            let scaledW = imageSize.width * scale
            let scaledH = imageSize.height * scale
            offsetX = (viewSize.width - scaledW) / 2
            offsetY = (viewSize.height - scaledH) / 2
        }
        
        return CGPoint(
            x: point.x * imageSize.width * scale + offsetX,
            y: point.y * imageSize.height * scale + offsetY
        )
    }
}

struct PoseOverlayShape: Shape {
    var overlay: PoseOverlay
    var imageSize: CGSize
    var viewSize: CGSize
    var contentMode: ContentMode
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        for line in overlay.lines {
            let start = transformPoint(line.from, 
                                      fromImageSize: imageSize, 
                                      toViewSize: viewSize, 
                                      contentMode: contentMode)
            let end = transformPoint(line.to, 
                                    fromImageSize: imageSize, 
                                    toViewSize: viewSize, 
                                    contentMode: contentMode)
            
            path.move(to: start)
            path.addLine(to: end)
        }
        
        return path
    }
    
    private func transformPoint(_ point: CGPoint, fromImageSize imageSize: CGSize, toViewSize viewSize: CGSize, contentMode: ContentMode) -> CGPoint {
        let scale: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat
        
        if contentMode == .fit {
            let scaleX = viewSize.width / imageSize.width
            let scaleY = viewSize.height / imageSize.height
            scale = min(scaleX, scaleY)
            
            let scaledW = imageSize.width * scale
            let scaledH = imageSize.height * scale
            offsetX = (viewSize.width - scaledW) / 2
            offsetY = (viewSize.height - scaledH) / 2
        } else { // .fill
            let scaleX = viewSize.width / imageSize.width
            let scaleY = viewSize.height / imageSize.height
            scale = max(scaleX, scaleY)
            
            let scaledW = imageSize.width * scale
            let scaledH = imageSize.height * scale
            offsetX = (viewSize.width - scaledW) / 2
            offsetY = (viewSize.height - scaledH) / 2
        }
        
        return CGPoint(
            x: point.x * imageSize.width * scale + offsetX,
            y: point.y * imageSize.height * scale + offsetY
        )
    }
}

// Helper to generate PoseOverlays from PoseLandmarkerResult
extension PoseOverlayView {
    static func createPoseOverlays(from landmarks: [[NormalizedLandmark]], imageSize: CGSize, orientation: UIImage.Orientation = .up) -> [PoseOverlay] {
        var poseOverlays: [PoseOverlay] = []
        
        for poseLandmarks in landmarks {
            var transformedPoseLandmarks: [CGPoint]
            
            switch orientation {
            case .left:
                transformedPoseLandmarks = poseLandmarks.map { CGPoint(x: CGFloat($0.y), y: 1 - CGFloat($0.x)) }
            case .right:
                transformedPoseLandmarks = poseLandmarks.map { CGPoint(x: 1 - CGFloat($0.y), y: CGFloat($0.x)) }
            default:
                transformedPoseLandmarks = poseLandmarks.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
            }
            
            let dots = transformedPoseLandmarks
            let lines = PoseLandmarker.poseLandmarks.map { connection in
                Line(
                    from: transformedPoseLandmarks[Int(connection.start)],
                    to: transformedPoseLandmarks[Int(connection.end)]
                )
            }
            
            poseOverlays.append(PoseOverlay(dots: dots, lines: lines))
        }
        
        return poseOverlays
    }
}