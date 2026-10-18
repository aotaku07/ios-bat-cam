import SwiftUI
import AVFoundation
import UIKit
import CoreMotion
import Accelerate

struct ContentView: View {
    @StateObject private var camera = Camera240Manager()
    @StateObject private var chirpDetector = ChirpAudioDetector()
    
    // 設定の永続化
    @AppStorage("controllerIP") private var controllerIP: String = "192.168.0.112"
    @AppStorage("analysisIP") private var analysisIP: String = ""
    @AppStorage("cameraRole") private var cameraRole: String = "cam_side_right" // "cam_front", "cam_side_right", "cam_side_left"
    @AppStorage("rotationAngle") private var rotationAngle: Int = 90 // デフォルト90度回転で左倒れ解消
    @AppStorage("remoteEnabled") private var remoteEnabled: Bool = true
    @AppStorage("shutterSpeedDenominator") private var shutterSpeedDenominator: Double = 0 // 0 = Auto, 1000...2000 = Manual (1/x sec)
    @AppStorage("aspectRatioMode") private var aspectRatioMode: String = "16:9" // "16:9", "16:8", "2.35:1"
    @AppStorage("chirpDetectionEnabled") private var chirpDetectionEnabled: Bool = false
    @AppStorage("chirpThreshold") private var chirpThreshold: Double = 0.18 // デフォルト0.35から0.18へ引き下げ（遠距離・騒音対応）
    @AppStorage("cameraPowerMode") private var cameraPowerMode: String = "auto" // "auto", "manual_on", "manual_off"
    
    @State private var showSettings: Bool = false
    @State private var baseZoom: CGFloat = 1.0

    private func roleDisplayName(_ role: String) -> String {
        switch role {
        case "cam_front": return "⚾ 正面カメラ (Front)"
        case "cam_side_right": return "📐 右打席用 側面 (Right)"
        case "cam_side_left": return "📐 左打席用 側面 (Left)"
        default: return "📐 側面カメラ"
        }
    }

