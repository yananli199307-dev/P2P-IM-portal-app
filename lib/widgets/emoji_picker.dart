import 'package:flutter/material.dart';

class EmojiPicker extends StatelessWidget {
  final Function(String) onEmoji;
  const EmojiPicker({super.key, required this.onEmoji});

  // 微信风格经典表情（第一页）
  static const _classic = [
    '😀','😃','😄','😁','😆','😅','😂','🤣',
    '😊','😇','🙂','😉','😌','😍','🥰','😘',
    '😋','😛','😜','🤪','😝','🤑','🤗','🤭',
    '😏','😒','😞','😔','😟','😕','🙁','😣',
    '😖','😫','😩','🥺','😢','😭','😤','😠',
    '😡','🤬','🤯','😳','🥵','🥶','😱','😨',
    '👍','👎','👏','🙌','💪','🤝','🙏','✌️',
    '❤️','🧡','💛','💚','💙','💜','🖤','🤍',
    '🎉','🎊','🎈','🔥','⭐','🌟','✨','💯',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 240,
      color: Colors.grey[100],
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: Colors.white,
          child: const Row(children: [
            Text('经典表情', style: TextStyle(fontSize: 13, color: Color(0xFF6C63FF), fontWeight: FontWeight.w500)),
          ]),
        ),
        Expanded(
          child: GridView.count(
            crossAxisCount: 8,
            padding: const EdgeInsets.all(4),
            children: _classic.map((e) => GestureDetector(
              onTap: () => onEmoji(e),
              child: Center(child: Text(e, style: const TextStyle(fontSize: 24))),
            )).toList(),
          ),
        ),
      ]),
    );
  }

  static void show(BuildContext context, TextEditingController controller) {
    showModalBottomSheet(
      context: context,
      builder: (_) => EmojiPicker(onEmoji: (emoji) {
        controller.text += emoji;
        controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
        Navigator.pop(context);
      }),
    );
  }
}
