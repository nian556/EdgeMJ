import 'package:edge_mj/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 輸入手牌並按下計算
Future<void> enterHand(WidgetTester tester, String hand) async {
  await tester.enterText(find.byKey(const Key('handInput')), hand);
  await tester.tap(find.text('計算聽牌'));
  await tester.pump();
}

void main() {
  testWidgets('預設是台灣牌，並顯示預設 16 張手牌的聽牌結果', (tester) async {
    await tester.pumpWidget(const EdgeMjApp());
    expect(find.textContaining('台灣牌：手牌 16 張'), findsOneWidget);
    expect(find.textContaining('聽：一萬'), findsOneWidget);
  });

  testWidgets('輸入新手牌後按下按鈕會重新計算', (tester) async {
    await tester.pumpWidget(const EdgeMjApp());
    await enterHand(tester, '23m456p789s111z22z');
    expect(find.text('聽：一萬、四萬'), findsOneWidget);
  });

  testWidgets('切換到日本牌後，七對子會被算進聽牌', (tester) async {
    await tester.pumpWidget(const EdgeMjApp());
    await enterHand(tester, '1122m3344p5566s7z');
    expect(find.text('沒有聽牌'), findsOneWidget); // 台灣牌不算七對子

    await tester.tap(find.text('日本牌'));
    await tester.pump();
    expect(find.text('聽：白（七對子）'), findsOneWidget);
  });

  testWidgets('日本牌輸入 16 張會顯示錯誤', (tester) async {
    await tester.pumpWidget(const EdgeMjApp());
    await tester.tap(find.text('日本牌'));
    await tester.pump();
    await enterHand(tester, '1112345678999m123p');
    expect(find.textContaining('日本牌手牌最多 13 張'), findsOneWidget);
  });
}
