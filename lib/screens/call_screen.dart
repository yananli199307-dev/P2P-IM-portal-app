import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';

/// 通话界面 — ChatProvider 已经把 WebRTC 状态准备好,这里只负责渲染。
class CallScreen extends StatefulWidget {
  final String peerName;
  final bool isVideo;
  const CallScreen({
    super.key,
    required this.peerName,
    required this.isVideo,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  bool _connected = false;
  bool _muted = false;
  int _duration = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    final webrtc = context.read<ChatProvider>().webrtc;

    webrtc.onDuration = (s) {
      if (mounted) setState(() => _duration = s);
    };
    webrtc.onRemoteStream = (stream) {
      _remoteRenderer.srcObject = stream;
      if (mounted) setState(() => _connected = true);
    };
    webrtc.onHangup = () {
      if (mounted) Navigator.pop(context);
    };

    // ChatProvider 已经在 startCall/acceptIncomingCall 里准备好流
    if (webrtc.localStream != null) {
      _localRenderer.srcObject = webrtc.localStream;
      if (mounted) setState(() {});
    }
    if (webrtc.remoteStream != null) {
      _remoteRenderer.srcObject = webrtc.remoteStream;
      if (mounted) setState(() => _connected = true);
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  String _fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext c) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      body: SafeArea(
        child: Stack(
          children: [
            // 远端视频(全屏)或头像占位
            Positioned.fill(
              child: widget.isVideo && _connected
                  ? RTCVideoView(
                      _remoteRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.white24,
                            child: Text(
                              widget.peerName.isEmpty
                                  ? '?'
                                  : widget.peerName[0].toUpperCase(),
                              style: const TextStyle(
                                fontSize: 40,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.peerName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _connected
                                ? _fmt(_duration)
                                : (widget.isVideo ? '视频呼叫中...' : '语音呼叫中...'),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

            // 本地视频小窗(右上角)
            if (widget.isVideo)
              Positioned(
                top: 24,
                right: 16,
                width: 100,
                height: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    color: Colors.black54,
                    child: RTCVideoView(
                      _localRenderer,
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),

            // 视频通话顶部信息条
            if (widget.isVideo && _connected)
              Positioned(
                top: 24,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${widget.peerName}  ${_fmt(_duration)}',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),

            // 底部控制栏
            Positioned(
              left: 0,
              right: 0,
              bottom: 60,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _btn(
                    _muted ? Icons.mic_off : Icons.mic,
                    _muted ? Colors.white38 : Colors.white,
                    () {
                      context.read<ChatProvider>().webrtc.toggleMic();
                      setState(() => _muted = !_muted);
                    },
                  ),
                  _btn(Icons.call_end, Colors.red, () {
                    context.read<ChatProvider>().hangupCall();
                    Navigator.pop(c);
                  }),
                  if (widget.isVideo)
                    _btn(Icons.cameraswitch, Colors.white, () {
                      context.read<ChatProvider>().webrtc.switchCamera();
                    })
                  else
                    _btn(Icons.volume_up, Colors.white, () {}),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(
        radius: 30,
        backgroundColor: color,
        child: Icon(
          icon,
          color: color == Colors.white ? Colors.black87 : Colors.white,
          size: 26,
        ),
      ),
    );
  }
}
