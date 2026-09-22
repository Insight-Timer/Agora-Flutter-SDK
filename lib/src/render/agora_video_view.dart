import '/src/render/video_view_controller.dart';
import '/src/impl/agora_video_view_impl.dart';

import 'package:flutter/material.dart';

/// The AgoraVideoView class, used to render local and remote video.
class AgoraVideoView extends StatefulWidget {
  /// @nodoc
  const AgoraVideoView({
    Key? key,
    required this.controller,
    this.onAgoraVideoViewCreated,
    this.cornerRadius = 0,
    this.cornerBackgroundColor,
  }) : super(key: key);

  /// Controls the type of video to render:
  ///  To render video from RtcEngine, see VideoViewController.
  ///  To render video from the media player, see MediaPlayerController.
  final VideoViewControllerBase controller;

  /// @nodoc
  final void Function(int viewId)? onAgoraVideoViewCreated;

  /// iOS platform view only: rounds the native view's own corners, so a host can keep a
  /// rectangular Flutter clip around it. A rounded Flutter clip over a platform view
  /// mis-layers the content above it on Flutter 3.47 (flutter/flutter#182662); drop both
  /// corner properties once the app runs on an SDK with that reverted.
  final double cornerRadius;

  /// iOS platform view only: painted a point past the view's frame behind the rounded
  /// corners, since Flutter paints nothing under a platform view. Read at creation.
  final Color? cornerBackgroundColor;

  @override
  State<AgoraVideoView> createState() => AgoraVideoViewState();
}
