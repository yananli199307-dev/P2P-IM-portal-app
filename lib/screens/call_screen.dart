import 'package:flutter/material.dart';
import '../services/webrtc_service.dart';

class CallScreen extends StatefulWidget {
  final WebRTCService service;
  final String peerName;
  final bool isIncoming;
  final bool isVideo;

  const CallScreen({
    super.key,
    required this.service,
    required this.peerName,
    required this.isIncoming,
    required this.isVideo,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _isAccepted = false;
  bool _muted = false;
  int _duration = 0;
  late WebRTCService _srv;

  @override
  void initState() {
    super.initState();
    _srv = widget.service;
    _srv.onDuration = (s) => setState(() => _duration = s);
    _srv.onRemoteStream = (stream) => setState(() => _isAccepted = true);
    _srv.onHangup = () { if (mounted) Navigator.pop(context); };
  }

  String _formatDuration(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            // 对方视频（通话中显示）
            Expanded(
              child: _isAccepted && _srv.localStream != null
                  ? Stack(children: [
                      if (widget.isVideo)
                        const RTCVideoView(RTCVideoRenderer()..srcObject = _srv.localStream),
                      Center(
                        child: CircleAvatar(radius: 48, backgroundColor: Colors.white24,
                          child: Text(widget.peerName[0].toUpperCase(), style: const TextStyle(fontSize: 36, color: Colors.white)),
                        ),
                      ),
                    ])
                  : Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        CircleAvatar(radius: 48, backgroundColor: Colors.white24,
                          child: Text(widget.peerName[0].toUpperCase(), style: const TextStyle(fontSize: 36, color: Colors.white)),
                        ),
                        const SizedBox(height: 16),
                        if (widget.isIncoming && !_isAccepted)
                          Text('${widget.peerName} 邀请你${widget.isVideo ? "视频" : "语音"}通话', style: const TextStyle(color: Colors.white, fontSize: 18)),
                        if (!widget.isIncoming && !_isAccepted)
                          const Text('正在等待对方接听...', style: TextStyle(color: Colors.white70, fontSize: 16)),
                        if (_isAccepted)
                          Text(_formatDuration(_duration), style: const TextStyle(color: Colors.white, fontSize: 24)),
                      ]),
                    ),
            ),
            // 底部按钮
            Padding(
              padding: const EdgeInsets.only(bottom: 48),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (!widget.isIncoming || _isAccepted) ...[
                    _callButton(_muted ? Icons.mic_off : Icons.mic, Colors.white, () async {
                      await _srv.toggleMic();
                      setState(() => _muted = !_muted);
                    }),
                    _callButton(Icons.call_end, Colors.red, () {
                      _srv.hangup();
                      Navigator.pop(context);
                    }),
                    _callButton(Icons.volume_up, Colors.white, () {}),
                  ] else ...[
                    _callButton(Icons.call_end, Colors.red, () {
                      _srv.rejectCall();
                      Navigator.pop(context);
                    }),
                    _callButton(Icons.call, Colors.green, () {
                      // Widget is recreated with service for accept
                    }),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _callButton(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(radius: 32, backgroundColor: color,
        child: Icon(icon, color: Colors.white, size: 28)),
    );
  }
}

class RTCVideoView extends StatelessWidget {
  final RTCVideoRenderer renderer;
  const RTCVideoView(this.renderer, {super.key});
  @override
  Widget build(BuildContext context) {
    return Container(color: Colors.black);
  }
}
