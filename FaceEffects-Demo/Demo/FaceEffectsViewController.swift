//
//  FaceEffectsViewController.swift
//  FaceEffects-Demo
//
//  Created by Nikunj Prajapati on 27/12/21.
//

import UIKit
import AVKit
import Vision

final class FaceEffectsViewController: UIViewController {
    
    //MARK: IBOutlet
    // Main view for showing camera content.
    @IBOutlet weak private var cameraPreviewView: UIView!
    @IBOutlet weak private var maskStackView: UIStackView!
    @IBOutlet weak private var mask1: UIButton!
    @IBOutlet weak private var mask2: UIButton!
    @IBOutlet weak private var mask3: UIButton!
    
    //MARK: Properties
    // AVCapture variables to hold sequence data
    private var session: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var videoDataOutputQueue: DispatchQueue?
    private var captureDevice: AVCaptureDevice?
    private var captureDeviceResolution: CGSize = CGSize()
    
    // Layer UI for drawing Vision results
    private var rootLayer: CALayer?
    private var detectionOverlayLayer: CALayer?
    private var detectedFaceRectangleShapeLayer: CAShapeLayer?
    private var detectedFaceLandmarksShapeLayer: CAShapeLayer?
    private var detectedEyeBrowLayers: CAShapeLayer?
    private var detectedLipsLayer: CAShapeLayer?
    private var detectedTounge: CAShapeLayer?
    
    // Vision requests
    private var detectionRequests: [VNDetectFaceRectanglesRequest]?
    private var trackingRequests: [VNTrackObjectRequest]?
    private lazy var sequenceRequestHandler = VNSequenceRequestHandler()
    
    // Face effects varialbes
    private var faceRect = CGRect()
    private var showEmoji = false
    private var maskImgView = UIImageView()
    private let emojis = ["🦁","🐶","🦊"]
    private var emojiIndex = 0
    
    // Ensure that the interface stays locked in Portrait.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    // Ensure that the interface stays locked in Portrait.
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }
    
    //MARK: View lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureSession()
        configureUI()
    }
}

//MARK: - Configure AVCaptureSession
extension FaceEffectsViewController {
    
    // Start AVCaptureSession
    private func configureSession() {
        
        session = configureAVCaptureSession()
        
        preapareVisionRequest()
        
        session?.startRunning()
    }
    
    private func configureUI() {
        
        mask1.setImage(emojis[0].convertStringToImage(), for: .normal)
        mask2.setImage(emojis[1].convertStringToImage(), for: .normal)
        mask3.setImage(emojis[2].convertStringToImage(), for: .normal)
        
        addTapGesture()
    }
    
