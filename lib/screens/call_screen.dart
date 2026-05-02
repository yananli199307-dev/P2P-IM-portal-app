import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../services/webrtc_service.dart';

class CallScreen extends StatefulWidget {
  final WebRTCService service;
  final String peerName;
  final bool isIncoming;
  final bool isVideo;
  final String? offerSdp;

  const CallScreen({
    super.key,
    required this.service,
    required this.peerName,
    required this.isIncoming,
    required this.isVideo,
    this.offerSdp,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _connected = false;
  bool _muted = false;
  int _duration = 0;
  late WebRTCService _srv;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _srv = widget.service;
    _srv.onDuration = (s) => setState(() => _duration = s);
    _srv.onRemoteStream = (stream) => setState(() => _connected = true);
    _srv.onHangup = () { if (mounted) Navigator.pop(context); };
    await _srv.init();

    if (widget.isIncoming && widget.offerSdp != null) {
      await _srv.acceptCall(widget.offerSdp!, widget.isVideo);
    } else if (!widget.isIncoming) {
      await _srv.startCall(widget.isVideo);
    }
  }

  String _fmt(int s) {
    final m = s ~/ 60, sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 60),
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(radius: 50, backgroundColor: Colors.white24,
                  child: Text(widget.peerName[0].toUpperCase(), style: const TextStyle(fontSize: 40, color: Colors.white)),
                ),
                const SizedBox(height: 16),
                Text(widget.peerName, style: const TextStyle(color: Colors.white, fontSize: 24)),
                const SizedBox(height: 8),
                if (!_connected && !widget.isIncoming)
                  const Text('等待对方接听...', style: TextStyle(color: Colors.white54, fontSize: 16)),
                if (!_connected && widget.isIncoming)
                  Text('${widget.peerName} 邀请你${widget.isVideo ? "视频" : "语音"}通话', style: const TextStyle(color: Colors.white, fontSize: 16)),
                if (_connected)
                  Text(_fmt(_duration), style: const TextStyle(color: Colors.white70, fontSize: 20)),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 60, top: 24),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _btn(_muted ? Icons.mic_off : Icons.mic, _muted ? Colors.white : Colors.white38, () { _srv.toggleMic(); setState(() => _muted = !_muted); }),
              _btn(Icons.call_end, Colors.red, () { _srv.hangup(); Navigator.pop(context); }),
              if (!widget.isIncoming || _connected)
                _btn(Icons.volume_up, Colors.white, () {}),
              if (widget.isIncoming && !_connected)
                _btn(Icons.call, Colors.green, () async {
                  await _srv.acceptCall(widget.offerSdp!, widget.isVideo);
                }),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _btn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(radius: 30, backgroundColor: color,
        child: Icon(icon, color: color == Colors.white ? Colors.black87 : Colors.white, size: 26)),
    );
  }

  @override
  void dispose() {
    _srv.dispose();
    super.dispose();
  }
}
