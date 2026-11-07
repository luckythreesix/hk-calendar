import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:quick_actions/quick_actions.dart';

Future<void> setVoice(FlutterTts t, double rate) async {
  await t.setLanguage("yue-Hant-HK");
  await t.setSpeechRate(rate);
  await t.setPitch(1.5);
  await t.setVolume(1.0);
  try {
    var vs = await t.getVoices;
    Map? pick;
    for (var v in vs) {
      String n = v['name'].toString().toLowerCase();
      String l = v['locale'].toString().toLowerCase();
      if (!l.contains('yue') && !l.contains('zh-hk') && !n.contains('cantonese')) continue;
      pick ??= v;
      if (n.contains('female') || n.contains('woman') || n.contains('sin-ji') || n.contains('欣')) { pick = v; break; }
    }
    if (pick != null) await t.setVoice({"name": pick['name'], "locale": pick['locale']});
  } catch (e) {}
}

@pragma('vm:entry-point')
Future<void> backgroundSpeak() async {
  final tts = FlutterTts();
  await setVoice(tts, 0.48);
  await tts.awaitSpeakCompletion(true);
  var sp = await SharedPreferences.getInstance();
  var events = jsonDecode(sp.getString('ev') ?? '{}');
  var todos = jsonDecode(sp.getString('todo') ?? '[]') as List;
  String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  var list = events[today] ?? [];
  String text = "朝早好，今日係 ${DateFormat('M月d日').format(DateTime.now())}。";
  if (list.isEmpty) { text += "今日暫時冇行程。"; } else {
    text += "你今日有 ${list.length} 個行程。";
    for (var e in list) { text += "${e['time'].toString().replaceAll(':', '點')}，${e['title']}。"; }
  }
  var left = todos.where((t) => t['done'] == false).toList();
  if (left.isNotEmpty) text += "待辦仲有 ${left.length} 樣。";
  text += "祝你今日順利！";
  await tts.speak(text);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AndroidAlarmManager.initialize();
  runApp(MaterialApp(home: CalendarPro(), debugShowCheckedModeBanner: false));
}

class CalendarPro extends StatefulWidget {
  @override
  State<CalendarPro> createState() => _State();
}

