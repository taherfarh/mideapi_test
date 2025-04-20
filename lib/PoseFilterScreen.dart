import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';

class PoseFilterScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  
  const PoseFilterScreen({Key? key, required this.cameras}) : super(key: key);
  
  @override
  _PoseFilterScreenState createState() => _PoseFilterScreenState();
}

class _PoseFilterScreenState extends State<PoseFilterScreen> {
  CameraController? _controller;
  PoseDetector? _poseDetector;
  List<Pose> _poses = [];
  bool _isProcessing = false;
  
  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
    _initializePoseDetector();
  }
  
  void _initializePoseDetector() {
    final options = PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.accurate,
    );
    _poseDetector = PoseDetector(options: options);
  }
  
  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      _initializeCamera();
    } else {
      print('Camera permission denied');
    }
  }
  
  Future<void> _initializeCamera() async {
    final camera = widget.cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );
    
    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    
    try {
      await _controller!.initialize();
      _controller!.startImageStream(_processCameraImage);
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }
  
  void _processCameraImage(CameraImage image) async {
    if (_isProcessing || _poseDetector == null) return;
    
    _isProcessing = true;
    
    try {
      final inputImage = _convertCameraImageToInputImage(image);
      if (inputImage != null) {
        final poses = await _poseDetector!.processImage(inputImage);
        
        if (mounted) {
          setState(() {
            _poses = poses;
          });
        }
      }
    } catch (e) {
      print('Error processing image: $e');
    } finally {
      _isProcessing = false;
    }
  }
  
  InputImage? _convertCameraImageToInputImage(CameraImage image) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();
      
      final camera = widget.cameras.firstWhere(
        (element) => element.lensDirection == CameraLensDirection.front,
        orElse: () => widget.cameras.first,
      );
      
      final imageRotation = InputImageRotationValue.fromRawValue(
        camera.sensorOrientation,
      ) ?? InputImageRotation.rotation0deg;
      
      final inputImageFormat = InputImageFormatValue.fromRawValue(
        image.format.raw,
      ) ?? InputImageFormat.nv21;
      
      // استخدام بيانات الصورة مباشرةً بدون InputImagePlaneMetadata
      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: imageRotation,
          format: inputImageFormat,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
      
      return inputImage;
    } catch (e) {
      print('Error converting camera image: $e');
      return null;
    }
  }
  
  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _poseDetector?.close();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Pose Filter'),
      ),
      body: Stack(
        children: [
          CameraPreview(_controller!),
          
          CustomPaint(
            painter: PoseOverlayPainter(
              poses: _poses,
              cameraSize: _controller!.value.previewSize!,
              canvasSize: MediaQuery.of(context).size,
            ),
            size: Size.infinite,
          ),
          
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black54,
              padding: EdgeInsets.all(8),
              child: Text(
                'Detected Poses: ${_poses.length}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// CustomPainter لرسم الوضعية
class PoseOverlayPainter extends CustomPainter {
  final List<Pose> poses;
  final Size cameraSize;
  final Size canvasSize;
  
  PoseOverlayPainter({
    required this.poses,
    required this.cameraSize,
    required this.canvasSize,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..color = Colors.green;
      
    final jointPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.red;
    
    for (final pose in poses) {
      _drawPose(canvas, pose, jointPaint, paint);
    }
  }
  
  void _drawPose(Canvas canvas, Pose pose, Paint jointPaint, Paint linePaint) {
    // رسم الخطوط بين النقاط المرجعية
    void drawLine(PoseLandmarkType type1, PoseLandmarkType type2) {
      final landmark1 = pose.landmarks[type1];
      final landmark2 = pose.landmarks[type2];
      
      if (landmark1 != null && landmark2 != null) {
        canvas.drawLine(
          Offset(landmark1.x, landmark1.y),
          Offset(landmark2.x, landmark2.y),
          linePaint,
        );
      }
    }
    
    // رسم النقاط المرجعية
    pose.landmarks.forEach((type, landmark) {
      canvas.drawCircle(
        Offset(landmark.x, landmark.y),
        8,
        jointPaint,
      );
    });
    
    // رسم هيكل الجسم
    // الرأس والرقبة
    drawLine(PoseLandmarkType.nose, PoseLandmarkType.leftEyeInner);
    drawLine(PoseLandmarkType.leftEyeInner, PoseLandmarkType.leftEye);
    drawLine(PoseLandmarkType.leftEye, PoseLandmarkType.leftEyeOuter);
    drawLine(PoseLandmarkType.nose, PoseLandmarkType.rightEyeInner);
    drawLine(PoseLandmarkType.rightEyeInner, PoseLandmarkType.rightEye);
    drawLine(PoseLandmarkType.rightEye, PoseLandmarkType.rightEyeOuter);
    drawLine(PoseLandmarkType.nose, PoseLandmarkType.leftMouth);
    drawLine(PoseLandmarkType.leftMouth, PoseLandmarkType.rightMouth);
    drawLine(PoseLandmarkType.nose, PoseLandmarkType.rightMouth);
    
    // الكتفان
    drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
    
    // الجذع
    drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip);
    drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip);
    drawLine(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip);
    
    // الذراع الأيسر
    drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow);
    drawLine(PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist);
    drawLine(PoseLandmarkType.leftWrist, PoseLandmarkType.leftThumb);
    drawLine(PoseLandmarkType.leftWrist, PoseLandmarkType.leftIndex);
    drawLine(PoseLandmarkType.leftWrist, PoseLandmarkType.leftPinky);
    
    // الذراع الأيمن
    drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow);
    drawLine(PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist);
    drawLine(PoseLandmarkType.rightWrist, PoseLandmarkType.rightThumb);
    drawLine(PoseLandmarkType.rightWrist, PoseLandmarkType.rightIndex);
    drawLine(PoseLandmarkType.rightWrist, PoseLandmarkType.rightPinky);
    
    // الساق اليسرى
    drawLine(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee);
    drawLine(PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle);
    drawLine(PoseLandmarkType.leftAnkle, PoseLandmarkType.leftHeel);
    drawLine(PoseLandmarkType.leftAnkle, PoseLandmarkType.leftFootIndex);
    
    // الساق اليمنى
    drawLine(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee);
    drawLine(PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle);
    drawLine(PoseLandmarkType.rightAnkle, PoseLandmarkType.rightHeel);
    drawLine(PoseLandmarkType.rightAnkle, PoseLandmarkType.rightFootIndex);
  }
  
  @override
  bool shouldRepaint(PoseOverlayPainter oldDelegate) {
    return oldDelegate.poses != poses;
  }
}