    // Add tap gesture to change face effects
    private func addTapGesture() {
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(onTappingCameraView))
        view.addGestureRecognizer(tapGesture)
    }
    
    @objc private func onTappingCameraView() {
        showEmoji.toggle()
    }
    
    // Configure AVCaptureSession
    private func configureAVCaptureSession() -> AVCaptureSession? {
        
        let captureSession = AVCaptureSession()
        
        do {
            let inputDevice = try configureFrontCamera(for: captureSession)
            configureVideoDataOutput(for: inputDevice.device, resolution: inputDevice.resolution, captureSession: captureSession)
            designatePreviewLayer(for: captureSession)
            return captureSession
            
        } catch let executionError as NSError {
            presentError(executionError)
        } catch {
            presentErrorAlert(message: "An unexpected failure has occured")
        }
        
        teardownAVCapture()
        return nil
    }
    
    // Configure front camera
    private func configureFrontCamera(for captureSession: AVCaptureSession) throws -> (device: AVCaptureDevice, resolution: CGSize) {
        
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .front)
        
        if let device = deviceDiscoverySession.devices.first {
            
            if let deviceInput = try? AVCaptureDeviceInput(device: device) {
                if captureSession.canAddInput(deviceInput) {
                    captureSession.addInput(deviceInput)
                }
                
                if let highestResolution = highestResolution420Format(for: device) {
                    
                    try device.lockForConfiguration()
                    device.activeFormat = highestResolution.format
                    device.unlockForConfiguration()
                    
                    return (device, highestResolution.resolution)
                }
            }
        }
        throw NSError(domain: "FaceEffectsViewController", code: 1, userInfo: nil)
    }
    
    // Configure AVCaptureDevice resolution
    private func highestResolution420Format(for device: AVCaptureDevice) -> (format: AVCaptureDevice.Format, resolution: CGSize)? {
        
        var highestResolutionFormat: AVCaptureDevice.Format? = nil
        var highestResolutionDimensions = CMVideoDimensions(width: 0, height: 0)
        
        for format in device.formats {
            let deviceFormat = format as AVCaptureDevice.Format
            
            let deviceFormatDescription = deviceFormat.formatDescription
            
            if CMFormatDescriptionGetMediaSubType(deviceFormatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
                
                let candidateDimensions = CMVideoFormatDescriptionGetDimensions(deviceFormatDescription)
                
                if (highestResolutionFormat == nil) || (candidateDimensions.width > highestResolutionDimensions.width) {
                    highestResolutionFormat = deviceFormat
                    highestResolutionDimensions = candidateDimensions
                }
            }
        }
        
        if highestResolutionFormat != nil {
            let resolution = CGSize(width: CGFloat(highestResolutionDimensions.width), height: CGFloat(highestResolutionDimensions.height))
            return (highestResolutionFormat!, resolution)
        }
        
        return nil
    }
    
    // Configure VideoDataOutput and create a DispatchQueue
    private func configureVideoDataOutput(for inputDevice: AVCaptureDevice, resolution: CGSize, captureSession: AVCaptureSession) {
        
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        // Create a serial dispatch queue used for the sample buffer delegate as well as when a still image is captured.
        // A serial dispatch queue must be used to guarantee that video frames will be delivered in order.
        let videoDataOutputQueue = DispatchQueue(label: "com.mi.FaceEffects-Demo")
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        }
        
        videoDataOutput.connection(with: .video)?.isEnabled = true
        
        if let captureConnection = videoDataOutput.connection(with: AVMediaType.video) {
            if captureConnection.isCameraIntrinsicMatrixDeliverySupported {
                captureConnection.isCameraIntrinsicMatrixDeliveryEnabled = true
            }
        }
        
        self.videoDataOutput = videoDataOutput
        self.videoDataOutputQueue = videoDataOutputQueue
        
        captureDevice = inputDevice
        captureDeviceResolution = resolution
    }
    
    // Designate preview layer to show video output
    private func designatePreviewLayer(for captureSession: AVCaptureSession) {
        
        let videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer = videoPreviewLayer
        
        videoPreviewLayer.name = "CameraPreviewLayer"
        videoPreviewLayer.backgroundColor = UIColor.black.cgColor
        videoPreviewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        
        if let previewRootLayer = cameraPreviewView?.layer {
            rootLayer = previewRootLayer
            
            previewRootLayer.masksToBounds = true
            videoPreviewLayer.frame = previewRootLayer.bounds
            previewRootLayer.addSublayer(videoPreviewLayer)
        }
    }
    
    // Tear down AVCapture and remove previewlayer
    private func teardownAVCapture() {
        
        videoDataOutput = nil
        videoDataOutputQueue = nil
        
        if let previewLayer = previewLayer {
            previewLayer.removeFromSuperlayer()
            self.previewLayer = nil
        }
    }
}

//MARK: - Perfrom Vision requests
extension FaceEffectsViewController {
    
    private func preapareVisionRequest() {
        
        var requests = [VNTrackObjectRequest]()
        
        let faceDetectionRequest = VNDetectFaceRectanglesRequest(completionHandler: { [weak self] (request, error) in
            
            if error != nil {
                print("FaceDetection error: \(String(describing: error)).")
            }
            
            guard let faceDetectionRequest = request as? VNDetectFaceRectanglesRequest,
                  let results = faceDetectionRequest.results else {
                      return
                  }
            
            DispatchQueue.main.async {
                
                for observation in results {
                    let faceTrackingRequest = VNTrackObjectRequest(detectedObjectObservation: observation)
                    requests.append(faceTrackingRequest)
                }
                self?.trackingRequests = requests
            }
        })
        
        // Start with face detection
        detectionRequests = [faceDetectionRequest]
        
        sequenceRequestHandler = VNSequenceRequestHandler()
        
        setupVisionDrawingLayers()
    }
}

