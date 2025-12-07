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
import Speech

import CocoaAsyncSocket

final class BeaconListener: NSObject, GCDAsyncUdpSocketDelegate {
    private let port: UInt16 = 19999
    private var sock: GCDAsyncUdpSocket!

    var onURL: ((URL) -> Void)?

    func start() {
        sock = GCDAsyncUdpSocket(delegate: self, delegateQueue: .main)
        try? sock.enableBroadcast(true)
        try? sock.bind(toPort: port)
        try? sock.beginReceiving()
    }

    func udpSocket(_ s: GCDAsyncUdpSocket, didReceive data: Data, fromAddress _: Data,
                   withFilterContext _: Any?) {
        print("Received beacon: \(String(data: data, encoding: .utf8) ?? "<binary>")")
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String:Any],
              let ip = dict["ip"] as? String,
              let port = dict["port"] as? Int,
              let path = dict["path"] as? String
        else { return }
        if let url = URL(string: "http://\(ip):\(port)\(path)") { onURL?(url) }
    }
}

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

final class Discovery: ObservableObject {
    let beacon = BeaconListener()
    @Published var lastURL: URL?

    func start() {
        beacon.onURL = { [weak self] url in
            DispatchQueue.main.async { self?.lastURL = url }
        }
        beacon.start()
    }
}

// MARK: - Speech Recognizer
final class SpeechRecognizer: ObservableObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    @Published var recognizedText = ""
    @Published var isRecording = false
    @Published var isProcessing = false

    var onQuestionDetected: ((String) -> Void)?

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                print("Speech authorization: \(status.rawValue)")
            }
        }
    }

    func startRecording() {
        guard !audioEngine.isRunning else { return }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognizedText = ""

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                DispatchQueue.main.async {
                    self.recognizedText = result.bestTranscription.formattedString

                    // Check if it's a question when final result
                    if result.isFinal {
                        self.checkForQuestion(self.recognizedText)
                    }
                }
            }

            if error != nil || result?.isFinal == true {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
                DispatchQueue.main.async {
                    self.isRecording = false
                }
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try? audioEngine.start()

        isRecording = true
    }

    func stopRecording() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        isRecording = false
    }

    private func checkForQuestion(_ text: String) {
        let lowercased = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it's a question (ends with ?, starts with question words, or contains question patterns)
        let questionWords = ["what", "where", "when", "who", "why", "how", "is", "are", "can", "could", "would", "should", "do", "does", "did"]
        let startsWithQuestion = questionWords.contains { lowercased.hasPrefix($0 + " ") }
        let endsWithQuestion = lowercased.hasSuffix("?")

        if startsWithQuestion || endsWithQuestion || lowercased.contains(" or ") {
            isProcessing = true
            onQuestionDetected?(text)
        }
    }
}

struct MJPEGStreamView: View {
    @StateObject private var streamer = MJPEGStreamer(urlString: "http://192.168.86.149:8081")
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @StateObject var d = Discovery()
    @Environment(\.openURL) var openURL

    var body: some View {
        ZStack {
            if let uiImage = streamer.image {
                Image(uiImage: uiImage).resizable().scaledToFit()
            } else {
                ProgressView("Connecting…")
            }
        }
        .onAppear {
            d.start()
            streamer.start()
            speechRecognizer.requestAuthorization()

            // Set up auto-capture when question is detected
            speechRecognizer.onQuestionDetected = { [weak speechRecognizer] question in
                captureAndSend(with: question)
                speechRecognizer?.stopRecording()
                // Clear text after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    speechRecognizer?.recognizedText = ""
                    speechRecognizer?.isProcessing = false
                }
            }
        }
        .onChange(of: d.lastURL) { if let u = $0 { print(u) } }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                // Show recognized text or processing state
                if speechRecognizer.isProcessing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                        Text("Processing: \(speechRecognizer.recognizedText)")
                            .font(.subheadline)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.7))
                    .foregroundStyle(.white)
                    .cornerRadius(8)
                    .padding(.horizontal)
                } else if !speechRecognizer.recognizedText.isEmpty {
                    Text(speechRecognizer.recognizedText)
                        .font(.subheadline)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.7))
                        .foregroundStyle(.white)
                        .cornerRadius(8)
                        .padding(.horizontal)
                }

                HStack(spacing: 16) {
                    // Voice button
                    Button {
                        if speechRecognizer.isRecording {
                            speechRecognizer.stopRecording()
                        } else {
                            speechRecognizer.startRecording()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "mic")
                            Text(speechRecognizer.isRecording ? "Listening..." : "Ask Question")
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(speechRecognizer.isRecording ? Color.red.opacity(0.8) : Color.black.opacity(0.55))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .disabled(speechRecognizer.isProcessing)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
        }
    }

    private func captureAndSend(with question: String) {
        guard let img = streamer.image else { return }
        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        uploadUIImage(img, filename: "frame-\(ts).jpg", question: question)
    }
}

func uploadUIImage(_ image: UIImage, filename: String, question: String? = nil) {
    print("> Uploading image with question \(String(describing: question))...\n")
    guard let url = URL(string: "http://192.168.86.38:8000/explain-image/") else { return }
    guard let imageData = image.jpegData(compressionQuality: 0.8) else { return }
    let base64String = imageData.base64EncodedString()

    var json: [String: String] = ["filename": filename, "data": base64String]
    if let question = question {
        json["question"] = question
    }

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

