import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';

class NetworkService {
  static final NetworkService _instance = NetworkService._();
  NetworkService._();
  factory NetworkService() => _instance;

  // Stream of real internet status
  Stream<bool> get onStatusChange {
    StreamController<bool> controller = StreamController.broadcast();

    Timer? timer;
    StreamSubscription? sub;

    controller.onListen = () {
      bool useTimerOnly = false;
      try {
        if (!kIsWeb && Platform.isWindows) {
          useTimerOnly = true;
        }
      } catch (_) {
        // Platform check might fail on some environments
      }

      if (useTimerOnly) {
        timer = Timer.periodic(const Duration(seconds: 10), (t) async {
          if (!controller.isClosed) {
            controller.add(await InternetConnectionChecker().hasConnection);
          }
        });
        InternetConnectionChecker().hasConnection.then((v) {
          if (!controller.isClosed) controller.add(v);
        });
      } else {
        try {
          sub = Connectivity().onConnectivityChanged.listen(
            (_) async {
              if (!controller.isClosed) {
                controller.add(await InternetConnectionChecker().hasConnection);
              }
            },
            onError: (e) {
              timer ??= Timer.periodic(const Duration(seconds: 10), (t) async {
                  if (!controller.isClosed) {
                    controller.add(await InternetConnectionChecker().hasConnection);
                  }
                });
            },
          );
        } catch (e) {
          timer = Timer.periodic(const Duration(seconds: 10), (t) async {
            if (!controller.isClosed) {
              controller.add(await InternetConnectionChecker().hasConnection);
            }
          });
          InternetConnectionChecker().hasConnection.then((v) {
            if (!controller.isClosed) controller.add(v);
          });
        }
      }
    };

    controller.onCancel = () {
      sub?.cancel();
      timer?.cancel();
    };

    return controller.stream;
  }

  Future<bool> get isOnline async {
    return await InternetConnectionChecker().hasConnection;
  }
}
