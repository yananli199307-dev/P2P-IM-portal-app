import 'dart:async';
import 'dart:html' as html;

class WebRTCService {
  html.RtcPeerConnection? _pc;
  html.MediaStream? _localStream;
  Function(String type, Map<String, dynamic> data)? onSignal;
  Function(html.MediaStream stream)? onRemoteStream;
  Function()? onHangup;
  bool _isCaller = false;
  Timer? _durationTimer;
  int _callSeconds = 0;
  Function(int seconds)? onDuration;

  int get callSeconds => _callSeconds;
  bool get isCaller => _isCaller;
  html.MediaStream? get localStream => _localStream;

  Future<void> init() async {
    final config = {'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]};
    _pc = html.RtcPeerConnection(config);
    _pc!.onIceCandidate = (e) {
      if (e.candidate != null) {
        onSignal?.call('call_ice', {'candidate': e.candidate!.candidate, 'sdpMid': e.candidate!.sdpMid, 'sdpMLineIndex': e.candidate!.sdpMLineIndex});
      }
    };
    _pc!.onAddStream = (e) async {
      onRemoteStream?.call(e.stream!);
    };
    _pc!.onRemoveStream = (_) => hangup();
  }

  Future<void> startCall(bool isVideo) async {
    _isCaller = true;
    _localStream = await html.window.navigator.mediaDevices!.getUserMedia({'audio': true, 'video': isVideo});
    _localStream!.getTracks().forEach((t) => _pc!.addTrack(t, _localStream!));
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    onSignal?.call('call_invite', {'sdp': offer.sdp, 'type': isVideo ? 'video' : 'voice'});
  }

  Future<void> acceptCall(String offerSdp, bool isVideo) async {
    _isCaller = false;
    _localStream = await html.window.navigator.mediaDevices!.getUserMedia({'audio': true, 'video': isVideo});
    _localStream!.getTracks().forEach((t) => _pc!.addTrack(t, _localStream!));
    await _pc!.setRemoteDescription(html.RtcSessionDescription({'sdp': offerSdp, 'type': 'offer'}));
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    onSignal?.call('call_accept', {'sdp': answer.sdp});
    _startDuration();
  }

  Future<void> onCallAccepted(String sdp) async {
    await _pc!.setRemoteDescription(html.RtcSessionDescription({'sdp': sdp, 'type': 'answer'}));
    _startDuration();
  }

  void onIceCandidate(Map<String, dynamic> data) {
    _pc?.addCandidate(html.RtcIceCandidate({
      'candidate': data['candidate'],
      'sdpMid': data['sdpMid'],
      'sdpMLineIndex': data['sdpMLineIndex'],
    }));
  }

  void rejectCall() { onSignal?.call('call_reject', {}); _cleanup(); }

  void hangup() {
    _stopDuration();
    _cleanup();
    onHangup?.call();
    onSignal?.call('call_hangup', {});
  }

  void _startDuration() {
    _callSeconds = 0;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) { _callSeconds++; onDuration?.call(_callSeconds); });
  }
  void _stopDuration() => _durationTimer?.cancel();

  void toggleMic() {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !t.enabled);
  }

  void _cleanup() {
    _localStream?.getTracks().forEach((t) => t.stop());
    _pc?.close();
    _localStream = null;
    _pc = null;
  }

  void dispose() => _cleanup();
}
