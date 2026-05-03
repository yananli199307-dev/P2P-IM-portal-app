import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class LinkText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const LinkText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final urls = _findUrls(text);
    if (urls.isEmpty) return Text(text, style: style);

    // Split text by URLs, render as RichText with clickable links
    final spans = <InlineSpan>[];
    int lastEnd = 0;
    for (final url in urls) {
      if (url.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, url.start), style: style));
      }
      spans.add(WidgetSpan(
        child: GestureDetector(
          onTap: () => launchUrl(Uri.parse(url.url)),
          child: Text(url.url, style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline, fontSize: style?.fontSize, fontWeight: style?.fontWeight)),
        ),
      ));
      lastEnd = url.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: style));
    }
    return RichText(text: TextSpan(children: spans));
  }

  List<_UrlMatch> _findUrls(String text) {
    final regex = RegExp(r'https?://[^\s]+');
    return regex.allMatches(text).map((m) => _UrlMatch(m.group(0)!, m.start, m.end)).toList();
  }
}

class _UrlMatch {
  final String url;
  final int start;
  final int end;
  _UrlMatch(this.url, this.start, this.end);
}
