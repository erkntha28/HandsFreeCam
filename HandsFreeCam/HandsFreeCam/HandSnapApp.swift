import SwiftUI
import AVFoundation
import Vision
import Photos
import UIKit
import Combine

@main
struct HandsFreeCamApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

// MARK: - Arayüz
struct ContentView: View {
    @StateObject private var camera = CameraController()
    @Environment(\.openURL) private var openURL
    @State private var showPermissionAlert = false

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
                .onAppear { camera.start() }
                .onDisappear { camera.stop() }

            VStack {
                Label(camera.isHandDetected ? "🖐 El algılandı" : "El bekleniyor",
                      systemImage: camera.isHandDetected ? "hand.raised.fill" : "hand.raised")
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .animation(.easeInOut(duration: 0.2), value: camera.isHandDetected)
                    .padding(.top, 16)

                Spacer()

                // Geri sayım overlay
                if let remaining = camera.countdownRemaining, remaining > 0 {
                    Text("Çekim: \(Int(ceil(remaining)))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .transition(.scale.combined(with: .opacity))
                        .padding(.bottom, 8)
                }

                HStack(spacing: 12) {
                    Label(camera.isAuthorized ? "İzin: OK" : "İzin Yok",
                          systemImage: camera.isAuthorized ? "checkmark.seal" : "exclamationmark.triangle")
                        .font(.footnote)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())

                    Spacer()

                    // Zamanlayıcı seçimi
                    Picker("", selection: $camera.selectedTimerSeconds) {
                        Text("Kapalı").tag(0)
                        Text("3s").tag(3)
                        Text("5s").tag(5)
                        Text("10s").tag(10)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())

                    Button { camera.toggleCameraPosition() } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
        .onChange(of: camera.permissionDenied) { _, newValue in
            showPermissionAlert = newValue
        }
        .alert("Kamera izni gerekli", isPresented: $showPermissionAlert) {
            Button("Ayarlar’a Git") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            Button("İptal", role: .cancel) {}
        } message: {
            Text("El algılama ve fotoğraf çekimi için kamera erişimi gereklidir.")
        }
    }
}

// MARK: - Kamera Önizleme
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

// MARK: - Kamera + Vision
final class CameraController: NSObject, ObservableObject {
    // UI’ya yansıtılan durumlar
    @Published var isHandDetected = false
    @Published var isAuthorized = false
    @Published var permissionDenied = false

    // Zamanlayıcı durumu
    @Published var selectedTimerSeconds: Int = 0          // 0: Kapalı, 3/5/10
    @Published var countdownRemaining: TimeInterval? = nil

    // Parametreler
    private var confidenceStorage: Float = 0.6
    private let confidenceLock = NSLock()
    var confidence: Float {
        get {
            confidenceLock.lock()
            let v = confidenceStorage
            confidenceLock.unlock()
            return v
        }
        set {
            confidenceLock.lock()
            confidenceStorage = newValue
            confidenceLock.unlock()
        }
    }

    private var lastCapture: TimeInterval = 0
    private let cooldown: TimeInterval = 2.0

    // Zamanlayıcı
    private var countdownTimer: Timer?

    // AVFoundation
    let session = AVCaptureSession()
    private var deviceInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "cam.session.queue")

    // Vision
    // Move to static factory to avoid main-actor isolation; create per-frame request for thread-safety.
    nonisolated private static func makeHandRequest() -> VNDetectHumanHandPoseRequest {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }

    override init() {
        super.init()
        requestPermissions()
    }

    deinit {
        invalidateCountdown()
    }

