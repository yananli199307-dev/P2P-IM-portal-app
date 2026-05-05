import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/update_service.dart';
import '../widgets/update_dialog.dart';
import 'contacts_book_screen.dart';
import 'chat_screen.dart';
import 'me_screen.dart';
import 'explore_screen.dart';
import 'call_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // 初始化 WebSocket
    _initWebSocket();
    // 启动时静默检查更新(失败不打扰)
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  Future<void> _checkUpdate() async {
    final info = await UpdateService().checkUpdate();
    if (!mounted || info == null || !info.hasUpdate) return;
    UpdateDialog.show(context, info);
  }
  
  void _initWebSocket() async {
    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    
    if (authProvider.user != null && authProvider.portalUrl != null) {
      // 初始化 WebSocket 连接 — Web 部署时用真实 Portal URL
      final wsBaseUrl = authProvider.portalUrl!;
      await chatProvider.initWebSocket(
        baseUrl: wsBaseUrl,
        userId: authProvider.user!.id.toString(),
        apiKey: authProvider.token!,
      );
      // 加载联系人
      chatProvider.loadContacts();
    }
  }

  bool _showingIncoming = false;

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final totalUnread = chatProvider.totalUnreadCount;

    // 监听来电:有 incomingCall 时弹出全屏来电界面
    if (chatProvider.incomingCall != null && !_showingIncoming) {
      _showingIncoming = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showIncomingDialog(chatProvider);
      });
    }
    
    final screens = [
      const ChatScreen(),
      const ContactsBookScreen(),
      const ExploreScreen(),
      const MeScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: totalUnread > 0,
              label: Text(totalUnread > 99 ? '99+' : '$totalUnread'),
              child: const Icon(Icons.chat_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: totalUnread > 0,
              label: Text(totalUnread > 99 ? '99+' : '$totalUnread'),
              child: const Icon(Icons.chat),
            ),
            label: '消息',
          ),
          const NavigationDestination(
            icon: Icon(Icons.contacts_outlined),
            selectedIcon: Icon(Icons.contacts),
            label: '通讯录',
          ),
          const NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: '探索',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我',
          ),
        ],
      ),
    );
  }

  Future<void> _showIncomingDialog(ChatProvider provider) async {
    final ic = provider.incomingCall;
    if (ic == null) {
      _showingIncoming = false;
      return;
    }
    final isVideo = ic['type'] == 'video';
    // 尝试根据 from_user_id 找联系人显示名(简化:暂用 "对方")
    final peerName = '对方';

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(isVideo ? '视频通话邀请' : '语音通话邀请'),
        content: Text('$peerName 邀请你${isVideo ? "视频" : "语音"}通话'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('拒绝', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('接听'),
          ),
        ],
      ),
    );

    _showingIncoming = false;
    if (!mounted) return;
    if (accepted == true) {
      await provider.acceptIncomingCall();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallScreen(peerName: peerName, isVideo: isVideo),
        ),
      );
    } else {
      provider.rejectIncomingCall();
    }
  }
}
