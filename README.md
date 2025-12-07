# SmartGlasses

A project for streaming and processing images from smart glasses, consisting of a FastAPI backend and an iOS application.

## Project Overview

SmartGlasses is a system that enables:
- Streaming video from smart glasses or a camera to an iOS application
- Uploading and processing images via a Python API
- Secure storage of received images with unique identifiers
- AI-powered image analysis using OpenAI
- Text-to-speech feedback of image analysis results

## Components

### 1. Python API Backend

Located in the `/api` directory, the backend provides:
- FastAPI-based REST API for image uploads
- Base64 image decoding
- Secure file storage with UUID naming
- Integration with OpenAI for image analysis and explanation

### 2. iOS Application

Located in the `/ios` directory, the iOS app provides:
- Real-time MJPEG video streaming from the glasses
- SwiftUI interface for viewing the stream
- "Capture & Explain" functionality to capture frames and send to the API
- Text-to-speech feedback reading out AI analysis results

## Setup Instructions

### API Setup

1. Navigate to the API directory:
   ```
   cd api
   ```

2. Create and activate a virtual environment (already done):
   ```
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. Install dependencies:
   ```
   pip install fastapi uvicorn openai
   ```

4. Run the API server:
   ```
   uvicorn main:app --reload --host 0.0.0.0 --port 8000
   ```

### iOS App Setup

1. Open the Xcode project:
   ```
   open ios/SmartGlasses.xcodeproj
   ```

2. Configure the stream URL in `SmartGlassesApp.swift` if needed (currently set to `http://192.168.86.46:8081`)

3. Build and run the application on your iOS device or simulator

## API Endpoints

### POST /upload-image/

Uploads an image to the server.

**Request Body:**
```json
{
  "filename": "image.jpg",
  "data": "base64_encoded_image_data"
}
```

**Response:**
```json
{
  "message": "Image received and saved",
  "path": "received_images/uuid_image.jpg"
}
```

### POST /explain-image/

Uploads an image and returns AI-generated analysis of its contents.

**Request Body:**
```json
{
  "filename": "image.jpg",
  "data": "base64_encoded_image_data"
}
```

**Response:**
```json
{
  "message": "AI-generated description of the image content"
}
```

## Project Structure

```
SmartGlasses/
├── api/                      # Python API backend
│   ├── main.py               # FastAPI application
│   ├── image_payload.json    # Example payload for testing
│   ├── received_images/      # Directory for stored images
│   └── venv/                 # Python virtual environment
│
└── ios/                      # iOS application
    ├── SmartGlasses/         # App source code
    │   └── SmartGlassesApp.swift  # Main app file
    └── SmartGlasses.xcodeproj/    # Xcode project files
```

## Dependencies

### API Dependencies
- Python 3.12+
- FastAPI
- Uvicorn
- Pydantic
- OpenAI

### iOS Dependencies
- iOS 14.0+
- SwiftUI
- Combine
- AVFoundation (for text-to-speech)

## Development

- The API server must be running for the iOS app to upload images
- The MJPEG stream server (at the configured IP address) must be running for the iOS app to display the video feed
- An OpenAI API key must be configured for the image analysis feature to work

## License

[Your license information here]