//MARK: - Draw Layers
extension FaceEffectsViewController {
    
    private func setupVisionDrawingLayers() {
        
        let captureDeviceResolution = captureDeviceResolution
        
        let captureDeviceBounds = CGRect(x: 0,
                                         y: 0,
                                         width: captureDeviceResolution.width,
                                         height: captureDeviceResolution.height)
        
        let captureDeviceBoundsCenterPoint = CGPoint(x: captureDeviceBounds.midX,
                                                     y: captureDeviceBounds.midY)
        
        let normalizedCenterPoint = CGPoint(x: 0.5, y: 0.5)
        
        guard let rootLayer = self.rootLayer else {
            presentErrorAlert(message: "view was not property initialized")
            return
        }
        
        let overlayLayer = CALayer()
        overlayLayer.name = "DetectionOverlay"
        overlayLayer.masksToBounds = true
        overlayLayer.anchorPoint = normalizedCenterPoint
        overlayLayer.bounds = captureDeviceBounds
        overlayLayer.position = CGPoint(x: rootLayer.bounds.midX, y: rootLayer.bounds.midY)
        
        let faceLandmarksShapeLayer = createShapeLayer(name: "FaceLandmarksLayer", bounds: captureDeviceBounds, anchorPoint: normalizedCenterPoint, position: captureDeviceBoundsCenterPoint, fillColor: nil, strokeColor: UIColor.red, lineWidth: 3)
        
        let faceRectangleShapeLayer = createShapeLayer(name: "RectangleOutlineLayer", bounds: captureDeviceBounds, anchorPoint: normalizedCenterPoint, position: captureDeviceBoundsCenterPoint, fillColor: nil, strokeColor: .clear, lineWidth: 3)
        
        let eyebrowsLayer = createShapeLayer(name: "EyebrowsLayer", bounds: captureDeviceBounds, anchorPoint: normalizedCenterPoint, position: captureDeviceBoundsCenterPoint, fillColor: .orange, strokeColor: .clear, lineWidth: 3)
        
        let lipsLayer = createShapeLayer(name: "LipsLayer", bounds: captureDeviceBounds, anchorPoint: normalizedCenterPoint, position: captureDeviceBoundsCenterPoint, fillColor: .clear, strokeColor: .systemPink, lineWidth: 30)
        
        let toungeLayer = createShapeLayer(name: "ToungeLayer", bounds: captureDeviceBounds, anchorPoint: normalizedCenterPoint, position: captureDeviceBoundsCenterPoint, fillColor: .white, strokeColor: .clear, lineWidth: 3)
        
        overlayLayer.addSublayer(faceRectangleShapeLayer)
        faceRectangleShapeLayer.addSublayer(faceLandmarksShapeLayer)
        faceLandmarksShapeLayer.addSublayer(eyebrowsLayer)
        faceLandmarksShapeLayer.addSublayer(lipsLayer)
        faceLandmarksShapeLayer.addSublayer(toungeLayer)
        rootLayer.addSublayer(overlayLayer)
        
        detectionOverlayLayer = overlayLayer
        detectedFaceRectangleShapeLayer = faceRectangleShapeLayer
        detectedFaceLandmarksShapeLayer = faceLandmarksShapeLayer
        detectedEyeBrowLayers = eyebrowsLayer
        detectedLipsLayer = lipsLayer
        
        updateLayerGeometry()
    }
    
    private func createShapeLayer(name: String, bounds: CGRect, anchorPoint: CGPoint, position: CGPoint, fillColor: UIColor?, strokeColor: UIColor, lineWidth: CGFloat) -> CAShapeLayer {
        
        let shapeLayer = CAShapeLayer()
        shapeLayer.name = name
        shapeLayer.bounds = bounds
        shapeLayer.anchorPoint = anchorPoint
        shapeLayer.position = position
        shapeLayer.fillColor = fillColor?.cgColor
        shapeLayer.strokeColor = strokeColor.cgColor
        shapeLayer.lineWidth = lineWidth
        shapeLayer.shadowOpacity = 0.7
        shapeLayer.shadowRadius = 5
        
        return shapeLayer
    }
    