    // MARK: - İzinler
    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isAuthorized = granted
                self.permissionDenied = !granted
            }
            if granted { self.configureSession() }
        }

        // Fotoğraf kütüphanesi ekleme izni (iOS 14+)
        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in }
        } else {
            PHPhotoLibrary.requestAuthorization { _ in }
        }
    }

    // MARK: - Oturum yapılandırması
    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            // Giriş
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                return
            }

            self.session.addInput(input)
            self.deviceInput = input

            // Video çıkışı
            let videoQueue = DispatchQueue(label: "cam.video.queue")
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)
            ]
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }
            // Delegate’i mutlaka ata: Vision’ın çalışması için gerekli
            self.videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

            if let conn = self.videoOutput.connections.first {
                // Portre yönü (90°) varsayımı
                if conn.isVideoRotationAngleSupported(90) {
                    conn.videoRotationAngle = 90
                }
                conn.isVideoMirrored = (self.deviceInput?.device.position == .front)
            }

            // Fotoğraf çıkışı
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }

            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    // MARK: - Başlat / Durdur
    func start() {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop()  {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    // MARK: - Kamera değiştir
    func toggleCameraPosition() {
        sessionQueue.async { [weak self] in
            guard let self, let current = self.deviceInput else { return }
            let newPos: AVCaptureDevice.Position = current.device.position == .back ? .front : .back
            guard let newDev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPos),
                  let newInput = try? AVCaptureDeviceInput(device: newDev)
            else { return }

            self.session.beginConfiguration()
            self.session.removeInput(current)
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.deviceInput = newInput
            } else if self.session.canAddInput(current) {
                self.session.addInput(current)
            }

            // Bağlantı ayarları (rotation + mirror)
            if let conn = self.videoOutput.connections.first {
                if conn.isVideoRotationAngleSupported(90) {
                    conn.videoRotationAngle = 90
                }
                conn.isVideoMirrored = (newPos == .front)
            }

            self.session.commitConfiguration()
        }
    }

    // MARK: - Fotoğraf çek
    private func shoot() {
        let now = CACurrentMediaTime()
        guard now - lastCapture > cooldown else { return }
        lastCapture = now

        let settings = AVCapturePhotoSettings()
        if self.photoOutput.supportedFlashModes.contains(.auto) {
            settings.flashMode = .auto
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
        DispatchQueue.main.async {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: - Zamanlayıcı kontrolü
    private func startCountdownIfNeeded() {
        let seconds = selectedTimerSeconds
        if seconds <= 0 {
            // Zamanlayıcı kapalıysa direkt çek
            shoot()
            return
        }
        // Zaten aktif geri sayım varsa yenisini başlatma
        if countdownTimer != nil { return }

        DispatchQueue.main.async {
            self.countdownRemaining = TimeInterval(seconds)
            self.countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] t in
                guard let self else { return }
                let newValue = max(0, (self.countdownRemaining ?? 0) - 0.1)
                self.countdownRemaining = newValue
                if newValue <= 0 {
                    t.invalidate()
                    self.countdownTimer = nil
                    self.countdownRemaining = nil
                    self.shoot()
                }
            }
            RunLoop.main.add(self.countdownTimer!, forMode: .common)
        }
    }

    private func invalidateCountdown() {
        DispatchQueue.main.async {
            self.countdownTimer?.invalidate()
            self.countdownTimer = nil
            self.countdownRemaining = nil
        }
    }
}

// MARK: - Vision Delegate
nonisolated extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Snapshot confidence without crossing main actor.
        let threshold: Float = self.confidence

        // Create per-frame request and handler to avoid main-actor isolation and thread-safety issues.
        let handRequest = CameraController.makeHandRequest()
        let sequenceHandler = VNSequenceRequestHandler()
        do {
            try sequenceHandler.perform([handRequest], on: buffer)
            guard let results = handRequest.results, !results.isEmpty else {
                DispatchQueue.main.async {
                    // El kaybolduğunda UI durumunu güncelle, geri sayımı artık iptal etme
                    self.isHandDetected = false
                    // self.invalidateCountdown()  // KALDIRILDI
                }
                return
            }

            let detected = results.contains { hand in
                if let pts = try? hand.recognizedPoints(.all) {
                    let valid = pts.values.filter { $0.confidence > threshold }
                    return valid.count >= 3
                } else {
                    return false
                }
            }

            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.1)) { self.isHandDetected = detected }
                if detected {
                    // El algılanınca geri sayımı başlat (gerekirse)
                    self.startCountdownIfNeeded()
                } else {
                    // El kaybolsa da geri sayım devam etmeli — iptal etme
                    // self.invalidateCountdown()  // KALDIRILDI
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.isHandDetected = false
                // Hata durumunda da geri sayımı zorla iptal etmiyoruz
                // self.invalidateCountdown()  // İsterseniz burada da iptal etmeyebilirsiniz
            }
        }
    }
}

// MARK: - Fotoğraf kaydı
extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data)
        else { return }

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }, completionHandler: { success, error in
            // İsterseniz hata loglayabilirsiniz
            // if !success { print("Save error: \(error?.localizedDescription ?? "unknown")") }
        })
    }
}
