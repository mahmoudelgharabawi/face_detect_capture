import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:face_detect_capture/face_detector_painter.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'camera_view.dart';

class FaceDetectorView extends StatefulWidget {
  final Function(Uint8List image) getImage;
  const FaceDetectorView({super.key, required this.getImage});

  @override
  State<FaceDetectorView> createState() => _FaceDetectorViewState();
}

class _FaceDetectorViewState extends State<FaceDetectorView> {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
    ),
  );
  bool _canProcess = true;
  bool _isBusy = false;
  CustomPaint? _customPaint;
  String? _text;

  @override
  void dispose() {
    _canProcess = false;
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 500),
          child: CameraView(
            title: 'Face Detector',
            customPaint: _customPaint,
            text: _text,
            onImage: (inputImage, controller) {
              processImage(inputImage, controller);
            },
            initialDirection: CameraLensDirection.front,
          )),
    );
  }

  Future<void> processImage(
      InputImage inputImage, CameraController controller) async {
    if (!_canProcess) return;
    if (_isBusy) return;
    _isBusy = true;
    setState(() {
      _text = '';
    });
    final faces = await _faceDetector.processImage(inputImage);
    if (inputImage.inputImageData?.size != null &&
        inputImage.inputImageData?.imageRotation != null) {
      final painter = FaceDetectorPainter(
          faces,
          inputImage.inputImageData!.size,
          inputImage.inputImageData!.imageRotation);
      _customPaint = CustomPaint(painter: painter);

      var result = _extractFace(faces);
      if (result.wellPositioned) {
        // to take image here
        print('well Positioned');
        _onTakePictureButtonPressed(controller)
            .then((value) => Navigator.pop(context));
      }
    } else {
      String text = 'Faces found: ${faces.length}\n\n';
      for (final face in faces) {
        text += 'face: ${face.boundingBox}\n\n';
      }
      _text = text;
      // TODO: set _customPaint to draw boundingRect on top of image
      _customPaint = null;
    }
    _isBusy = false;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _onTakePictureButtonPressed(CameraController controller) async {
    try {
      controller.stopImageStream().whenComplete(() async {
        await Future.delayed(const Duration(milliseconds: 500));
        takePicture(controller).then((XFile? file) async {
          /// Return image callback
          if (file != null) {
            var result = await file.readAsBytes();
            widget.getImage.call(result);
          }

          /// Resume image stream after 2 seconds of capture
          // Future.delayed(const Duration(seconds: 2)).whenComplete(() {
          //   if (mounted && cameraController.value.isInitialized) {
          //     try {
          //       _startImageStream();
          //     } catch (e) {
          //       print(e.toString());
          //     }
          //   }
          // });
        });
      });
    } catch (e) {
      print(e.toString());
    }
  }

  Future<XFile?> takePicture(CameraController controller) async {
    if (!controller.value.isInitialized) {
      print('Error: select a camera first.');
      return null;
    }

    if (controller.value.isTakingPicture) {
      // A capture is already pending, do nothing.
      return null;
    }

    try {
      XFile file = await controller.takePicture();
      return file;
    } on CameraException catch (e) {
      print(e);
      return null;
    }
  }

  DetectedFace _extractFace(List<Face> faces) {
    //List<Rect> rect = [];
    bool wellPositioned = faces.isNotEmpty;
    Face? detectedFace;

    for (Face face in faces) {
      // rect.add(face.boundingBox);
      detectedFace = face;

      // Head is rotated to the right rotY degrees
      if (face.headEulerAngleY! > 2 || face.headEulerAngleY! < -2) {
        wellPositioned = false;
      }

      // Head is tilted sideways rotZ degrees
      if (face.headEulerAngleZ! > 2 || face.headEulerAngleZ! < -2) {
        wellPositioned = false;
      }

      // If landmark detection was enabled with FaceDetectorOptions (mouth, ears,
      // eyes, cheeks, and nose available):
      final FaceLandmark? leftEar = face.landmarks[FaceLandmarkType.leftEar];
      final FaceLandmark? rightEar = face.landmarks[FaceLandmarkType.rightEar];
      if (leftEar != null && rightEar != null) {
        if (leftEar.position.y < 0 ||
            leftEar.position.x < 0 ||
            rightEar.position.y < 0 ||
            rightEar.position.x < 0) {
          wellPositioned = false;
        }
      }

      if (face.leftEyeOpenProbability != null) {
        if (face.leftEyeOpenProbability! < 0.5) {
          wellPositioned = false;
        }
      }

      if (face.rightEyeOpenProbability != null) {
        if (face.rightEyeOpenProbability! < 0.5) {
          wellPositioned = false;
        }
      }
    }

    return DetectedFace(wellPositioned: wellPositioned, face: detectedFace);
  }
}

class DetectedFace {
  final Face? face;
  final bool wellPositioned;
  const DetectedFace({required this.face, required this.wellPositioned});

  DetectedFace copyWith({Face? face, bool? wellPositioned}) => DetectedFace(
      face: face ?? this.face,
      wellPositioned: wellPositioned ?? this.wellPositioned);
}