class _State extends State<CalendarPro> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();
  int _tab = 0;
  Map<String, List> events = {};
  List todos = [];
  List counts = [];
  bool autoSpeak = true;
  TimeOfDay autoTime = TimeOfDay(hour: 8, minute: 0);
  double speechRate = 0.48;
  final FlutterTts tts = FlutterTts();
  final FlutterLocalNotificationsPlugin noti = FlutterLocalNotificationsPlugin();
  final SpeechToText _speech = SpeechToText();
  bool _listening = false;
  String _voiceText = "";
  final QuickActions _quickActions = QuickActions();

  @override
  void initState() {
    super.initState();
    load(); initNoti(); setVoice(tts, speechRate);
    Future.delayed(Duration(seconds: 1), checkMorning);
    _quickActions.initialize((type) {
      if (type == 'voice_add') {
        Future.delayed(Duration(milliseconds: 600), () => startVoiceInput());
      } else if (type == 'speak_today') {
        Future.delayed(Duration(milliseconds: 600), () => speakDate(DateTime.now(), "今日"));
      } else if (type == 'speak_three_days') {
        Future.delayed(Duration(milliseconds: 600), () => speakThreeDays());
      }
    });
    _quickActions.setShortcutItems([
      ShortcutItem(type: 'voice_add', localizedTitle: '🎤 講嘢入行程', icon: 'mic'),
      ShortcutItem(type: 'speak_today', localizedTitle: '🔊 講今日行程', icon: 'volume_up'),
      ShortcutItem(type: 'speak_three_days', localizedTitle: '🔊 講三日行程', icon: 'volume_up'),
    ]);
  }

  Future<void> initNoti() async {
    const a = AndroidInitializationSettings('@mipmap/ic_launcher');
    await noti.initialize(InitializationSettings(android: a), onDidReceiveNotificationResponse: (r) => speakDaily());
  }
  Future<void> reqPerm() async { await Permission.notification.request(); await Permission.scheduleExactAlarm.request(); await Permission.ignoreBatteryOptimizations.request(); await Permission.microphone.request(); }
  Future<void> scheduleSpeak() async {
    if (!autoSpeak) return;
    await reqPerm();
    await AndroidAlarmManager.cancel(999); await AndroidAlarmManager.cancel(1000);
    DateTime now = DateTime.now();
    DateTime target = DateTime(now.year, now.month, now.day, autoTime.hour, autoTime.minute);
    if (target.isBefore(now)) target = target.add(Duration(days: 1));
    await AndroidAlarmManager.oneShotAt(target, 999, backgroundSpeak, exact: true, wakeup: true, rescheduleOnReboot: true);
    await AndroidAlarmManager.periodic(Duration(days: 1), 1000, backgroundSpeak, startAt: target, exact: true, wakeup: true, rescheduleOnReboot: true);
  }
  void checkMorning() { var n = DateTime.now(); if (autoSpeak && n.hour >= 7 && n.hour <= 10) speakDaily(); }
  load() async {
    var sp = await SharedPreferences.getInstance();
    setState(() {
      events = jsonDecode(sp.getString('ev') ?? '{}').map((k, v) => MapEntry(k, List.from(v)));
      todos = jsonDecode(sp.getString('todo') ?? '[]');
      counts = jsonDecode(sp.getString('count') ?? '[]');
      autoSpeak = sp.getBool('autoSpeak') ?? true;
      speechRate = sp.getDouble('speechRate') ?? 0.48;
      int h = sp.getInt('autoHour') ?? 8;
      int m = sp.getInt('autoMin') ?? 0;
      autoTime = TimeOfDay(hour: h, minute: m);
    });
    setVoice(tts, speechRate);
    scheduleSpeak();
  }
  save() async { var sp = await SharedPreferences.getInstance(); sp.setString('ev', jsonEncode(events)); sp.setString('todo', jsonEncode(todos)); sp.setString('count', jsonEncode(counts)); sp.setBool('autoSpeak', autoSpeak); sp.setDouble('speechRate', speechRate); sp.setInt('autoHour', autoTime.hour); sp.setInt('autoMin', autoTime.minute); }
  String keyOf(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  void showSettings() {
    showDialog(context: context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setD)xt: '輸入待辦', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
      SizedBox(height: 12),
      ...todos.asMap().entries.map((en) => Container(margin: EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: CheckboxListTile(value: en.value['done'], title: Text(en.value['text']), onChanged: (v) { setState(() => todos[en.key]['done'] = v); save(); }, secondary: IconButton(icon: Icon(Icons.delete_outline), onPressed: () { setState(() => todos.removeAt(en.key)); save(); })))).toList()
    ]);
  }

  Widget buildCount() {
    return ListView(padding: EdgeInsets.all(12), children: [
      ElevatedButton(onPressed: addCountDialog, child: Text('新增倒數日'), style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF2A7CFF))),
      ...counts.asMap().entries.map((en) {
        int diff = DateTime.parse(en.value['date']).difference(DateTime.now()).inDays + 1;
        return Container(margin: EdgeInsets.only(top: 10), padding: EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(en.value['title'], style: TextStyle(fontWeight: FontWeight.bold)), Text(en.value['date'], style: TextStyle(color: Colors.grey, fontSize: 12))]), Text('$diff日', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF2A7CFF))), IconButton(icon: Icon(Icons.close), onPressed: () { setState(() => counts.removeAt(en.key)); save(); })]));
      }).toList()
    ]);
  }

  void addEvent() {
    var titleC = TextEditingController(); var timeC = TextEditingController(text: '10:00');
    showDialog(context: context, builder: (_) => AlertDialog(title: Text('新增行程'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: titleC, decoration: InputDecoration(labelText: '標題')), TextField(controller: timeC, decoration: InputDecoration(labelText: '時間'))]), actions: [TextButton(onPressed: () { Navigator.pop(context); }, child: Text('取消')), TextButton(onPressed: () { var k = keyOf(_selected); if (events[k] == null) events[k] = []; events[k]!.add({'title': titleC.text, 'time': timeC.text}); save(); setState(() {}); Navigator.pop(context); }, child: Text('儲存'))]));
  }

  void editEvent(int index, dynamic e) {
    var titleC = TextEditingController(text: e['title'].toString());
    var timeC = TextEditingController(text: e['time'].toString());
    showDialog(context: context, builder: (_) => AlertDialog(title: Text('修改行程'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: titleC, decoration: InputDecoration(labelText: '標題')), TextField(controller: timeC, decoration: InputDecoration(labelText: '時間，例如 18:00'))]), actions: [TextButton(onPressed: () { Navigator.pop(context); }, child: Text('取消')), TextButton(onPressed: () { setState(() { events[keyOf(_selected)]![index]['title'] = titleC.text; events[keyOf(_selected)]![index]['time'] = timeC.text; }); save(); Navigator.pop(context); }, child: Text('儲存修改'))]));
  }

  void addCountDialog() {
    var titleC = TextEditingController(); var dateC = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now().add(Duration(days: 30))));
    showDialog(context: context, builder: (_) => AlertDialog(title: Text('新增倒數'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: titleC, decoration: InputDecoration(labelText: '事件')), TextField(controller: dateC, decoration: InputDecoration(labelText: '日期 yyyy-mm-dd'))]), actions: [TextButton(onPressed: () { counts.add({'title': titleC.text, 'date': dateC.text}); save(); setState(() {}); Navigator.pop(context); }, child: Text('加入'))]));
  }
}
