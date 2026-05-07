import 'dart:async' show Timer;
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// 单例 WebRTC 服务,绑定 WebSocket 信令通道。
class WebRTCService {
  static final WebRTCService _instance = WebRTCService._internal();
  factory WebRTCService() => _instance;
  WebRTCService._internal();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  void Function(String, Map<String, dynamic>)? onSignal;
  void Function(MediaStream)? onRemoteStream;
  void Function()? onHangup;
  bool _isCaller = false;
  Timer? _durationTimer;
  int _callSeconds = 0;
  void Function(int)? onDuration;

  int? peerUserId;          // 当前通话对端的 user id(target_user_id)
  int? peerContactId;       // 对端 contact.id(本地)
  bool isVideo = false;
  DateTime? startedAt;      // remote description 设置成功(媒体真正连通起算)
  bool _remoteDescSet = false;
  final List<RTCIceCandidate> _pendingIce = [];

  bool get isCaller => _isCaller;

  int get callSeconds => _callSeconds;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  bool get inCall => _pc != null;

  Future<void> init() async {
    _pc = await createPeerConnection({
      'iceServers': [
        // 项目自有 STUN（国内可达）— 必须在 Google STUN 之前,确保移动网络也能拿到 srflx
        {'urls': 'stun:185.115.207.219:3478'},
        {'urls': 'stun:stun.l.google.com:19302'},
        {
          'urls': 'turn:185.115.207.219:3478',
          'username': 'agentp2p',
          'credential': '95046a276a4c4f7fd604f9d3',
        },
      ],
    });
    _pc!.onIceCandidate = (c) {
      // ICE 收集结束(end-of-candidates)时 candidate 可能是空字符串,过滤掉避免对端 addIceCandidate 抛异常
      final cand = c.candidate;
      if (cand != null && cand.isNotEmpty) {
        onSignal?.call('call_ice', {
          'candidate': cand,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      }
    };
    // Web 端用 addTrack(unified-plan),App 端如果只用 onAddStream 在 unified-plan 下不一定触发,
    // 改用 onTrack 才是 unified-plan 的标准回调。同时保留 onAddStream 作为旧行为兜底。
    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        final s = event.streams.first;
        _remoteStream = s;
        onRemoteStream?.call(s);
      }
    };
    _pc!.onAddStream = (s) {
      _remoteStream = s;
      onRemoteStream?.call(s);
    };
  }

  Future<void> startCall(bool video) async {
    _isCaller = true;
    isVideo = video;
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video,
    });
    for (final t in _localStream!.getTracks()) {
      _pc!.addTrack(t, _localStream!);
    }
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    onSignal?.call('call_invite', {
      'sdp': offer.sdp,
      'type': video ? 'video' : 'voice',
    });
  }

  Future<void> acceptCall(String offerSdp, bool video) async {
    _isCaller = false;
    isVideo = video;
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video,
    });
    for (final t in _localStream!.getTracks()) {
      _pc!.addTrack(t, _localStream!);
    }
    await _pc!.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));
    _remoteDescSet = true;
    await _flushPendingIce();
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    onSignal?.call('call_accept', {'sdp': answer.sdp});
    startedAt = DateTime.now();
    _startDuration();
  }

  Future<void> onCallAccepted(String answerSdp) async {
    await _pc!.setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));
    _remoteDescSet = true;
    await _flushPendingIce();
    startedAt = DateTime.now();
    _startDuration();
  }

  Future<void> onIceCandidate(Map<String, dynamic> data) async {
    final cand = RTCIceCandidate(
      data['candidate'] ?? '',
      data['sdpMid'] ?? '',
      data['sdpMLineIndex'],
    );
    if (!_remoteDescSet || _pc == null) {
      _pendingIce.add(cand);
      return;
    }
    await _pc!.addCandidate(cand);
  }

  Future<void> _flushPendingIce() async {
    if (_pc == null) return;
    for (final c in _pendingIce) {
      await _pc!.addCandidate(c);
    }
    _pendingIce.clear();
  }

  void rejectCall() {
    onSignal?.call('call_reject', {});
    _cleanup();
  }

  void hangup() {
    _stopDuration();
    onSignal?.call('call_hangup', {});
    _cleanup();
    onHangup?.call();
  }

  void onPeerHangup() {
    _stopDuration();
    _cleanup();
    onHangup?.call();
  }

  void _startDuration() {
    _callSeconds = 0;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _callSeconds++;
      onDuration?.call(_callSeconds);
    });
  }

  void toggleMic() {
    for (final t in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !t.enabled;
    }
  }

  void switchCamera() {
    for (final t in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      Helper.switchCamera(t);
    }
  }

  void _stopDuration() => _durationTimer?.cancel();

  void _cleanup() {
    for (final t in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      t.stop();
    }
    _pc?.close();
    _localStream = null;
    _remoteStream = null;
    _pc = null;
    peerUserId = null;
    peerContactId = null;
    startedAt = null;
    _remoteDescSet = false;
    _pendingIce.clear();
  }

  void dispose() => _cleanup();
}
