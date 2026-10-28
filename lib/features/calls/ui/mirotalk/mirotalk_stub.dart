import 'package:flutter/material.dart';

Widget buildMirotalkView({
  required String roomId,
  required String userName,
  required VoidCallback onClosed,
  String? mirotalkUrl,
  bool isHost = false,
  VoidCallback? onEndMeeting,
}) {
  return const Scaffold(
    body: Center(
      child: CircularProgressIndicator(),
    ),
  );
}

Future<void> joinMirotalkNative({
  required String roomId,
  required String userName,
  required VoidCallback onClosed,
  String? mirotalkUrl,
}) async {
  throw UnsupportedError('Use buildMirotalkView');
}
