import 'package:flutter/material.dart';

import '../core/mahjong/mahjong.dart';
import 'wait_text.dart';

/// 手動輸入手牌簡寫，顯示聽哪些牌（階段一的畫面）。
class WaitCalculatorPage extends StatefulWidget {
  const WaitCalculatorPage({super.key});

  @override
  State<WaitCalculatorPage> createState() => _WaitCalculatorPageState();
}

class _WaitCalculatorPageState extends State<WaitCalculatorPage> {
  final _controller = TextEditingController(text: '1112345678999m123p');
  MahjongRules _rules = MahjongRules.presets.first; // 預設：台灣牌
  String _result = '';

  @override
  void initState() {
    super.initState();
    _calculate();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _calculate() {
    String result;
    try {
      result = calculateWaitText(parseTiles(_controller.text), _rules);
    } on FormatException catch (e) {
      result = '格式錯誤：${e.message}';
    }
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EdgeMJ 聽牌計算')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 規則切換：台灣牌 / 香港牌 / 日本牌
            SegmentedButton<MahjongRules>(
              segments: [
                for (final r in MahjongRules.presets)
                  ButtonSegment(value: r, label: Text(r.name)),
              ],
              selected: {_rules},
              onSelectionChanged: (selected) {
                _rules = selected.first;
                _calculate();
              },
            ),
            const SizedBox(height: 8),
            Text('${_rules.name}：手牌 ${_rules.handSize} 張（有吃碰時只輸入手上剩下的牌）'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('handInput'),
              controller: _controller,
              decoration: const InputDecoration(
                labelText: '手牌（m=萬 p=筒 s=條 z=東南西北中發白）',
                hintText: '例：123m456p789s1122z',
              ),
              onSubmitted: (_) => _calculate(),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _calculate, child: const Text('計算聽牌')),
            const SizedBox(height: 24),
            Text(
              _result,
              key: const Key('resultText'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}
