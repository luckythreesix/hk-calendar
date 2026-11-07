import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> setFemaleCantoneseVoice(FlutterTts tts) async {
  await tts.setLanguage("yue-Hant-HK");
  await tts.setSpeechRate(0.48);
  await tts.setPitch(1.5);
  await tts.setVolume(1.0);
  try {
    var voices = await tts.getVoices;
    Map? femaleVoice;
    Map? cantoneseVoice;
    for (var v in voices) {
      String name = v['name'].toString().toLowerCase();
      String locale = v['locale'].toString().toLowerCase();
      bool isCantonese = locale.contains('yue') || locale.contains('zh-hk') || locale.contains('zh_hk') || name.contains('yue') || name.contains('cantonese') || name.contains('hk');
      if (!isCantonese) continue;
      cantoneseVoice ??= v;
      if (name.contains('female') || name.contains('woman') || name.contains('sin-ji') || name.contains('sinji') || name.contains('f1') || name.contains('欣') || name.contains('女')) {
        femaleVoice = v;
        break;
      }
    }
    var picked = femaleVoice ?? cantoneseVoice;
    if (picked != null) {
      await tts.setVoice({"name": picked['name'], "locale": picked['locale']});
    }
  } catch (e) {}
}

@pragma('vm:entry-point')
Future<void> backgroundSpeak() async {
  final tts = FlutterTts();
  await setFemaleCantoneseVoice(tts);
  await tts.awaitSpeakCompletion(true);
  var sp = await SharedPreferences.getInstance();
  var events = jsonDecode(sp.getString('ev') ?? '{}');
  var todos = jsonDecode(sp.getString('todo') ?? '[]') as List;
  var counts = jsonDecode(sp.getString('count') ?? '[]') as List;
  String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  var list = events[today] ?? [];
  String text = "朝早好，熄屏播報。今日係 ${DateFormat('M月d日').format(DateTime.now())}。";
  if (list.isEmpty) {
    text += "今日暫時冇行程。";
  } else {
    text += "你今日有 ${list.length} 個行程。";
    for (var e in list) {
      text += "${e['time'].toString().replaceAll(':', '點')}，${e['title']}。";
    }
  }
  var todoLeft = todos.where((t) => t['done'] == false).toList();
  if (todoLeft.isNotEmpty) {
    text += "待辦仲有 ${todoLeft.length} 樣，${todoLeft.take(3).map((t) => t['text']).join('，')}。";
  }
  if (counts.isNotEmpty) {
    text += "倒數方面，";
    for (var c in counts) {
      int diff = DateTime.parse(c['date']).difference(DateTime.now()).inDays + 1;
      if (diff < 0) diff = 0;
      text += "${c['title']}重有 $diff 日，";
    }
  }
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
  final FlutterTts tts = FlutterTts();
  final FlutterLocalNotificationsPlugin noti = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    load();
    initNoti();
    setupTts();
    Future.delayed(Duration(seconds: 1), checkMorningAutoSpeak);
  }

  Future<void> setupTts() async {
    await setFemaleCantoneseVoice(tts);
  }

  void initNoti() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(android: android);
    await noti.initialize(init, onDidReceiveNotificationResponse: (r) => speakDaily());
  }

  Future<void> requestPermissions() async {
    await Permission.notification.request();
    await Permission.scheduleExactAlarm.request();
    await Permission.ignoreBatteryOptimizations.request();
  }

  Future<void> scheduleScreenOffSpeak() async {
    if (!autoSpeak) return;
    await requestPermissions();
    await AndroidAlarmManager.cancel(999);
    await AndroidAlarmManager.cancel(1000);
    DateTime now = DateTime.now();
    DateTime target = DateTime(now.year, now.month, now.day, autoTime.hour, autoTime.minute);
    if (target.isBefore(now)) target = target.add(Duration(days: 1));
    await AndroidAlarmManager.oneShotAt(target, 999, backgroundSpeak, exact: true, wakeup: true, rescheduleOnReboot: true);
    await AndroidAlarmManager.periodic(Duration(days: 1), 1000, backgroundSpeak, startAt: target, exact: true, wakeup: true, rescheduleOnReboot: true);
  }

  void checkMorningAutoSpeak() {
    var now = DateTime.now();
    if (autoSpeak && now.hour >= 7 && now.hour <= 10) speakDaily();
  }

  load() async {
    var sp = await SharedPreferences.getInstance();
    setState(() {
      events = jsonDecode(sp.getString('ev') ?? '{}').map((k, v) => MapEntry(k, List.from(v)));
      todos = jsonDecode(sp.getString('todo') ?? '[]');
      counts = jsonDecode(sp.getString('count') ?? '[]');
      autoSpeak = sp.getBool('autoSpeak') ?? true;
    });
    scheduleScreenOffSpeak();
  }

  save() async {
    var sp = await SharedPreferences.getInstance();
    sp.setString('ev', jsonEncode(events));
    sp.setString('todo', jsonEncode(todos));
    sp.setString('count', jsonEncode(counts));
    sp.setBool('autoSpeak', autoSpeak);
  }

  String keyOf(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> speakDaily() async {
    await setupTts();
    String k = keyOf(DateTime.now());
    var list = events[k] ?? [];
    var todoList = todos.where((t) => !t['done']).toList();
    String text = "朝早好，今日係 ${DateFormat('M月d日').format(DateTime.now
