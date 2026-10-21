import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:mobile_scanner/src/web/media_track_extension.dart';
import 'package:web/web.dart' as web;

export 'package:mobile_scanner/src/web/web_barcode_utils.dart'
    show isInsideScanWindow, mirrorBarcodeX;

/// Returns true if the video stream should be mirrored horizontally.
///
/// Mirrors when facingMode is 'user' (front camera on mobile), or when
/// facingMode is null (desktop cameras mainly face the user).
bool shouldMirrorStream(web.MediaStream? videoStream) {
  final tracks = videoStream?.getVideoTracks().toDart;

  if (tracks == null || tracks.isEmpty) {
    return false;
  }

  final facingMode = tracks.first.getSettings().facingModeNullable?.toDart;

  return facingMode == 'user' || facingMode == null;
}

/// Apply a horizontal CSS mirror transform to [videoElement] if the camera
/// is facing the user.
void maybeFlipVideoPreview(
  web.HTMLVideoElement videoElement,
  web.MediaStream videoStream,
) {
  if (shouldMirrorStream(videoStream)) {
    videoElement.style.transform = 'scaleX(-1)';
  }
}

@JS()
extension type _VideoFrameMetadata._(JSObject _) implements JSObject {
  external double get mediaTime;
}

/// Allows decoding only after playback has presented a new camera frame.
///
/// Completing `video.play()` does not mean the frozen pre-pause pixels have
/// been replaced. Frame callbacks establish that replacement independently.
final class VideoFrameFreshness {
  web.HTMLVideoElement? _video;
  int? _callbackId;
  int _generation = 0;
  double _lastFrameTime = 0;
  bool _freshFrame = false;
  bool _usesFrameCallbacks = false;

  /// Start observing frames, discarding the currently displayed frame.
  void start(web.HTMLVideoElement video) {
    stop();
    _video = video;
    _lastFrameTime = video.currentTime;
    _usesFrameCallbacks = video
        .getProperty<JSAny?>('requestVideoFrameCallback'.toJS)
        .typeofEquals('function');
    if (_usesFrameCallbacks) {
      _requestFrame(video, _generation);
    }
  }

  void _requestFrame(web.HTMLVideoElement video, int generation) {
    _callbackId = video.requestVideoFrameCallback(
      ((double _, _VideoFrameMetadata metadata) {
        if (generation != _generation) return;

        // Safari camera callbacks can report mediaTime=0 indefinitely.
        // Compare currentTime only with its own baseline, never mediaTime.
        if (!video.paused && video.currentTime > _lastFrameTime) {
          _lastFrameTime = video.currentTime;
          _freshFrame = true;
        }
        _requestFrame(video, generation);
      }).toJS,
    );
  }

  /// Consume a fresh frame once, or wait for another frame to arrive.
  bool takeFrame() {
    final video = _video;
    if (video == null || video.paused || video.readyState < 2) return false;
    if (!_usesFrameCallbacks && video.currentTime > _lastFrameTime) {
      _lastFrameTime = video.currentTime;
      return true;
    }
    if (!_freshFrame) return false;
    _freshFrame = false;
    return true;
  }

  /// Invalidate callbacks and any unconsumed frames.
  void stop() {
    _generation++;
    final callbackId = _callbackId;
    if (callbackId != null) {
      _video?.cancelVideoFrameCallback(callbackId);
    }
    _video = null;
    _callbackId = null;
    _freshFrame = false;
  }
}
