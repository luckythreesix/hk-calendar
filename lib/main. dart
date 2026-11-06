import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// ============ 熄屏播報 - 系統叫醒時會跑呢個 ============
@pragma('vm:entry-point')
Future<void> backgroundSpeak() async {
  final tts = FlutterTts();
  await tts.setLanguage("yue-Hant-HK");
  await tts.setSpeechRate(0.92);
  await tts.setPitch(1.25);
  await tts.setVolume(1.0);
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

// ============ 主程式 ============
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
    await tts.setLanguage("yue-Hant-HK");
    await tts.setSpeechRate(0.92);
    await tts.setPitch(1.25);
    await tts.setVolume(1.0);
    try {
      var voices = await tts.getVoices;
      for (var v in voices) {
        String name = v['name'].toString().toLowerCase();
        if (name.contains('yue') || name.contains('cantonese') || name.contains('hk')) {
          await tts.setVoice({"name": v['name'], "locale": v['locale']});
          break;
        }
      }
    } catch (e) {}
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
    String text = "朝早好，今日係 ${DateFormat('M月d日').format(DateTime.now())}，星期${['日', '一', '二', '三', '四', '五', '六'][DateTime.now().weekday % 7]}。";
    if (list.isEmpty) {
      text += "今日行事曆暫時冇安排，可以輕鬆啲。";
    } else {
      text += "你今日有 ${list.length} 個行程，聽住啦。";
      for (var e in list) {
        text += "${e['time'].toString().replaceAll(':', '點')}，${e['title']}。";
      }
    }
    if (todoList.isNotEmpty) {
      text += "待辦仲有 ${todoList.length} 樣未做，${todoList.take(3).map((t) => t['text']).join('，')}，記得做呀。";
    }
    if (counts.isNotEmpty) {
      text += "倒數日方面，";
      for (var c in counts) {
        int diff = DateTime.parse(c['date']).difference(DateTime.now()).inDays + 1;
        if (diff < 0) diff = 0;
        text += "${c['title']}，重有 $diff 日就到，";
      }
    }
    text += "祝你今日順順利利，心情靚靚！";
    await tts.speak(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F5F7),
      appBar: AppBar(
        title: Text(['行事曆', '待辦', '倒數日'][_tab]),
        backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0,
        actions: [
          IconButton(icon: Icon(autoSpeak ? Icons.volume_up : Icons.volume_off, color: autoSpeak ? Color(0xFF2A7CFF) : Colors.grey), onPressed: () {
            setState(() => autoSpeak = !autoSpeak); save(); if (autoSpeak) scheduleScreenOffSpeak();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(autoSpeak ? '已開啟 熄屏自動講' : '已關閉自動講')));
          }),
          IconButton(icon: Icon(Icons.access_time), onPressed: () async {
            var t = await showTimePicker(context: context, initialTime: autoTime);
            if (t != null) { setState(() => autoTime = t); save(); scheduleScreenOffSpeak(); }
          }),
        ],
      ),
      body: _tab == 0 ? buildCal() : _tab == 1 ? buildTodo() : buildCount(),
      bottomNavigationBar: BottomNavigationBar(currentIndex: _tab, onTap: (i) => setState(() => _tab = i), selectedItemColor: Color(0xFF2A7CFF), items: [
        BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: '行事曆'),
        BottomNavigationBarItem(icon: Icon(Icons.check_circle), label: '待辦'),
        BottomNavigationBarItem(icon: Icon(Icons.hourglass_bottom), label: '倒數'),
      ]),
      floatingActionButton: _tab == 0 ? FloatingActionButton(onPressed: addEvent, child: Icon(Icons.add), backgroundColor: Color(0xFF2A7CFF)) : null,
    );
  }

  Widget buildCal() {
    return Column(children: [
      Container(margin: EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: TableCalendar(firstDay: DateTime(2020), lastDay: DateTime(2030), focusedDay: _focused,
          selectedDayPredicate: (d) => isSameDay(_selected, d),
          onDaySelected: (s, f) { setState(() { _selected = s; _focused = f; }); },
          eventLoader: (d) => events[keyOf(d)] ?? [],
          calendarStyle: CalendarStyle(markerDecoration: BoxDecoration(color: Color(0xFF2A7CFF), shape: BoxShape.circle)),
          headerStyle: HeaderStyle(formatButtonVisible: false, titleCentered: true),
        )),
      Container(margin: EdgeInsets.symmetric(horizontal: 12), width: double.infinity,
        child: ElevatedButton.icon(onPressed: speakDaily, icon: Icon(Icons.volume_up), label: Text("🔊 女聲講出今日行事"), style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF2A7CFF), padding: EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))),
      SizedBox(height: 8),
      Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Row(children: [Icon(Icons.wb_sunny, size: 14, color: Colors.orange), SizedBox(width: 4), Text(autoSpeak ? '熄屏自動講：每日 ${autoTime.hour}:${autoTime.minute.toString().padLeft(2, '0')}' : '自動講已關閉', style: TextStyle(fontSize: 12, color: Colors.grey))])),
      Expanded(child: Container(margin: EdgeInsets.all(12), padding: EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: ListView(children: (events[keyOf(_selected)] ?? []).map<Widget>((e) => ListTile(leading: Container(width: 10, height: 10, decoration: BoxDecoration(color: Color(0xFF2A7CFF), shape: BoxShape.circle)), title: Text(e['title']), subtitle: Text(e['time']), trailing: IconButton(icon: Icon(Icons.close, size: 16), onPressed: () { setState(() => events[keyOf(_selected)]!.remove(e)); save(); }))).toList()))),
    ]);
  }

  Widget buildTodo() {
    return ListView(padding: EdgeInsets.all(12), children: [
      TextField(onSubmitted: (v) { setState(() => todos.add({'text': v, 'done': false})); save(); }, decoration: InputDecoration(hintText: '輸入待辦，例如：買機票', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
      SizedBox(height: 12),
      ...todos.asMap().entries.map((en) => Container(margin: EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: CheckboxListTile(value: en.value['done'], title: Text(en.value['text'], style: TextStyle(decoration: en.value['done'] ? TextDecoration.lineThrough : null)), onChanged: (v) { setState(() => todos[en.key]['done'] = v); save(); }, secondary: IconButton(icon: Icon(Icons.delete_outline), onPressed: () { setState(() => todos.removeAt(en.key)); save(); })))).toList()
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
    showDialog(context: context, builder: (_) => AlertDialog(title: Text('新增行程'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: titleC, decoration: InputDecoration(labelText: '標題')), TextField(controller: timeC, decoration: InputDecoration(labelText: '時間'))]), actions: [TextButton(onPressed: () { Navigator.pop(context); }, child: Text('取消')), TextButton(onPressed: () { var k = keyOf(_selected); if (events[k] == null) events[k] = []; events[k]!.add({'title': titleC.text, 'time': timeC.text, 'color': '0xFF2A7CFF'}); save(); setState(() {}); Navigator.pop(context); }, child: Text('儲存'))]));
  }

  void addCountDialog() {
    var titleC = TextEditingController(); var dateC = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now().add(Duration(days: 30))));
    showDialog(context: context, builder: (_) => AlertDialog(title: Text('新增倒數'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: titleC, decoration: InputDecoration(labelText: '事件，例如：去日本')), TextField(controller: dateC, decoration: InputDecoration(labelText: '日期 yyyy-mm-dd'))]), actions: [TextButton(onPressed: () { counts.add({'title': titleC.text, 'date': dateC.text}); save(); setState(() {}); Navigator.pop(context); }, child: Text('加入'))]));
  }
}