    // Update layer Geometry
    private func updateLayerGeometry() {
        
        guard let overlayLayer = detectionOverlayLayer,
              let rootLayer = self.rootLayer,
              let previewLayer = self.previewLayer
        else { return }
        
        CATransaction.setValue(NSNumber(value: true), forKey: kCATransactionDisableActions)
        
        let videoPreviewRect = previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        
        var rotation: CGFloat
        var scaleX: CGFloat
        var scaleY: CGFloat
        
        // Rotate the layer into screen orientation.
        switch UIDevice.current.orientation {
        case .portraitUpsideDown:
            rotation = 180
            scaleX = videoPreviewRect.width / captureDeviceResolution.width
            scaleY = videoPreviewRect.height / captureDeviceResolution.height
            
        case .landscapeLeft:
            rotation = 90
            scaleX = videoPreviewRect.height / captureDeviceResolution.width
            scaleY = scaleX
            
        case .landscapeRight:
            rotation = -90
            scaleX = videoPreviewRect.height / captureDeviceResolution.width
            scaleY = scaleX
            
        default:
            rotation = 0
            scaleX = videoPreviewRect.width / captureDeviceResolution.width
            scaleY = videoPreviewRect.height / captureDeviceResolution.height
        }
        
        // Scale and mirror the image to ensure upright presentation.
        let affineTransform = CGAffineTransform(rotationAngle: radiansForDegrees(rotation))
            .scaledBy(x: scaleX, y: -scaleY)
        overlayLayer.setAffineTransform(affineTransform)
        
        // Cover entire screen UI.
        let rootLayerBounds = rootLayer.bounds
        overlayLayer.position = CGPoint(x: rootLayerBounds.midX, y: rootLayerBounds.midY)
    }
    
    // Draw Paths
    private func drawFaceObservations(_ faceObservations: [VNFaceObservation]) {
        
        guard let faceLandmarksShapeLayer = detectedFaceLandmarksShapeLayer,
              let faceRectengalgeShapeLayer = detectedFaceRectangleShapeLayer,
              let eyebrowsLayer = detectedEyeBrowLayers,
              let lipsLayer = detectedLipsLayer else { return }
        
        CATransaction.begin()
        CATransaction.setValue(NSNumber(value: true), forKey: kCATransactionDisableActions)
        
        let faceRectengalgePath = CGMutablePath()
        let faceLandmarksPath = CGMutablePath()
        let eyebrowsPath = CGMutablePath()
        let lipsPath = CGMutablePath()
        
        for faceObservation in faceObservations {
            addFaceLandmarks(faceLandmarksPath: faceLandmarksPath, faceRectanglePath: faceRectengalgePath, lipsPath: lipsPath, eyebrowsPath: eyebrowsPath, for: faceObservation)
        }
        
        faceRectengalgeShapeLayer.path = faceRectengalgePath
        faceLandmarksShapeLayer.path = faceLandmarksPath
        eyebrowsLayer.path = eyebrowsPath
        lipsLayer.path = lipsPath
        
        updateLayerGeometry()
        
        CATransaction.commit()
    }
    
