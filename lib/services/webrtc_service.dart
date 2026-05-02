import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCService {
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  Function(String type, Map<String, dynamic> data)? onSignal;
  Function(MediaStream stream)? onRemoteStream;
  Function()? onHangup;
  bool _isCaller = false;
  Timer? _durationTimer;
  int _callSeconds = 0;
  Function(int seconds)? onDuration;

  int get callSeconds => _callSeconds;
  bool get isCaller => _isCaller;

  Future<void> init() async {
    _pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    });

    _pc!.onIceCandidate = (candidate) {
      onSignal?.call('call_ice', {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    _pc!.onAddStream = (stream) {
      onRemoteStream?.call(stream);
    };

    _pc!.onRemoveStream = (_) {
      hangup();
    };

    _pc!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        hangup();
      }
    };
  }

  Future<void> startCall(bool isVideo) async {
    _isCaller = true;
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': isVideo,
    });
    _localStream!.getTracks().forEach((t) => _pc!.addTrack(t, _localStream!));

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    onSignal?.call('call_invite', {
      'sdp': offer.sdp,
      'type': isVideo ? 'video' : 'voice',
      'callerName': '',
    });
  }

  Future<void> acceptCall(String offerSdp, bool isVideo) async {
    _isCaller = false;
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': isVideo,
    });
    _localStream!.getTracks().forEach((t) => _pc!.addTrack(t, _localStream!));

    await _pc!.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    onSignal?.call('call_accept', {'sdp': answer.sdp});
    _startDuration();
  }

  Future<void> onCallAccepted(String answerSdp) async {
    await _pc!.setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));
    _startDuration();
  }

  void onIceCandidate(RTCIceCandidate candidate) {
    _pc?.addCandidate(candidate);
  }

  void rejectCall() {
    onSignal?.call('call_reject', {});
    _cleanup();
  }

  void hangup() {
    _stopDuration();
    if (_localStream != null) {
      _localStream!.getTracks().forEach((t) => t.stop());
    }
    if (_pc != null) {
      _pc!.close();
    }
    _localStream = null;
    _pc = null;
    onHangup?.call();
    onSignal?.call('call_hangup', {});
  }

  void _startDuration() {
    _callSeconds = 0;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _callSeconds++;
      onDuration?.call(_callSeconds);
    });
  }

  void _stopDuration() {
    _durationTimer?.cancel();
  }

  Future<void> toggleMic() async {
    if (_localStream != null) {
      final audioTrack = _localStream!.getAudioTracks().firstOrNull;
      if (audioTrack != null) {
        audioTrack.enabled = !audioTrack.enabled;
      }
    }
  }

  Future<void> toggleSpeaker() async {
    // Speaker toggle (platform dependent, web uses browser controls)
  }

  void _cleanup() {
    _stopDuration();
    _localStream?.getTracks().forEach((t) => t.stop());
    _pc?.close();
    _localStream = null;
    _pc = null;
  }

  MediaStream? get localStream => _localStream;

  void dispose() {
    _cleanup();
  }
}
