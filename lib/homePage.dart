// ignore: file_names
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wakelock/wakelock.dart';

import 'chart.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  HomePageView createState() {
    return HomePageView();
  }
}

class HomePageView extends State<HomePage> with SingleTickerProviderStateMixin {
  bool _toggled = false; // toggle button value
  final List<SensorValue> _data = []; // array to store the values
  late CameraController _controller;
  final double _alpha = 0.3; // factor for the mean value
  late AnimationController _animationController;
  double _iconScale = 1;
  var _bpm = 0; // beats per minute
  final int _fs = 30; // sampling frequency (fps)
  final int _windowLen = 30 * 6; // window length to display - 6 seconds
// store the last camera image
  late double _avg; // store the average value during calculation
  //DateTime _now = new DateTime.now();
  Timer? _timer; // timer for image processing

  @override
  void initState() {
    super.initState();
    _animationController =
        AnimationController(duration: const Duration(milliseconds: 500), vsync: this);
    _animationController
      .addListener(() {
        setState(() => _iconScale = 1.0 + _animationController.value * 0.4);
      });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _toggled = false;
    _disposeController();
    Wakelock.disable();
    _animationController.stop();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
                flex: 1,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Expanded(
                      flex: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(18),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            alignment: Alignment.center,
                            children: <Widget>[
                              _toggled
                                  ? AspectRatio(
                                      aspectRatio:
                                          _controller.value.aspectRatio,
                                      child: CameraPreview(_controller),
                                    )
                                  : Container(
                                      padding: const EdgeInsets.all(12),
                                      alignment: Alignment.center,
                                      color: Colors.grey,
                                    ),
                              Container(
                                alignment: Alignment.center,
                                padding: const EdgeInsets.all(4),
                                child: Text(
                                  _toggled
                                      ? "Cover both the camera and the flash with your finger"
                                      : "Camera feed will display here",
                                  style: TextStyle(
                                      backgroundColor: _toggled
                                          ? Colors.white
                                          : Colors.transparent),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Center(
                          child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          const Text(
                            "Estimated BPM",
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          Text(
                            ( _bpm.toString()),
                            style: const TextStyle(
                                fontSize: 32, fontWeight: FontWeight.bold),
                          ),
                        ],
                      )),
                    ),
                  ],
                )),
            Expanded(
              flex: 1,
              child: Center(
                child: Transform.scale(
                  scale: _iconScale,
                  child: IconButton(
                    icon:
                        Icon(_toggled ? Icons.favorite : Icons.favorite_border),
                    color: Colors.red,
                    iconSize: 128,
                    onPressed: () {
                      if (_toggled) {
                        _untoggle();
                      } else {
                        _toggle();
                      }
                    },
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Container(
                margin: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                    borderRadius: BorderRadius.all(
                      Radius.circular(18),
                    ),
                    color: Colors.black),
                child: Chart(_data),
              ),
            ),
          ],
        ),
      ),
    );
  }


  void _toggle() {
    if (kDebugMode) {
      print("_toggle");
    }
    _clearData();
    _initController().then((onValue) {
      Wakelock.enable();
      _animationController.repeat(reverse: true);
      setState(() {
        _toggled = true;
      });
      _initTimer();
      _updateBPM();
    });
  }



  void _untoggle() {
    if (kDebugMode) {
      print("_untoggle");
    }
    _controller.stopImageStream();
    _controller.setFlashMode(FlashMode.off);
    Wakelock.disable();
    _animationController.stop();
    _animationController.value = 0.0;
    setState(() {
      _toggled = false;
    });
  }

  void _clearData() {
    // create array of 128 ~= 255/2
    if (kDebugMode) {
      print("clearData");
    }
    _data.clear();
    int now = DateTime.now().millisecondsSinceEpoch;
    for (int i = 0; i < _windowLen; i++) {
      _data.insert(
          0,
          SensorValue(
              (now - i * 1000 ~/ _fs), 128));
    }
  }

  Future<void> _initController() async {
    if (kDebugMode) {
      print("initController");
    }
    try {
      List cameras = await availableCameras();
      _controller = CameraController(cameras.first, ResolutionPreset.low);
      await _controller.initialize();

      Future.delayed(const Duration(milliseconds: 100)).then((onValue) {
        if (kDebugMode) {
          print("Flash turned on");
        }
        _controller.setFlashMode(FlashMode.torch);
      });


      _controller.startImageStream((CameraImage image) {
        if (kDebugMode) {
          print("image");
        }
        _scanImage(image);
      });
    } on Exception {
      debugPrint(Exception as String?);
    }
  }

  void _scanImage(CameraImage image) {
    int now = DateTime.now().millisecondsSinceEpoch;
    _avg =
        image.planes.first.bytes.reduce((value, element) => value + element) /
            image.planes.first.bytes.length;
    if (_data.length >= _windowLen) {
      _data.removeAt(0);
    }
    setState(() {
      _data.add(SensorValue(now, 255 - _avg));
    });
  }

  void _disposeController() {
    _controller.dispose();
  }


  void _initTimer() {
    if (kDebugMode) {
      print("initTimer");
    }
    _timer = Timer.periodic(Duration(milliseconds: 1000 ~/ _fs), (timer) {
      if (_toggled) {
      } else {
        _timer?.cancel();
      }
    });
  }

  void _updateBPM() async {
    if (kDebugMode) {
      print("updateBPM");
    }
    // Bear in mind that the method used to calculate the BPM is very rudimentar
    // feel free to improve it :)

    // Since this function doesn't need to be so "exact" regarding the time it executes,
    // I only used the a Future.delay to repeat it from time to time.
    // Ofc you can also use a Timer object to time the callback of this function
    List<SensorValue> values;
    double avg;
    int n;
    double m;
    double threshold;
    double bpm;
    int counter = 0;
    int previous;
    while (_toggled) {
      values = List.from(_data); // create a copy of the current data array
      avg = 0;
      n = values.length;
      m = 0;
      for (SensorValue value in values) {
        avg += value.value / n;
        if (value.value > m) m = value.value;
      }
      threshold = (m + avg) / 2;
      bpm = 0;
      previous = 0;
      for (int i = 1; i < n; i++) {
        if (values[i - 1].value < threshold &&
            values[i].value > threshold) {
          if (previous != 0) {
            counter++;
            bpm += 60 *
                1000 /
                (values[i].time - previous);
          }
          previous = values[i].time;
        }
      }
      if (counter > 0) {
        bpm = bpm / counter;
        if (kDebugMode) {
          print(bpm);
        }
        setState(() {
          _bpm = ((1 - _alpha) * _bpm + _alpha * bpm).toInt();
        });
      }
      await Future.delayed(Duration(
          milliseconds:
              1000 * _windowLen ~/ _fs)); // wait for a new set of _data values
    }
  }
}