    // Get face landmarks
    private func addFaceLandmarks(faceLandmarksPath: CGMutablePath, faceRectanglePath: CGMutablePath, lipsPath: CGMutablePath, eyebrowsPath: CGMutablePath, for faceObservation: VNFaceObservation) {
        
        let displaySize = captureDeviceResolution
        
        let faceBounds = VNImageRectForNormalizedRect(faceObservation.boundingBox, Int(displaySize.width), Int(displaySize.height))
        faceRectanglePath.addRect(faceBounds)
        
        if showEmoji {
            
            maskStackView.isHidden = false
            faceRect = faceObservation.boundingBox
            addEmoji(faceRect: faceRect, emojiString: emojis[emojiIndex])
            
        } else {
            
            maskStackView.isHidden = true
            maskImgView.image = UIImage()
            
            if let landmarks = faceObservation.landmarks {
                // Landmarks are relative to -- and normalized within --- face bounds
                let affineTransform = CGAffineTransform(translationX: faceBounds.origin.x, y: faceBounds.origin.y)
                    .scaledBy(x: faceBounds.size.width, y: faceBounds.size.height)
                
                // Draw eyebrows.
                let eyebrowLandmarkRegions: [VNFaceLandmarkRegion2D?] = [
                    landmarks.leftEyebrow,
                    landmarks.rightEyebrow]
                
                for eyebrowLandmarkRegion in eyebrowLandmarkRegions where eyebrowLandmarkRegion != nil {
                    addPoints(in: eyebrowLandmarkRegion!, to: eyebrowsPath, applying: affineTransform, closingWhenComplete: false)
                }
                
                // Draw eyes and nose.
                let closedLandmarkRegions: [VNFaceLandmarkRegion2D?] = [
                    landmarks.leftEye,
                    landmarks.rightEye,
                    landmarks.nose]
                
                for closedLandmarkRegion in closedLandmarkRegions where closedLandmarkRegion != nil {
                    addPoints(in: closedLandmarkRegion!, to: faceLandmarksPath, applying: affineTransform, closingWhenComplete: true)
                }
                
                // Draw lips.
                let lipsLandmarkRegions: [VNFaceLandmarkRegion2D?] = [landmarks.outerLips]
                
                for lipsLandmarkRegion in lipsLandmarkRegions where lipsLandmarkRegion != nil {
                    addPoints(in: lipsLandmarkRegion!, to: lipsPath, applying: affineTransform, closingWhenComplete: true)
                }
            }
        }
    }
    
    private func addEmoji(faceRect: CGRect, emojiString: String) {
        
        let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -view.frame.height)
        let translate = CGAffineTransform.identity.scaledBy(x: view.frame.width, y: view.frame.height)
        
        let facebounds = faceRect.applying(translate).applying(transform)
        
        maskImgView.frame.size = CGSize(width: facebounds.size.width * 2.6, height: facebounds.size.width * 2.6)
        maskImgView.center = CGPoint(x: facebounds.midX, y: facebounds.midY - 10)
        maskImgView.image = emojiString.convertStringToImage()
        maskImgView.contentMode = .scaleToFill
        view.addSubview(maskImgView)
    }
    
    // Add landmark points
    private func addPoints(in landmarkRegion: VNFaceLandmarkRegion2D, to path: CGMutablePath, applying affineTransform: CGAffineTransform, closingWhenComplete closePath: Bool) {
        
        let pointCount = landmarkRegion.pointCount
        
        if pointCount > 1 {
            
            let points: [CGPoint] = landmarkRegion.normalizedPoints
            path.move(to: points[0], transform: affineTransform)
            path.addLines(between: points, transform: affineTransform)
            
            if closePath {
                
                path.addLine(to: points[0], transform: affineTransform)
                path.closeSubpath()
            }
        }
    }
}

