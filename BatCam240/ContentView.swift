import SwiftUI
import AVFoundation
import UIKit

struct ContentView: View {
    @StateObject private var camera = Camera240Manager()
    
    // 設定の永続化
    @AppStorage("controllerIP") private var controllerIP: String = "192.168.0.112"
    @AppStorage("analysisIP") private var analysisIP: String = ""
    @AppStorage("cameraRole") private var cameraRole: String = "cam_side" // "cam_side" or "cam_front"
    @AppStorage("remoteEnabled") private var remoteEnabled: Bool = true
    
    @State private var showSettings: Bool = false

    var body: some View {
        ZStack {
            // カメラプレビュー
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
            
            // 録画中の赤枠アニメーション
            if camera.isRecording {
                Rectangle()
                    .stroke(Color.red, lineWidth: 6)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack {
                // 上部ステータスバー
                HStack(spacing: 8) {
                    Circle()
                        .fill(camera.isRecording ? Color.red : (camera.isUploading ? Color.yellow : Color.green))
                        .frame(width: 14, height: 14)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(camera.statusMessage)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            Text("v2.0")
                                .font(.system(size: 10, weight: .heavy))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.yellow)
                                .foregroundColor(.black)
                                .cornerRadius(4)
                        }
                        
                        Text("カメラ役割: \(cameraRole == "cam_side" ? "📐 側面 (cam_side)" : "⚾ 正面 (cam_front)")")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                }
                .padding(10)
                .background(Color.black.opacity(0.75))
                .cornerRadius(10)
                .frame(maxWidth: 600)
                .padding(.horizontal)
                .padding(.top, 4)

                Spacer()

                // 下部コントロールパネル
                VStack(spacing: 12) {
                    // カメラ役割の簡単切り替え
                    HStack(spacing: 8) {
                        Button(action: {
                            cameraRole = "cam_side"
                            restartListening()
                        }) {
                            Text("📐 側面カメラ")
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(cameraRole == "cam_side" ? Color.blue : Color.white.opacity(0.15))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }

                        Button(action: {
                            cameraRole = "cam_front"
                            restartListening()
                        }) {
                            Text("⚾ 正面カメラ")
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(cameraRole == "cam_front" ? Color.blue : Color.white.opacity(0.15))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }

                    // 設定詳細アコーディオン
                    if showSettings {
                        VStack(spacing: 8) {
                            HStack {
                                Text("指示PC (現在):")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .frame(width: 95, alignment: .leading)
                                TextField("192.168.0.112", text: $controllerIP)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .font(.caption)
                            }

                            HStack {
                                Text("解析PC (別PC):")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .frame(width: 95, alignment: .leading)
                                TextField("空欄なら指示PCへ", text: $analysisIP)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .font(.caption)
                            }

                            Toggle(isOn: $remoteEnabled) {
                                Text("PC遠隔トリガーを自動受信")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                            .onChange(of: remoteEnabled) { _ in
                                restartListening()
                            }
                        }
                        .padding(10)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                    }

                    // 手動録画ボタン
                    Button(action: {
                        if camera.isRecording {
                            camera.stopRecordingAndUpload(
                                controllerIP: controllerIP,
                                analysisIP: analysisIP,
                                cameraRole: cameraRole
                            )
                        } else {
                            camera.startRecording()
                        }
                    }) {
                        HStack {
                            Image(systemName: camera.isRecording ? "stop.circle.fill" : "record.circle")
                            Text(camera.isRecording ? "⏹ 録画停止 & 解析PCへ送信" : "🔴 手動 240fps 録画スタート")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(camera.isRecording ? Color.red : Color.blue)
                        .cornerRadius(12)
                    }
                }
                .padding()
                .frame(maxWidth: 600)
                .background(Color.black.opacity(0.75))
                .cornerRadius(14)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            // スリープ（画面自動消灯）を無効化
            UIApplication.shared.isIdleTimerDisabled = true
            camera.setup240fpsCamera()
            restartListening()
        }
    }

    private func restartListening() {
        if remoteEnabled {
            camera.startListening(
                controllerIP: controllerIP,
                analysisIP: analysisIP,
                cameraRole: cameraRole
            )
        } else {
            camera.stopListening()
        }
    }
}

// ─────────────────────────────────────────────
// 240fps カメラマネージャー & 遠隔トリガー
// ─────────────────────────────────────────────
class Camera240Manager: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    
    private var currentControllerIP: String = ""
    private var currentAnalysisIP: String = ""
    private var currentCameraRole: String = "cam_side"
    
    private var isListening: Bool = false
    private var listeningTask: URLSessionDataTask?
    
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
        
        var targetFPS: Int = 30
        var bestFormat: AVCaptureDevice.Format?
        
        // デバイスの最高フレームレート (240fps -> 120fps -> 60fps) を自動探索
        for desiredFPS in [240, 120, 60] {
            for format in device.formats {
                for range in format.videoSupportedFrameRateRanges {
                    if range.maxFrameRate >= Double(desiredFPS) {
                        bestFormat = format
                        targetFPS = desiredFPS
                        break
                    }
                }
                if bestFormat != nil { break }
            }
            if bestFormat != nil { break }
        }
        
        if let format = bestFormat {
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(targetFPS))
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Int32(targetFPS))
                device.unlockForConfiguration()
                statusMessage = "✅ \(targetFPS)fps ロック成功 (PC待機中)"
            } catch {
                statusMessage = "FPS設定失敗 (通常モード)"
            }
        } else {
            statusMessage = "✅ 標準カメラで起動 (PC待機中)"
        }
        
        session.commitConfiguration()
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }
    
    // ─────────────────────────────────────────────
    // PC遠隔トリガー待機 (Long Polling)
    // ─────────────────────────────────────────────
    func startListening(controllerIP: String, analysisIP: String, cameraRole: String) {
        self.currentControllerIP = controllerIP
        self.currentAnalysisIP = analysisIP
        self.currentCameraRole = cameraRole
        self.isListening = true
        pollNextCommand()
    }
    
    func stopListening() {
        self.isListening = false
        listeningTask?.cancel()
        listeningTask = nil
    }
    
    private func pollNextCommand() {
        guard isListening else { return }
        
        let cleanIP = sanitizeIP(currentControllerIP)
        guard let url = URL(string: "http://\(cleanIP):8080/api/wait_command?camera=\(currentCameraRole)") else {
            DispatchQueue.main.async {
                self.statusMessage = "❌ 指示PC IP無効: \(cleanIP)"
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        
        listeningTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, self.isListening else { return }
            
            if let error = error as NSError?, error.code == NSURLErrorCancelled {
                return
            }
            
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let action = json["action"] as? String {
                
                let duration = json["duration"] as? Double ?? 0.0
                
                DispatchQueue.main.async {
                    if action == "START" {
                        if !self.isRecording {
                            self.startRecording()
                            if duration > 0 {
                                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                                    if self.isRecording {
                                        self.stopRecordingAndUpload(
                                            controllerIP: self.currentControllerIP,
                                            analysisIP: self.currentAnalysisIP,
                                            cameraRole: self.currentCameraRole
                                        )
                                    }
                                }
                            }
                        }
                    } else if action == "STOP" {
                        if self.isRecording {
                            self.stopRecordingAndUpload(
                                controllerIP: self.currentControllerIP,
                                analysisIP: self.currentAnalysisIP,
                                cameraRole: self.currentCameraRole
                            )
                        }
                    }
                }
            }
            
            // アップロード中以外の時は、すぐに次回のコマンド待ちを再開
            if !self.isUploading {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                    self.pollNextCommand()
                }
            }
        }
        listeningTask?.resume()
    }
    
    // ─────────────────────────────────────────────
    // 録画の開始・停止
    // ─────────────────────────────────────────────
    func startRecording() {
        guard !isRecording else { return }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("swing_240fps.mp4")
        try? FileManager.default.removeItem(at: tempURL)
        movieOutput.startRecording(to: tempURL, recordingDelegate: self)
        isRecording = true
        statusMessage = "🔴 240fps 録画中..."
    }
    
    func stopRecordingAndUpload(controllerIP: String, analysisIP: String, cameraRole: String) {
        guard isRecording else { return }
        self.currentControllerIP = controllerIP
        self.currentAnalysisIP = analysisIP
        self.currentCameraRole = cameraRole
        
        movieOutput.stopRecording()
        isRecording = false
        isUploading = true
        statusMessage = "⏳ 録画停止・解析PCへ送信中..."
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        guard error == nil else {
            statusMessage = "録画エラー"
            isUploading = false
            pollNextCommand()
            return
        }
        uploadVideo(fileURL: outputFileURL)
    }
    
    // ─────────────────────────────────────────────
    // 解析PCへ動画アップロード
    // ─────────────────────────────────────────────
    private func uploadVideo(fileURL: URL) {
        // 解析PCのIPが空なら、指示PCのIPへ送る
        let targetRawIP = currentAnalysisIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? currentControllerIP
            : currentAnalysisIP
        
        let cleanIP = sanitizeIP(targetRawIP)
        guard let url = URL(string: "http://\(cleanIP):8080/api/analyze_video?camera=\(currentCameraRole)") else {
            statusMessage = "❌ 解析PC IP無効: \(cleanIP)"
            isUploading = false
            pollNextCommand()
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)
        
        let task = session.uploadTask(with: request, fromFile: fileURL) { [weak self] _, response, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isUploading = false
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                    self.statusMessage = "✅ 送信完了！(次回撮影 待機中)"
                } else if let error = error {
                    self.statusMessage = "❌ 送信失敗: \(error.localizedDescription)"
                } else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    self.statusMessage = "❌ 送信失敗: HTTP \(code)"
                }
                
                // 送信完了後、再びPC待機ループに戻る
                self.pollNextCommand()
            }
        }
        task.resume()
    }
    
    private func sanitizeIP(_ ip: String) -> String {
        return ip.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: ":8080", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

// ─────────────────────────────────────────────
// カメラプレビュー
// ─────────────────────────────────────────────
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