    var body: some View {
        ZStack {
            // カメラプレビュー & ピンチズームジェスチャー (カメラ起動時のみ表示)
            if camera.isCameraRunning {
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
            } else {
                // カメラ省電力スリープ表示（キオスクのready待機時）
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 14) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 54))
                            .foregroundColor(.gray)
                        Text("💤 カメラ待機中 (省電力モード)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        if cameraPowerMode == "auto" {
                            Text("キオスクがプレビュー画面（Ready）に遷移すると\n自動でカメラが起動します")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("カメラは強制OFFモードに設定されています")
                                .font(.system(size: 13))
                                .foregroundColor(.red.opacity(0.8))
                        }
                    }
                    .padding()
                }
            }
            
            // 録画中の極太赤枠（三脚や遠くからでも一目で分かる）
            if camera.isRecording {
                Rectangle()
                    .stroke(Color.red, lineWidth: 10)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // 撮影画角・比率調整マスク (上下余計なスペースを遮蔽し左右両打席に集中)
            if aspectRatioMode != "16:9" {
                GeometryReader { geo in
                    let maskH = (aspectRatioMode == "2.35:1") ? geo.size.height * 0.16 : geo.size.height * 0.08
                    VStack(spacing: 0) {
                        ZStack(alignment: .bottom) {
                            Color.black.opacity(0.60)
                            Rectangle().fill(Color.yellow.opacity(0.85)).frame(height: 1.5)
                        }
                        .frame(height: maskH)
                        
                        Spacer()
                        
                        ZStack(alignment: .top) {
                            Color.black.opacity(0.60)
                            Rectangle().fill(Color.yellow.opacity(0.85)).frame(height: 1.5)
                        }
                        .frame(height: maskH)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }
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
                        Text("v2.7")
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
                        Text("役割: \(roleDisplayName(cameraRole))")
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

                // ─────────────────────────────────────────────
                // チャープ音検出コントロールバー (ON/OFF & 検出回数表示)
                // ─────────────────────────────────────────────
                HStack(spacing: 8) {
                    // ON/OFF 切り替えボタン
                    Button(action: {
                        chirpDetectionEnabled.toggle()
                        chirpDetector.detectionThreshold = Float(chirpThreshold)
                        if chirpDetectionEnabled {
                            chirpDetector.startDetection()
                        } else {
                            chirpDetector.stopDetection()
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: chirpDetectionEnabled ? "mic.fill" : "mic.slash.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(chirpDetectionEnabled ? "🔊 ON" : "🔇 OFF")
                                .font(.system(size: 11, weight: .heavy))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(chirpDetectionEnabled ? Color.green : Color.gray.opacity(0.5))
                        .foregroundColor(chirpDetectionEnabled ? .black : .white)
                        .cornerRadius(7)
                    }

                    // 検出回数バッジ (オン〜オフまでの累計回数)
                    HStack(spacing: 4) {
                        Text("検出:")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                        Text("\(chirpDetector.chirpCount)回")
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(chirpDetector.chirpCount > 0 ? .yellow : .white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(7)

                    // ★ ピークスコア & 閾値表示（現場での音圧確認用）
                    HStack(spacing: 3) {
                        Text("閾値:\(String(format: "%.2f", chirpThreshold))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.cyan)
                        Text("(Peak:\(String(format: "%.2f", chirpDetector.lastPeakCorrelation)))")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(chirpDetector.lastPeakCorrelation >= Float(chirpThreshold) ? .yellow : .gray)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(7)

                    // カウントクリアボタン
                    if chirpDetector.chirpCount > 0 {
                        Button(action: {
                            chirpDetector.resetCount()
                        }) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(5)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.80))
                .cornerRadius(10)
                .frame(maxWidth: 600)
                .padding(.horizontal)
                .padding(.top, 2)

                // ─────────────────────────────────────────────
                // ★ チャープ音検出時の特大ポップアップバナー
                // ─────────────────────────────────────────────
                if chirpDetector.isRecentlyDetected {
                    HStack(spacing: 12) {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 26))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("⚡ チャープ同期音 (2kHz-5kHz) を検出！ (スコア: \(String(format: "%.2f", chirpDetector.lastPeakCorrelation)))")
                                .font(.system(size: 15, weight: .black))
                                .foregroundColor(.yellow)
                            Text("今回セッション累計: \(chirpDetector.chirpCount) 回検出")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.92))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.yellow, lineWidth: 2)
                    )
                    .shadow(color: .yellow.opacity(0.6), radius: 10)
                    .padding(.top, 6)
                    .transition(.scale.combined(with: .opacity))
                }

                Spacer()

                // ─────────────────────────────────────────────
                // 手動ズームコントロール & 映像向き回転コントロール
                // ─────────────────────────────────────────────
                VStack(spacing: 6) {
                    // ズームバー
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
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
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

                    // 向き・回転バー (0° / 90° / 180° / 270°)
                    HStack(spacing: 10) {
                        Text("🔄 向き:")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                        
                        ForEach([0, 90, 180, 270], id: \.self) { deg in
                            Button(action: {
                                rotationAngle = deg
                                camera.setRotation(angle: deg)
                            }) {
                                Text("\(deg)°")
                                    .font(.system(size: 12, weight: .heavy))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(rotationAngle == deg ? Color.green : Color.black.opacity(0.6))
                                    .foregroundColor(rotationAngle == deg ? Color.black : Color.white)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }
                    }

                    // 撮影画角・比率バー (16:9 / 16:8 / 2.35:1)
                    HStack(spacing: 8) {
                        Text("📐 比率:")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                        
                        ForEach(["16:9", "16:8", "2.35:1"], id: \.self) { ratio in
                            Button(action: {
                                aspectRatioMode = ratio
                            }) {
                                Text(ratio == "16:9" ? "16:9 (フル)" : (ratio == "16:8" ? "16:8 (ワイド)" : "2.35:1 (シネマ)"))
                                    .font(.system(size: 11, weight: .heavy))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(aspectRatioMode == ratio ? Color.cyan : Color.black.opacity(0.6))
                                    .foregroundColor(aspectRatioMode == ratio ? Color.black : Color.white)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }
                    }

                    Divider().background(Color.white.opacity(0.2))

                    // ─────────────────────────────────────────────
                    // シャッタースピード設定 (1/1000 〜 1/2000秒 マニュアル調整 & オート)
                    // ─────────────────────────────────────────────
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Text("⚡ シャッター:")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text(shutterSpeedDenominator <= 0 ? "自動 (Auto)" : "1/\(Int(shutterSpeedDenominator))秒")
                                .font(.system(size: 11, weight: .heavy))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(shutterSpeedDenominator <= 0 ? Color.green.opacity(0.25) : Color.yellow.opacity(0.25))
                                .foregroundColor(shutterSpeedDenominator <= 0 ? .green : .yellow)
                                .cornerRadius(6)
                            
                            Spacer()
                            
                            // Auto 復帰ボタン
                            Button(action: {
                                shutterSpeedDenominator = 0
                                camera.setShutterSpeed(denominator: 0)
                            }) {
                                Text("Auto")
                                    .font(.system(size: 11, weight: .heavy))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(shutterSpeedDenominator <= 0 ? Color.green : Color.black.opacity(0.6))
                                    .foregroundColor(shutterSpeedDenominator <= 0 ? .black : .white)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                            }
                            
                            // プリセットボタン (1/1000, 1/1500, 1/2000)
                            ForEach([1000.0, 1500.0, 2000.0], id: \.self) { speed in
                                Button(action: {
                                    shutterSpeedDenominator = speed
                                    camera.setShutterSpeed(denominator: speed)
                                }) {
                                    Text("1/\(Int(speed))")
                                        .font(.system(size: 11, weight: .heavy))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                        .background(abs(shutterSpeedDenominator - speed) < 1.0 ? Color.yellow : Color.black.opacity(0.6))
                                        .foregroundColor(abs(shutterSpeedDenominator - speed) < 1.0 ? .black : .white)
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                        )
                                }
                            }
                        }
                        
                        // 1000〜2000 のマニュアル微調整スライダー (50単位でステップ調整)
                        if shutterSpeedDenominator > 0 {
                            HStack(spacing: 8) {
                                Text("1/1000s")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                                
                                Slider(
                                    value: Binding(
                                        get: { shutterSpeedDenominator },
                                        set: { newVal in
                                            let snapped = round(newVal / 50.0) * 50.0
                                            shutterSpeedDenominator = snapped
                                            camera.setShutterSpeed(denominator: snapped)
                                        }
                                    ),
                                    in: 1000...2000,
                                    step: 50
                                )
                                .accentColor(.yellow)
                                
                                Text("1/2000s")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding(.top, 2)
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
                    // ─────────────────────────────────────────────
                    // カメラ電源モード切替 (自動キオスク連動 / 強制ON / 強制OFF)
                    // ─────────────────────────────────────────────
                    HStack(spacing: 6) {
                        Text("📷 電源:")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)

                        Button(action: {
                            cameraPowerMode = "auto"
                            camera.setPowerMode("auto")
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "bolt.badge.automatic.fill")
                                Text("自動 (連動)")
                            }
                            .font(.system(size: 11, weight: .heavy))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(cameraPowerMode == "auto" ? Color.green : Color.white.opacity(0.15))
                            .foregroundColor(cameraPowerMode == "auto" ? .black : .white)
                            .cornerRadius(7)
                        }

                        Button(action: {
                            cameraPowerMode = "manual_on"
                            camera.setPowerMode("manual_on")
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "video.fill")
                                Text("常時ON")
                            }
                            .font(.system(size: 11, weight: .heavy))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(cameraPowerMode == "manual_on" ? Color.orange : Color.white.opacity(0.15))
                            .foregroundColor(cameraPowerMode == "manual_on" ? .black : .white)
                            .cornerRadius(7)
                        }

                        Button(action: {
                            cameraPowerMode = "manual_off"
                            camera.setPowerMode("manual_off")
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "video.slash.fill")
                                Text("常時OFF")
                            }
                            .font(.system(size: 11, weight: .heavy))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(cameraPowerMode == "manual_off" ? Color.red : Color.white.opacity(0.15))
                            .foregroundColor(cameraPowerMode == "manual_off" ? .white : .white)
                            .cornerRadius(7)
                        }
                    }

                    // カメラ役割の切り替え (正面 / 右打席側面 / 左打席側面)
                    HStack(spacing: 6) {
                        Button(action: {
                            cameraRole = "cam_front"
                            restartListening()
                        }) {
                            Text("⚾ 正面")
                                .font(.system(size: 12, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(cameraRole == "cam_front" ? Color.blue : Color.white.opacity(0.15))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }

                        Button(action: {
                            cameraRole = "cam_side_right"
                            restartListening()
                        }) {
                            Text("📐 右打席 側面")
                                .font(.system(size: 12, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(cameraRole == "cam_side_right" ? Color.blue : Color.white.opacity(0.15))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }

                        Button(action: {
                            cameraRole = "cam_side_left"
                            restartListening()
                        }) {
                            Text("📐 左打席 側面")
                                .font(.system(size: 12, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(cameraRole == "cam_side_left" ? Color.blue : Color.white.opacity(0.15))
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

                            HStack(spacing: 6) {
                                Text("チャープ感度:")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .frame(width: 85, alignment: .leading)
                                
                                ForEach([0.15, 0.18, 0.22, 0.28, 0.35], id: \.self) { th in
                                    Button(action: {
                                        chirpThreshold = th
                                        chirpDetector.detectionThreshold = Float(th)
                                    }) {
                                        Text(String(format: "%.2f", th))
                                            .font(.system(size: 10, weight: .heavy))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 3)
                                            .background(abs(chirpThreshold - th) < 0.01 ? Color.yellow : Color.black.opacity(0.6))
                                            .foregroundColor(abs(chirpThreshold - th) < 0.01 ? .black : .white)
                                            .cornerRadius(5)
                                    }
                                }
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
            camera.setRotation(angle: rotationAngle)
            camera.setup240fpsCamera()
            camera.setPowerMode(cameraPowerMode)
            if shutterSpeedDenominator > 0 {
                camera.setShutterSpeed(denominator: shutterSpeedDenominator)
            }
            chirpDetector.detectionThreshold = Float(chirpThreshold)
            if chirpDetectionEnabled {
                chirpDetector.startDetection()
            }
            restartListening()
        }
        .onDisappear {
            chirpDetector.stopDetection()
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
// 240fps カメラマネージャー & 遠隔同期 (毎秒2コマ プレビュー送信対応)
// ─────────────────────────────────────────────
class Camera240Manager: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let previewQueue = DispatchQueue(label: "com.amsp.previewQueue")
    private var lastPreviewSentTime: TimeInterval = 0
    private var isSendingPreview: Bool = false
    private var currentRotationAngle: Int = 90
    
    private var currentControllerIP: String = ""
    private var currentAnalysisIP: String = ""
    private var currentCameraRole: String = "cam_side_right"
    
    private var isListening: Bool = false
    private var listeningTask: URLSessionDataTask?
    private var countdownTimer: Timer?
    
    @Published var isRecording = false
    @Published var isUploading = false
    @Published var isAutoCountingDown = false
    @Published var remainingSeconds = 0
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var currentShutterDenominator: Double = 0
    @Published var currentISO: Float = 0
    @Published var statusMessage = "待機中 (240fps スタンバイ)"
    
    // カメラ電源ライフサイクル管理
    @Published var isCameraRunning = false
    @Published var isKioskReadyOrRecording = false
    @Published var kioskScreenState = "standby"
    private var powerMode: String = "auto" // "auto", "manual_on", "manual_off"

    func setPowerMode(_ mode: String) {
        self.powerMode = mode
        applyCameraPowerState()
    }

    func applyCameraPowerState() {
        switch powerMode {
        case "manual_on":
            startCameraSessionIfNeeded()
        case "manual_off":
            if !isRecording {
                stopCameraSessionIfNeeded()
            }
        default: // "auto" (キオスクがreadyまたはrecording中ならカメラON、それ以外はOFF)
            if isKioskReadyOrRecording || isRecording {
                startCameraSessionIfNeeded()
            } else {
                stopCameraSessionIfNeeded()
            }
        }
    }

    func startCameraSessionIfNeeded() {
        guard !session.isRunning else {
            DispatchQueue.main.async { self.isCameraRunning = true }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isCameraRunning = self.session.isRunning
                self.updateMovieOrientation()
                print("[CameraPower] ✅ カメラセッション起動 (ON)")
            }
        }
    }

    func stopCameraSessionIfNeeded() {
        guard session.isRunning else {
            DispatchQueue.main.async { self.isCameraRunning = false }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isCameraRunning = false
                print("[CameraPower] 💤 カメラセッション停止 (OFF / 省電力モード)")
            }
        }
    }

    func setRotation(angle: Int) {
        currentRotationAngle = angle
        updateMovieOrientation()
    }
    
    func updateMovieOrientation() {
        guard let connection = movieOutput.connection(with: .video) else { return }
        if connection.isVideoOrientationSupported {
            switch currentRotationAngle {
            case 90: connection.videoOrientation = .portrait
            case 180: connection.videoOrientation = .landscapeLeft
            case 270: connection.videoOrientation = .portraitUpsideDown
            default: connection.videoOrientation = .landscapeRight
            }
        }
    }
    
    func setup240fpsCamera() {
        session.beginConfiguration()
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            statusMessage = "カメラ初期化エラー"
            return
        }
        
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        if session.canAddOutput(videoDataOutput) {
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.setSampleBufferDelegate(self, queue: previewQueue)
            session.addOutput(videoDataOutput)
        }
        
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
        updateMovieOrientation()
        applyCameraPowerState()
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
    // シャッタースピード設定 (1/1000〜1/2000秒 マニュアル固定 & オート)
    // ─────────────────────────────────────────────
    func setShutterSpeed(denominator: Double) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        do {
            try device.lockForConfiguration()
            if denominator <= 0 {
                // オート露出へ復帰
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                DispatchQueue.main.async {
                    self.currentShutterDenominator = 0
                }
                print("[Camera] Exposure mode restored to continuousAutoExposure")
            } else {
                // マニュアル固定 (1/1000 〜 1/2000秒)
                let clampedDenom = max(500.0, min(denominator, 4000.0))
                let targetDuration = CMTime(value: 1, timescale: Int32(clampedDenom))
                let minDuration = device.activeFormat.minExposureDuration
                let maxDuration = device.activeFormat.maxExposureDuration
                let safeDuration = max(minDuration, min(targetDuration, maxDuration))
                
                let minISO = device.activeFormat.minISO
                let maxISO = device.activeFormat.maxISO
                // 高速シャッター時は受光量が激減するため、ISO感度を適切な範囲で確保
                let current = device.iso
                let targetISO = min(maxISO, max(minISO, max(current, 400.0)))
                
                if device.isExposureModeSupported(.custom) {
                    device.setExposureModeCustom(duration: safeDuration, iso: targetISO) { [weak self] _ in
                        guard let self = self else { return }
                        DispatchQueue.main.async {
                            self.currentISO = targetISO
                        }
                    }
                    DispatchQueue.main.async {
                        self.currentShutterDenominator = clampedDenom
                    }
                    print("[Camera] Custom shutter set: 1/\(Int(clampedDenom))s, ISO: \(targetISO)")
                }
            }
            device.unlockForConfiguration()
        } catch {
            print("Shutter speed configuration error:", error)
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
                    // キオスク画面状態およびカメラ要求フラグの更新
                    if let req = json["camera_required"] as? Bool {
                        self.isKioskReadyOrRecording = req
                        self.applyCameraPowerState()
                    }
                    if let kScreen = json["kiosk_screen"] as? String {
                        self.kioskScreenState = kScreen
                    }

                    if action == "CAMERA_ON" {
                        self.isKioskReadyOrRecording = true
                        self.applyCameraPowerState()
                    } else if action == "CAMERA_OFF" {
                        if !self.isRecording {
                            self.isKioskReadyOrRecording = false
                            self.applyCameraPowerState()
                        }
                    } else if action == "START" {
                        self.isKioskReadyOrRecording = true
                        self.startCameraSessionIfNeeded()
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
                    } else if action == "MEASURE_TILT" {
                        self.measureAndSendTilt()
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
                
                // 送信完了後、キオスクがreadyでなければ自動省電力停止
                self.applyCameraPowerState()
                
                // 送信完了後、再びPC待機ループに戻る
                self.pollNextCommand()
            }
        }
        task.resume()
    }

    // ─────────────────────────────────────────────
    // 毎秒2コマ (2fps) リアルタイムプレビュー配信
    // ─────────────────────────────────────────────
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // 録画中・アップロード中・カメラ非動作中はプレビュー配信をスキップしてリソース保護
        guard isCameraRunning, !isRecording, !isUploading, isListening, !isSendingPreview else { return }
        
        let now = Date().timeIntervalSince1970
        guard now - lastPreviewSentTime >= 0.5 else { return } // 0.5秒おき (毎秒2コマ)
        
        lastPreviewSentTime = now
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // 向き回転の適用 (0° / 90° / 180° / 270°) - デフォルト90°で左倒れ解消
        var orientedImage = ciImage
        switch currentRotationAngle {
        case 90:
            orientedImage = ciImage.oriented(.right) // 時計回り90度 (左倒れ完全解消)
        case 180:
            orientedImage = ciImage.oriented(.down)  // 180度
        case 270:
            orientedImage = ciImage.oriented(.left)  // 反時計回り90度
        default:
            break // 0度 (未回転)
        }
        
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(orientedImage, from: orientedImage.extent) else { return }
        
        let image = UIImage(cgImage: cgImage)
        guard let jpegData = image.jpegData(compressionQuality: 0.45) else { return }
        
        sendPreviewFrame(jpegData)
    }
    
    private func sendPreviewFrame(_ data: Data) {
        let cleanIP = sanitizeIP(currentControllerIP)
        guard !cleanIP.isEmpty, let url = URL(string: "http://\(cleanIP):8080/api/preview_frame?camera=\(currentCameraRole)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        request.timeoutInterval = 1.5
        
        isSendingPreview = true
        URLSession.shared.dataTask(with: request) { [weak self] _, _, _ in
            self?.isSendingPreview = false
        }.resume()
    }
    
    // ─────────────────────────────────────────────
    // PC指示による傾き計測＆送信 (オンデマンド・ワンショット実行)
    // ─────────────────────────────────────────────
    private let motionManager = CMMotionManager()

    func measureAndSendTilt() {
        guard motionManager.isDeviceMotionAvailable else {
            print("[MotionTilt] ⚠️ ジャイロ・加速度センサーが利用不可です")
            return
        }
        
        // PCから指示された瞬間のみ起動 (0.05秒間だけ計測して即座に終了・負荷ゼロ)
        motionManager.deviceMotionUpdateInterval = 0.05
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self = self, let motion = motion else { return }
            
            // 1回計測したら直ちに停止してCPU/バッテリー負荷を完全ゼロ化
            self.motionManager.stopDeviceMotionUpdates()
            
            let gz = motion.gravity.z
            let gx = motion.gravity.x
            // 横向き（Landscape）設置時の上下の傾き (Pitch角)
            // gravity.z: 水平時 0.0, 見上げ時 -1.0, 見下げ時 +1.0
            let pitch = asin(max(-1.0, min(1.0, -gz))) * (180.0 / .pi)
            let roll = gx * (180.0 / .pi)
            
            print(String(format: "[MotionTilt] 📐 PC指示により傾き計測完了: カメラ=%@, Pitch=%+.2f°, Roll=%+.2f°", self.currentCameraRole, pitch, roll))
            self.sendTiltDataToPC(pitch: pitch, roll: roll)
        }
    }
    
    private func sendTiltDataToPC(pitch: Double, roll: Double) {
        let cleanIP = sanitizeIP(currentControllerIP)
        guard !cleanIP.isEmpty, let url = URL(string: "http://\(cleanIP):8080/api/camera_tilt") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 3.0
        
        let payload: [String: Any] = [
            "camera": currentCameraRole,
            "pitch": pitch,
            "roll": roll,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("[MotionTilt] ❌ PCへの傾き送信失敗:", error.localizedDescription)
            } else {
                print("[MotionTilt] ✅ PCへ傾きデータを正常送信完了")
            }
        }.resume()
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

// ─────────────────────────────────────────────
// チャープ音（5kHz -> 12kHz, 70ms）高精度・超低負荷 リアルタイム検出エンジン
// ─────────────────────────────────────────────
class ChirpAudioDetector: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var chirpCount: Int = 0
    @Published var isRecentlyDetected: Bool = false
    @Published var statusText: String = "マイク停止中"
    @Published var detectionThreshold: Float = 0.18 // 判定閾値（0.35から0.18へ引き下げ）
    @Published var lastPeakCorrelation: Float = 0.0 // 直近のピークNCC相関値（視認用）
    
    private let audioEngine = AVAudioEngine()
    private let processingQueue = DispatchQueue(label: "com.amsp.chirpProcessing", qos: .userInitiated)
    
    // チャープ波形パラメータ (2kHz -> 5kHz / 70ms: NS4168スピーカー最高音圧帯 & 環境ノイズ分離)
    private let fStart: Double = 2000.0
    private let fEnd: Double = 5000.0
    private let chirpDuration: Double = 0.070 // 70ms
    
    // サンプルレート別 参照チャープ波形 (直交I/Q成分: 位相ずれに左右されない直交検波)
    private var referenceChirpI: [Float] = []
    private var referenceChirpQ: [Float] = []
    private var referenceNorm: Float = 1.0
    private var configuredSampleRate: Double = 0.0
    
    // バッファ境界またぎ対策のオーバーラップ保持
    private var overlapBuffer: [Float] = []
    
    // デバウンス用 (多重カウント防止)
    private var lastDetectionTimestamp: TimeInterval = 0
    private let debounceInterval: TimeInterval = 0.35 // 350ms
    private var bannerHideWorkItem: DispatchWorkItem?
    
    init() {
        // デフォルト44100Hzで事前初期化
        updateReferenceChirp(sampleRate: 44100.0)
    }
    
    private func updateReferenceChirp(sampleRate: Double) {
        guard sampleRate > 0, sampleRate != configuredSampleRate else { return }
        configuredSampleRate = sampleRate
        
        let nSamples = Int(sampleRate * chirpDuration)
        referenceChirpI = [Float](repeating: 0, count: nSamples)
        referenceChirpQ = [Float](repeating: 0, count: nSamples)
        let k = (fEnd - fStart) / chirpDuration
        
        var sumSq: Float = 0.0
        for i in 0..<nSamples {
            let t = Double(i) / sampleRate
            let phase = 2.0 * .pi * (fStart * t + 0.5 * k * t * t)
            // Tukey窓（端部3msのみフェード）
            let fadeSamples = max(1, Int(sampleRate * 0.003))
            var w: Double = 1.0
            if i < fadeSamples {
                w = 0.5 * (1.0 - cos(.pi * Double(i) / Double(fadeSamples)))
            } else if i >= nSamples - fadeSamples {
                w = 0.5 * (1.0 - cos(.pi * Double(nSamples - 1 - i) / Double(fadeSamples)))
            }
            let valI = Float(w * sin(phase))
            let valQ = Float(w * cos(phase))
            referenceChirpI[i] = valI
            referenceChirpQ[i] = valQ
            sumSq += valI * valI
        }
        referenceNorm = max(1e-6, sqrt(sumSq))
    }
    
    func startDetection() {
        guard !isRunning else { return }
        
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if !granted {
                    self.statusText = "❌ マイク権限が拒否されています"
                    print("[ChirpDetector] ⚠️ マイク権限が拒否されています")
                    return
                }
                self.startAudioEngine()
            }
        }
    }
    
    private func startAudioEngine() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true)
            
            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            let sampleRate = inputFormat.sampleRate > 0 ? inputFormat.sampleRate : 44100.0
            
            updateReferenceChirp(sampleRate: sampleRate)
            overlapBuffer.removeAll()
            
            // オンになった瞬間にカウントをリセットして監視開始
            chirpCount = 0
            isRecentlyDetected = false
            
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, time in
                guard let self = self else { return }
                self.processAudioBuffer(buffer: buffer)
            }
            
            try audioEngine.start()
            isRunning = true
            statusText = "🔊 マイク監視中 (2kHz-5kHz 待機)"
            print("[ChirpDetector] ✅ マイク監視開始 (SR: \(sampleRate)Hz)")
        } catch {
            statusText = "❌ マイク起動エラー: \(error.localizedDescription)"
            isRunning = false
            print("[ChirpDetector] Audio engine start error:", error)
        }
    }
    
    func stopDetection() {
        guard isRunning else { return }
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        
        isRunning = false
        statusText = "🔇 マイク停止 (検出総数: \(chirpCount)回)"
        print("[ChirpDetector] ⏹ マイク停止 (オフ時検出数: \(chirpCount)回)")
    }
    
    func resetCount() {
        chirpCount = 0
        isRecentlyDetected = false
    }
    
    private func processAudioBuffer(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        
        let newSamples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 直前のオーバーラップデータと結合
            let fullData = self.overlapBuffer + newSamples
            let refLen = self.referenceChirpI.count
            guard fullData.count >= refLen else {
                self.overlapBuffer = fullData
                return
            }
            
            // スライディング直交正規化相互相関 (Quadrature NCC)
            // キャリア位相(φ)依存性を完全排除し、微細ステップ(4サンプル)でピークを確実に捕捉
            let step = 4
            let maxIndex = fullData.count - refLen
            var maxCorrelation: Float = 0.0
            
            let refI = self.referenceChirpI
            let refQ = self.referenceChirpQ
            let refNorm = self.referenceNorm
            
            for i in stride(from: 0, through: maxIndex, by: step) {
                var dotI: Float = 0.0
                var dotQ: Float = 0.0
                fullData.withUnsafeBufferPointer { fullPtr in
                    guard let basePtr = fullPtr.baseAddress else { return }
                    vDSP_dotpr(basePtr + i, 1, refI, 1, &dotI, vDSP_Length(refLen))
                    vDSP_dotpr(basePtr + i, 1, refQ, 1, &dotQ, vDSP_Length(refLen))
                }
                
                // シグナル局所エネルギーの算出
                var sigEnergySq: Float = 0.0
                fullData.withUnsafeBufferPointer { fullPtr in
                    guard let basePtr = fullPtr.baseAddress else { return }
                    vDSP_svesq(basePtr + i, 1, &sigEnergySq, vDSP_Length(refLen))
                }
                
                let sigNorm = sqrt(sigEnergySq)
                if sigNorm > 1e-4 {
                    let iqMag = sqrt(dotI * dotI + dotQ * dotQ)
                    let ncc = iqMag / (sigNorm * refNorm)
                    if ncc > maxCorrelation {
                        maxCorrelation = ncc
                    }
                }
            }
            
            // 次回用に最後の (refLen - 1) サンプルをオーバーラップとして保持
            let keepCount = min(refLen - 1, fullData.count)
            self.overlapBuffer = Array(fullData.suffix(keepCount))
            
            // しきい値判定 (直交NCC >= detectionThreshold: 0.18 で遠距離・騒音下でも確実に検出)
            let now = Date().timeIntervalSince1970
            if maxCorrelation >= self.detectionThreshold {
                if now - self.lastDetectionTimestamp > self.debounceInterval {
                    self.lastDetectionTimestamp = now
                    print(String(format: "[ChirpDetector] ⚡⚡⚡ CHIRP DETECTED! NCC=%.3f (Threshold=%.2f) at %@", maxCorrelation, self.detectionThreshold, Date().description))
                    
                    DispatchQueue.main.async {
                        self.chirpCount += 1
                        self.isRecentlyDetected = true
                        self.lastPeakCorrelation = maxCorrelation
                        
                        // 1.5秒後にバナーを自動非表示
                        self.bannerHideWorkItem?.cancel()
                        let item = DispatchWorkItem { [weak self] in
                            self?.isRecentlyDetected = false
                        }
                        self.bannerHideWorkItem = item
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
                    }
                }
            } else if maxCorrelation > 0.08 {
                // しきい値未満でも微弱な相関があった場合に直近ピークを記録（感度調整・視認用）
                DispatchQueue.main.async {
                    self.lastPeakCorrelation = maxCorrelation
                }
            }
        }
    }
}


