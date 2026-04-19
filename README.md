# Agent Portal App

Flutter 移动端应用 - P2P 安全通讯

## 功能特性

- ✅ 用户注册/登录
- ✅ JWT Token 认证
- ✅ 联系人管理
- ✅ 实时聊天（WebSocket）
- ✅ 消息气泡 UI
- ✅ 连接状态指示

## 技术栈

- Flutter 3.0+
- Provider 状态管理
- Dio HTTP 客户端
- WebSocket 实时通讯
- SharedPreferences 本地存储

## 快速开始

### 1. 安装 Flutter

```bash
# 确保 Flutter 已安装
flutter doctor
```

### 2. 获取依赖

```bash
cd portal_app
flutter pub get
```

### 3. 配置服务器地址

编辑 `lib/services/api_service.dart`：

```dart
static const String baseUrl = 'https://your-portal.com/api';
```

### 4. 运行应用

```bash
# 调试模式
flutter run

# 或指定设备
flutter run -d <device_id>
```

## 构建发布版本

### Android

```bash
flutter build apk --release
# 输出: build/app/outputs/flutter-apk/app-release.apk
```

### iOS

```bash
flutter build ios --release
# 需要 Xcode 和开发者账号
```

## 项目结构

```
lib/
├── main.dart              # 应用入口
├── models/                # 数据模型
│   ├── user.dart
│   ├── contact.dart
│   └── message.dart
├── services/              # 服务层
│   ├── api_service.dart   # HTTP API
│   └── websocket_service.dart  # WebSocket
├── providers/             # 状态管理
│   ├── auth_provider.dart
│   └── chat_provider.dart
├── screens/               # 页面
│   ├── login_screen.dart
│   ├── register_screen.dart
│   ├── home_screen.dart
│   ├── contacts_screen.dart
│   ├── chat_screen.dart
│   ├── chat_detail_screen.dart
│   ├── add_contact_screen.dart
│   └── settings_screen.dart
└── widgets/               # 组件（待添加）
```

## 下一步

- [ ] WebRTC 语音/视频通话
- [ ] 文件传输
- [ ] 群聊功能
- [ ] 消息已读/撤回
- [ ] 推送通知

## 连接的后端

- Portal: https://agentp2p.cn
- API 文档: https://agentp2p.cn/docs
