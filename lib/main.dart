import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

import 'package:uuid/uuid.dart';

class CameraScreen extends StatefulWidget {
  @override
  _CameraScreenState createState() {
    return _CameraScreenState();
  }
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? controller;
  String? imagePath;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    controller = CameraController(cameras[0], ResolutionPreset.medium);
    controller!.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Flutter Vision'),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Container(
              child: Padding(
                padding: const EdgeInsets.all(1.0),
                child: Center(
                  child: _cameraPreviewWidget(),
                ),
              ),
            ),
          ),
          _captureControlRowWidget(),
        ],
      ),
    );
  }

  /// Display the preview from the camera (or a message if the preview is not available).
  Widget _cameraPreviewWidget() {
    if (controller == null || !controller!.value.isInitialized) {
      return const Text(
        'Tap a camera',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24.0,
          fontWeight: FontWeight.w900,
        ),
      );
    } else {
      return AspectRatio(
        aspectRatio: controller!.value.aspectRatio,
        child: CameraPreview(controller!),
      );
    }
  }

  /// Display the control bar with buttons to take pictures.
  Widget _captureControlRowWidget() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      mainAxisSize: MainAxisSize.max,
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.camera_alt),
          color: Colors.blue,
          onPressed: controller != null && controller!.value.isInitialized
              ? onTakePictureButtonPressed
              : null,
        )
      ],
    );
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void showInSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void onTakePictureButtonPressed() {
    takePicture().then((String? filePath) {
      if (mounted) {
        setState(() {
          imagePath = filePath;
        });
        if (filePath != null) {
          detectLabels().then((_) {});
        }
      }
    });
  }

  Future<void> detectLabels() async {
    final InputImage inputImage = InputImage.fromFilePath(imagePath!);
    final ImageLabelerOptions options =
        ImageLabelerOptions(confidenceThreshold: 0.5);
    final imageLabeler = ImageLabeler(options: options);

    final List<ImageLabel> labels = await imageLabeler.processImage(inputImage);

    List<String?> labelTexts = <String?>[];
    for (ImageLabel label in labels) {
      final String? text = label.label;

      labelTexts.add(text);
    }

    imageLabeler.close();

    final String uuid = Uuid().v1();
    final String downloadURL = await _uploadFile(uuid);

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ItemsListScreen()),
    );

    await _addItem(downloadURL, labelTexts);
  }

  Future<void> _addItem(String downloadURL, List<String?> labels) async {
    await FirebaseFirestore.instance
        .collection('items')
        .add(<String, dynamic>{'downloadURL': downloadURL, 'labels': labels});
  }

  Future<String> _uploadFile(filename) async {
    final File file = File(imagePath!);
    final firebase_storage.Reference ref =
        firebase_storage.FirebaseStorage.instance.ref().child('$filename.jpg');
    final firebase_storage.UploadTask uploadTask = ref.putFile(
      file,
      firebase_storage.SettableMetadata(
        contentLanguage: 'en',
      ),
    );

    firebase_storage.TaskSnapshot snapshot = await uploadTask;
    final downloadURL = await snapshot.ref.getDownloadURL();
    return downloadURL;
  }

  Future<String?> takePicture() async {
    if (!controller!.value.isInitialized) {
      showInSnackBar('Please select a camera first');
      return null;
    }

    XFile imageFile;

    if (controller!.value.isTakingPicture) {
      // A capture is already pending, do nothing.
      return null;
    }

    try {
      imageFile = await controller!.takePicture();
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }

    return imageFile.path;
  }

  void _showCameraException(CameraException e) {
    logError(e.code, e.description);
    showInSnackBar('Error: ${e.code}\n${e.description}');
  }
}

late List<CameraDescription> cameras;

class ItemsListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Items'),
      ),
      body: ItemsList(firestore: FirebaseFirestore.instance),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => CameraScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class ItemsList extends StatelessWidget {
  ItemsList({this.firestore});

  final FirebaseFirestore? firestore;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore!.collection('items').snapshots(),
      builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (!snapshot.hasData) return const Text('Loading...');
        final int itemsCount = snapshot.data!.docs.length;
        return ListView.builder(
          itemCount: itemsCount,
          itemBuilder: (_, int index) {
            final DocumentSnapshot document = snapshot.data!.docs[index];
            return SafeArea(
              top: false,
              bottom: false,
              child: Container(
                padding: const EdgeInsets.all(8.0),
                height: 310.0,
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16.0),
                      topRight: Radius.circular(16.0),
                      bottomLeft: Radius.circular(16.0),
                      bottomRight: Radius.circular(16.0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // photo and title
                      SizedBox(
                        height: 184.0,
                        child: Stack(
                          children: <Widget>[
                            Positioned.fill(
                              child: Image.network(document['downloadURL']),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding:
                              const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0.0),
                          child: DefaultTextStyle(
                            softWrap: true,
                            //overflow: TextOverflow.,
                            style: Theme.of(context).textTheme.subtitle1!,
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(document['labels'].join(', ')),
                                ]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class FlutterVisionApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ItemsListScreen(),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Fetch the available cameras before initializing the app.
  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    logError(e.code, e.description);
  }
  runApp(FlutterVisionApp());
}

void logError(String code, String? message) =>
    print('Error: $code\nError Message: $message');
