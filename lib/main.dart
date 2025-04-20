import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_app/PoseFilterScreen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  
  const MyApp({Key? key, required this.cameras}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'تطبيق تتبع الوضعية',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: PoseFilterScreen(cameras: cameras),
    );
  }
}