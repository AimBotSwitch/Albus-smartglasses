//
//  SmartGlassesApp.swift
//  SmartGlasses
//
//  Created by Xiang Xiao on 7/6/25.
//

import SwiftUI
import Combine
import UIKit

// MARK: – SwiftUI View
struct ContentView: View {
    @StateObject private var streamer = MJPEGStreamer(urlString: "http://192.168.86.44:8081")

    var body: some View {
        Group {
            if let uiImage = streamer.image {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView("Connecting…")
            }
        }
        .onAppear { streamer.start() }
    }
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
            ContentView()
        }
    }
}

