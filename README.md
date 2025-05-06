# FormForgeV1 Media Pipe

An iOS SwiftUI application that implements real-time body pose landmark detection and analysis using Google's MediaPipe framework.

## Features

- Real-time pose detection using device camera
- Support for image and video processing from media library
- Three model options (lite, full, heavy) with different performance/accuracy tradeoffs
- Adjustable detection parameters
- GPU/CPU processing selection
- Visual pose landmark overlays

## Requirements

- iOS 15.0+
- Xcode 13.0+
- CocoaPods 1.11.0+
- Swift 5.5+

## Installation

### Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPOSITORY.git
cd YOUR_REPOSITORY
```

### Install Dependencies

This project uses CocoaPods to manage dependencies. If you don't have CocoaPods installed, you can install it with:

```bash
sudo gem install cocoapods
```

Then, install the dependencies:

```bash
pod install
```

⚠️ Important: After running `pod install`, always open the project using the generated `.xcworkspace` file, not the `.xcodeproj` file.

### Download Models

The app requires pose detection models to work. Run the included script to download them:

```bash
chmod +x download_models.sh
./download_models.sh
```

This will download three model variants (lite, full, and heavy) and place them in the appropriate directory.

## Running the App

1. Open the `.xcworkspace` file in Xcode
2. Select your target device (physical iOS device recommended for better performance)
3. Build and run the application (⌘+R)

## Usage

The app has two main tabs:

1. **Camera View**: Uses the device camera for real-time pose detection
2. **Media Library**: Import images or videos from your device for pose analysis

### Adjusting Settings

Tap the settings panel at the bottom of the screen to:
- Change the model (lite/full/heavy)
- Switch between CPU and GPU processing
- Adjust the number of poses to detect
- Modify confidence thresholds for detection, presence, and tracking

## Troubleshooting

### Common Issues

- **Camera Access Denied**: Make sure to grant camera permissions when prompted or enable them in Settings → Privacy → Camera
- **Slow Performance**: Try switching to the 'lite' model or using GPU acceleration if available
- **CocoaPods Installation Errors**: Make sure you have the latest version of CocoaPods and try running `pod repo update` before `pod install`
- **"Model path not found" Error**: Re-run the download_models.sh script and ensure the models are properly added to the project

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Google MediaPipe](https://developers.google.com/mediapipe) for the underlying pose detection technology
- [MediaPipeTasksVision](https://developers.google.com/mediapipe/solutions/vision/pose_landmarker) for the iOS framework

## Note to Contributors

Feel free to submit issues or pull requests for improvements!
