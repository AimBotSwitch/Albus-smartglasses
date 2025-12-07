//
//  SmartGlassesApp.swift
//  SmartGlasses
//
//  Created by Xiang Xiao on 7/6/25.
//

import SwiftUI
import UIKit
import Combine

import AVFoundation

private let tts = AVSpeechSynthesizer()

private func speak(_ text: String, lang: String = "en-US") {
    // Optional: ensure playback even in silent mode
    try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
    try? AVAudioSession.sharedInstance().setActive(true)

    let u = AVSpeechUtterance(string: text)
    u.voice = AVSpeechSynthesisVoice(language: lang)
    u.rate  = AVSpeechUtteranceDefaultSpeechRate
    tts.speak(u)
}

struct MJPEGStreamView: View {
    @StateObject private var streamer = MJPEGStreamer(urlString: "http://192.168.86.46:8081")

    var body: some View {
        ZStack {
            if let uiImage = streamer.image {
                Image(uiImage: uiImage).resizable().scaledToFit()
            } else {
                ProgressView("Connecting…")
            }
        }
        .onAppear { streamer.start() }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    captureAndSend()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.circle.fill")
                        Text("Capture & Send")
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Color.black.opacity(0.55))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
        }
    }

    private func captureAndSend() {
        guard let img = streamer.image else { return }
        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        uploadUIImage(img, filename: "frame-\(ts).jpg")
    }
}

func uploadUIImage(_ image: UIImage, filename: String) {
    guard let url = URL(string: "http://localhost:8000/explain-image/") else { return }
    guard let imageData = image.jpegData(compressionQuality: 0.8) else { return }
    let base64String = imageData.base64EncodedString()
    let json: [String: String] = ["filename": filename, "data": base64String]
    guard let httpBody = try? JSONSerialization.data(withJSONObject: json) else { return }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = httpBody
    
    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error { print("❌ Error:", error); return }
        guard let data = data else { return }

        // Try to get message from { "message": "..."} or { "response": { "message": "..." } }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let message =
                (obj["message"] as? String) ??
                ((obj["response"] as? [String: Any])?["message"] as? String)

            if let message = message {
                DispatchQueue.main.async { speak(message) }
                print("🗣️ Spoke message: \(message)")
            } else {
                print("ℹ️ No 'message' field found:", obj)
            }
        }
    }.resume()
}


// MARK: – MJPEG Streamer
class MJPEGStreamer: NSObject, ObservableObject, URLSessionDataDelegate {
    @Published var image: UIImage?
    private var buffer = Data()
    private let urlString: String
    private let session: URLSession

    init(urlString: String) {
        self.urlString = urlString
        // Create a session that uses this object as its delegate
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = TimeInterval(INT_MAX)
        self.session = URLSession(configuration: cfg,
                                  delegate: nil,
                                  delegateQueue: .main)
        super.init()
    }

    func start() {
        guard let url = URL(string: urlString) else { return }
        // Recreate the session with delegate since init(delegate:) happens before super.init()
        let cfg = session.configuration
        let taskSession = URLSession(configuration: cfg,
                                     delegate: self,
                                     delegateQueue: .main)
        taskSession.dataTask(with: url).resume()
    }

    // Called as chunks arrive
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        buffer.append(data)

        // Extract complete JPEG frames
        while true {
            guard let start = buffer.range(of: Data([0xFF, 0xD8])),
                  let end   = buffer.range(of: Data([0xFF, 0xD9]),
                                            in: start.lowerBound..<buffer.endIndex)
            else {
                break
            }

            let frameData = buffer[start.lowerBound...end.upperBound-1]
            buffer.removeSubrange(0...end.upperBound-1)

            if let uiImage = UIImage(data: frameData) {
                self.image = uiImage
            }
        }
    }
}

// MARK: – App Entry Point
@main
struct SmartGlassesApp: App {
    var body: some Scene {
        WindowGroup {
            MJPEGStreamView()
        }
    }
}

