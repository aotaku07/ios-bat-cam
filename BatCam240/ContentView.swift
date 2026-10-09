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
    @State private var baseZoom: CGFloat = 1.0

    var body: some View {
        ZStack {
            // カメラプレビュー & ピンチズームジェスチャー
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let target = baseZoom * value
                            camera.setZoom(factor: target)
                        }
                        .onEnded { _ in
                            baseZoom = camera.currentZoomFactor
                        }
                )
            
            // 録画中の極太赤枠（三脚や遠くからでも一目で分かる）
            if camera.isRecording {
                Rectangle()
                    .stroke(Color.red, lineWidth: 10)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack {
                // ─────────────────────────────────────────────
                // 上部ステータスHUD (超特大で視認性抜群)
                // ─────────────────────────────────────────────
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(camera.isRecording ? Color.red : (camera.isUploading ? Color.yellow : Color.green))
                            .frame(width: 18, height: 18)
                        
                        if camera.isRecording {
                            if camera.isAutoCountingDown {
                                Text("🔴 REC 録画中 (残り \(camera.remainingSeconds)秒)")
                                    .font(.system(size: 18, weight: .black))
                                    .foregroundColor(.red)
                            } else {
                                Text("🔴 REC 録画中...")
                                    .font(.system(size: 18, weight: .black))
                                    .foregroundColor(.red)
                            }
                        } else if camera.isUploading {
                            Text("⏳ 解析PCへ送信中...")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.yellow)
                        } else {
                            Text("🟢 待機中 (PCからの合図待ち)")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.green)
                        }
                        
                        Spacer()
                        
                        // バージョンバッジ
                        Text("v2.1")
                            .font(.system(size: 11, weight: .heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.yellow)
                            .foregroundColor(.black)
                            .cornerRadius(4)
                        
                        Button(action: { showSettings.toggle() }) {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 16))
                                .padding(8)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                    }
                    
                    // サブ情報バー
                    HStack {
                        Text("役割: \(cameraRole == "cam_side" ? "📐 側面カメラ" : "⚾ 正面カメラ")")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Text(camera.statusMessage)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                .padding(12)
                .background(Color.black.opacity(0.85))
                .cornerRadius(12)
                .frame(maxWidth: 600)
                .padding(.horizontal)
                .padding(.top, 4)

                Spacer()

                // ─────────────────────────────────────────────
                // 手動ズームコントロール (1x / 1.5x / 2x / 3x)
                // ─────────────────────────────────────────────
                HStack(spacing: 12) {
                    Text("🔍 ズーム:")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                    
                    ForEach([1.0, 1.5, 2.0, 3.0], id: \.self) { z in
                        Button(action: {
                            baseZoom = CGFloat(z)
                            camera.setZoom(factor: CGFloat(z))
                        }) {
                            Text(String(format: "%.1fx", z))
                                .font(.system(size: 13, weight: .heavy))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(abs(camera.currentZoomFactor - CGFloat(z)) < 0.1 ? Color.yellow : Color.black.opacity(0.6))
                                .foregroundColor(abs(camera.currentZoomFactor - CGFloat(z)) < 0.1 ? Color.black : Color.white)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color.black.opacity(0.75))
                .cornerRadius(20)
                .frame(maxWidth: 600)
                .padding(.bottom, 6)

                // ─────────────────────────────────────────────
                // 下部コントロールパネル
                // ─────────────────────────────────────────────
                VStack(spacing: 12) {
                    // カメラ役割の切り替え
                    HStack(spacing: 8) {
                        Button(action: {
                            cameraRole = "cam_side"
                            restartListening()
                        }) {
                            Text("📐 側面カメラ (cam_side)")
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
                            Text("⚾ 正面カメラ (cam_front)")
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
                                Text("指示PC IP:")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .frame(width: 85, alignment: .leading)
                                TextField("192.168.0.112", text: $controllerIP)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .font(.caption)
                            }

                            HStack {
                                Text("解析PC IP:")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .frame(width: 85, alignment: .leading)
                                TextField("空欄なら指示PCへ送信", text: $analysisIP)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .font(.caption)
                            }

                            Toggle(isOn: $remoteEnabled) {
                                Text("PC遠隔トリガーを受信 (常時スタンバイ)")
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
                            camera.startRecording(
                                autoDuration: 0,
                                controllerIP: controllerIP,
                                analysisIP: analysisIP,
                                cameraRole: cameraRole
                            )
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
                .background(Color.black.opacity(0.85))
                .cornerRadius(14)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
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
// 240fps カメラマネージャー & 遠隔同期
// ─────────────────────────────────────────────
class Camera240Manager: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    
    private var currentControllerIP: String = ""
    private var currentAnalysisIP: String = ""
    private var currentCameraRole: String = "cam_side"
    
    private var isListening: Bool = false
    private var listeningTask: URLSessionDataTask?
    private var countdownTimer: Timer?
    
    @Published var isRecording = false
    @Published var isUploading = false
    @Published var isAutoCountingDown = false
    @Published var remainingSeconds = 0
    @Published var currentZoomFactor: CGFloat = 1.0
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
    // ズーム設定
    // ─────────────────────────────────────────────
    func setZoom(factor: CGFloat) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        do {
            try device.lockForConfiguration()
            let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 5.0)
            let clamped = max(1.0, min(factor, maxZoom))
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            DispatchQueue.main.async {
                self.currentZoomFactor = clamped
            }
        } catch {
            print("Zoom error:", error)
        }
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
                
                // duration を安全にパース (NSNumber, Double, String どの型でも対応)
                var duration: Double = 0.0
                if let num = json["duration"] as? NSNumber {
                    duration = num.doubleValue
                } else if let d = json["duration"] as? Double {
                    duration = d
                } else if let s = json["duration"] as? String, let d = Double(s) {
                    duration = d
                }
                
                DispatchQueue.main.async {
                    if action == "START" {
                        if !self.isRecording {
                            self.startRecording(
                                autoDuration: duration,
                                controllerIP: self.currentControllerIP,
                                analysisIP: self.currentAnalysisIP,
                                cameraRole: self.currentCameraRole
                            )
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
    // 録画の開始・停止 (カウントダウン自動停止付き)
    // ─────────────────────────────────────────────
    func startRecording(autoDuration: Double = 0, controllerIP: String = "", analysisIP: String = "", cameraRole: String = "") {
        guard !isRecording else { return }
        if !controllerIP.isEmpty { self.currentControllerIP = controllerIP }
        if !analysisIP.isEmpty { self.currentAnalysisIP = analysisIP }
        if !cameraRole.isEmpty { self.currentCameraRole = cameraRole }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("swing_240fps.mp4")
        try? FileManager.default.removeItem(at: tempURL)
        movieOutput.startRecording(to: tempURL, recordingDelegate: self)
        
        isRecording = true
        statusMessage = "🔴 240fps 録画中..."
        
        // 自動停止タイマー (画面カウントダウン表示 & 時間切れで確実停止)
        countdownTimer?.invalidate()
        if autoDuration > 0 {
            isAutoCountingDown = true
            remainingSeconds = Int(ceil(autoDuration))
            countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
                guard let self = self else { return }
                self.remainingSeconds -= 1
                if self.remainingSeconds <= 0 {
                    t.invalidate()
                    self.isAutoCountingDown = false
                    if self.isRecording {
                        print("[AutoStopTimer] Countdown finished. Stopping recording automatically...")
                        self.stopRecordingAndUpload(
                            controllerIP: self.currentControllerIP,
                            analysisIP: self.currentAnalysisIP,
                            cameraRole: self.currentCameraRole
                        )
                    }
                }
            }
        } else {
            isAutoCountingDown = false
        }
    }
    
    func stopRecordingAndUpload(controllerIP: String, analysisIP: String, cameraRole: String) {
        guard isRecording else { return }
        countdownTimer?.invalidate()
        isAutoCountingDown = false
        
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
        
        statusMessage = "⏳ 送信中 (-> \(cleanIP):8080)..."
        
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
                    self.statusMessage = "✅ 送信完了！(\(self.currentCameraRole))"
                } else if let error = error {
                    self.statusMessage = "❌ 送信失敗(\(cleanIP)): \(error.localizedDescription)"
                } else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    self.statusMessage = "❌ 送信失敗: HTTP \(code) (\(cleanIP))"
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
