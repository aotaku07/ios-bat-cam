import SwiftUI
import AVFoundation
import UIKit

struct ContentView: View {
    @StateObject private var camera = Camera240Manager()
    @State private var serverIP: String = "192.168.1.50"
    
    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
            
            VStack {
                HStack {
                    Circle()
                        .fill(camera.isRecording ? Color.red : (camera.isUploading ? Color.yellow : Color.green))
                        .frame(width: 14, height: 14)
                    Text(camera.statusMessage)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(10)
                .background(Color.black.opacity(0.75))
                .cornerRadius(8)
                .padding()
                
                Spacer()
                
                VStack(spacing: 12) {
                    HStack {
                        Text("PCのIP:").foregroundColor(.white).font(.caption)
                        TextField("PC IPアドレス", text: $serverIP)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 160)
                    }
                    
                    Button(action: {
                        if camera.isRecording {
                            camera.stopRecordingAndUpload(serverIP: serverIP)
                        } else {
                            camera.startRecording()
                        }
                    }) {
                        Text(camera.isRecording ? "⏹ 録画停止 & PCへ自動送信" : "🔴 240fps 録画スタート")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(camera.isRecording ? Color.red : Color.blue)
                            .cornerRadius(12)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.7))
            }
        }
        .onAppear {
            camera.setup240fpsCamera()
        }
    }
}

class Camera240Manager: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var targetServerIP: String = ""
    
    @Published var isRecording = false
    @Published var isUploading = false
    @Published var statusMessage = "待機中 (240fps スタンバイ)"
    
    func setup240fpsCamera() {
        session.beginConfiguration()
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            statusMessage = "カメラ初期化エラー"
            return
        }
        
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        
        var bestFormat: AVCaptureDevice.Format?
        for format in device.formats {
            for range in format.videoSupportedFrameRateRanges {
                if range.maxFrameRate >= 240.0 {
                    bestFormat = format
                    break
                }
            }
            if bestFormat != nil { break }
        }
        
        if let format = bestFormat {
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 240)
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 240)
                device.unlockForConfiguration()
                statusMessage = "✅ 240fps ロック成功"
            } catch {
                statusMessage = "FPS設定失敗"
            }
        } else {
            statusMessage = "⚠️ 240fps非対応デバイス"
        }
        
        session.commitConfiguration()
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }
    
    func startRecording() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("swing_240fps.mp4")
        try? FileManager.default.removeItem(at: tempURL)
        movieOutput.startRecording(to: tempURL, recordingDelegate: self)
        isRecording = true
        statusMessage = "🔴 240fps 録画中..."
    }
    
    func stopRecordingAndUpload(serverIP: String) {
        self.targetServerIP = serverIP
        movieOutput.stopRecording()
        isRecording = false
        isUploading = true
        statusMessage = "⏳ 録画停止・PCへ送信中..."
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        guard error == nil else {
            statusMessage = "録画エラー"
            isUploading = false
            return
        }
        uploadVideoToPC(fileURL: outputFileURL)
    }
    
    private func uploadVideoToPC(fileURL: URL) {
        guard let url = URL(string: "http://\(targetServerIP):8080/api/analyze_video") else {
            statusMessage = "IPアドレス無効"
            isUploading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.shared.uploadTask(with: request, fromFile: fileURL) { _, response, error in
            DispatchQueue.main.async {
                self.isUploading = false
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                    self.statusMessage = "✅ PCへ転送完了 (AI解析開始)"
                } else {
                    self.statusMessage = "❌ 転送失敗 (PCサーバー確認)"
                }
            }
        }
        task.resume()
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        DispatchQueue.main.async { layer.frame = view.bounds }
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