//MARK: - AVCaptureVideoDataOutputSampleBuffer Delegate
extension FaceEffectsViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        var requestHandlerOptions: [VNImageOption: AnyObject] = [:]
        
        let cameraIntrinsicData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil)
        if cameraIntrinsicData != nil {
            requestHandlerOptions[VNImageOption.cameraIntrinsics] = cameraIntrinsicData
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to obtain a CVPixelBuffer for the current output frame.")
            return
        }
        
        let exifOrientation = exifOrientationForCurrentDeviceOrientation()
        
        guard let requests = trackingRequests, !requests.isEmpty else {
            // No tracking object detected, so perform initial detection
            let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                            orientation: exifOrientation,
                                                            options: requestHandlerOptions)
            
            do {
                guard let detectRequests = detectionRequests else {
                    return
                }
                try imageRequestHandler.perform(detectRequests)
            } catch let error as NSError {
                NSLog("Failed to perform FaceRectangleRequest: %@", error)
            }
            return
        }
        
        do {
            try sequenceRequestHandler.perform(requests,
                                                    on: pixelBuffer,
                                                    orientation: exifOrientation)
        } catch let error as NSError {
            NSLog("Failed to perform SequenceRequest: %@", error)
        }
        
        // Setup the next round of tracking.
        var newTrackingRequests = [VNTrackObjectRequest]()
        for trackingRequest in requests {
            
            guard let results = trackingRequest.results else {
                return
            }
            
            guard let observation = results[0] as? VNDetectedObjectObservation else {
                return
            }
            
            if !trackingRequest.isLastFrame {
                if observation.confidence > 0.3 {
                    trackingRequest.inputObservation = observation
                } else {
                    trackingRequest.isLastFrame = true
                }
                newTrackingRequests.append(trackingRequest)
            }
        }
        trackingRequests = newTrackingRequests
        
        if newTrackingRequests.isEmpty {
            // Nothing to track, so abort.
            return
        }
        
        // Perform face landmark tracking on detected faces.
        var faceLandmarkRequests = [VNDetectFaceLandmarksRequest]()
        
        // Perform landmark detection on tracked faces.
        for trackingRequest in newTrackingRequests {
            
            let faceLandmarksRequest = VNDetectFaceLandmarksRequest(completionHandler: { [weak self] (request, error) in
                
                if error != nil {
                    print("FaceLandmarks error: \(String(describing: error)).")
                }
                
                guard let landmarksRequest = request as? VNDetectFaceLandmarksRequest,
                      let results = landmarksRequest.results else {
                          return
                      }
                
                DispatchQueue.main.async {
                    self?.drawFaceObservations(results)
                }
            })
            
            guard let trackingResults = trackingRequest.results else {
                return
            }
            
            guard let observation = trackingResults[0] as? VNDetectedObjectObservation else {
                return
            }
            let faceObservation = VNFaceObservation(boundingBox: observation.boundingBox)
            faceLandmarksRequest.inputFaceObservations = [faceObservation]
            
            // Continue to track detected facial landmarks.
            faceLandmarkRequests.append(faceLandmarksRequest)
            
            let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                            orientation: exifOrientation,
                                                            options: requestHandlerOptions)
            
            do {
                try imageRequestHandler.perform(faceLandmarkRequests)
            } catch let error as NSError {
                NSLog("Failed to perform FaceLandmarkRequest: %@", error)
            }
        }
    }
}

//MARK: - IBActions
extension FaceEffectsViewController {
    
    @IBAction func obnMask1Tapped(_ sender: UIButton) {
        
        emojiIndex = 0
        addEmoji(faceRect: faceRect, emojiString: emojis[0])
    }
    
    @IBAction func onMask2Tapped(_ sender: UIButton) {
        
        emojiIndex = 1
        addEmoji(faceRect: faceRect, emojiString: emojis[1])
    }
    
    @IBAction func onMask3Tapped(_ sender: UIButton) {
        
        emojiIndex = 2
        addEmoji(faceRect: faceRect, emojiString: emojis[2])
    }
}

//MARK: - Helper methods
extension FaceEffectsViewController {
    
    private func presentErrorAlert(withTitle title: String = "Unexpected Failure", message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        present(alertController, animated: true)
    }
    
    private func presentError(_ error: NSError) {
        presentErrorAlert(withTitle: "Failed with error \(error.code)", message: error.localizedDescription)
    }
    
    private func radiansForDegrees(_ degrees: CGFloat) -> CGFloat {
        return CGFloat(Double(degrees) * Double.pi / 180.0)
    }
    
    private func exifOrientationForDeviceOrientation(_ deviceOrientation: UIDeviceOrientation) -> CGImagePropertyOrientation {
        
        switch deviceOrientation {
        case .portraitUpsideDown:
            return .rightMirrored
            
        case .landscapeLeft:
            return .downMirrored
            
        case .landscapeRight:
            return .upMirrored
            
        default:
            return .leftMirrored
        }
    }
    
    private func exifOrientationForCurrentDeviceOrientation() -> CGImagePropertyOrientation {
        return exifOrientationForDeviceOrientation(UIDevice.current.orientation)
    }
}
