import 'dart:async' show Timer;
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCService {
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  void Function(String, Map<String, dynamic>)? onSignal;
  void Function(MediaStream)? onRemoteStream;
  void Function()? onHangup;
  bool _isCaller = false;
  Timer? _durationTimer;
  int _callSeconds = 0;
  void Function(int)? onDuration;

  int get callSeconds => _callSeconds;
  MediaStream? get localStream => _localStream;

  Future<void> init() async {
    _pc = await createPeerConnection({
      'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]
    });
    _pc!.onIceCandidate = (c) {
      if (c.candidate != null) onSignal?.call('call_ice', {
        'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex
      });
    };
    _pc!.onAddStream = (s) => onRemoteStream?.call(s);
  }

  Future<void> startCall(bool isVideo) async {
    _isCaller = true;
    _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': isVideo});
    for (final t in _localStream!.getTracks()) { _pc!.addTrack(t, _localStream!); }
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    onSignal?.call('call_invite', {'sdp': offer.sdp, 'type': isVideo ? 'video' : 'voice'});
  }

  Future<void> acceptCall(String offerSdp, bool isVideo) async {
    _isCaller = false;
    _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': isVideo});
    for (final t in _localStream!.getTracks()) { _pc!.addTrack(t, _localStream!); }
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

  void onIceCandidate(Map<String, dynamic> data) {
    _pc?.addCandidate(RTCIceCandidate(data['candidate'] ?? '', data['sdpMid'] ?? '', data['sdpMLineIndex']));
  }

  void rejectCall() { onSignal?.call('call_reject', {}); _cleanup(); }
  void hangup() { _stopDuration(); _cleanup(); onHangup?.call(); onSignal?.call('call_hangup', {}); }

  void _startDuration() {
    _callSeconds = 0;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) { _callSeconds++; onDuration?.call(_callSeconds); });
  }

  void toggleMic() {
    for (final t in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) { t.enabled = !t.enabled; }
  }

  void _stopDuration() => _durationTimer?.cancel();
  void _cleanup() {
    for (final t in _localStream?.getTracks() ?? <MediaStreamTrack>[]) { t.stop(); }
    _pc?.close(); _localStream = null; _pc = null;
  }
  void dispose() => _cleanup();
}
