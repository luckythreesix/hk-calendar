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
      if (n.contains('female') || n.contains('woman') || n.contains('sin-ji') || n.contains('欣')) {
        pick = v;
        break;
      }
    }
    if (pick != null) {
      await t.setVoice({"name": pick['name'], "locale": pick['locale']});
    }
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
  if (list.isEmpty) {
    text += "今日暫時冇行程。";
  } else {
    text += "你今日有 ${list.length} 個行程。";
    for (var e in list) {
      text += "${e['time'].toString().replaceAll(':', '點')}，${e['title']}。";
    }
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
    load();
    initNoti();
    setVoice(tts, speechRate);
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
    await noti.initialize(
      InitializationSettings(android: a),
      onDidReceiveNotificationResponse: (r) => speakDaily(),
    );
  }

  Future<void> reqPerm() async {
    await Permission.notification.request();
    await Permission.scheduleExactAlarm.request();
    await Permission.ignoreBatteryOptimizations.request();
    await Permission.microphone.request();
  }

  Future<void> scheduleSpeak() async {
    if (!autoSpeak) return;
    await reqPerm();
    await AndroidAlarmManager.cancel(999);
    await AndroidAlarmManager.cancel(1000);
    DateTime now = DateTime.now();
    DateTime target = DateTime(now.year, now.month, now.day, autoTime.hour, autoTime.minute);
    if (target.isBefore(now)) target = target.add(Duration(days: 1));
    await AndroidAlarmManager.oneShotAt(target, 999, backgroundSpeak, exact: true, wakeup: true, rescheduleOnReboot: true);
    await AndroidAlarmManager.periodic(Duration(days: 1), 1000, backgroundSpeak, startAt: target, exact: true, wakeup: true, rescheduleOnReboot: true);
  }

  void checkMorning() {
    var n = DateTime.now();
    if (autoSpeak && n.hour >= 7 && n.hour <= 10) speakDaily();
  }

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

  save() async {
    var sp = await SharedPreferences.getInstance();
    sp.setString('ev', jsonEncode(events));
    sp.setString('todo', jsonEncode(todos));
    sp.setString('count', jsonEncode(counts));
    sp.setBool('autoSpeak', autoSpeak);
    sp.setDouble('speechRate', speechRate);
    sp.setInt('autoHour', autoTime.hour);
    sp.setInt('autoMin', autoTime.minute);
  }

  String keyOf(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  void showSettings() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            return AlertDialog(
              title: Text('⚙️ 設定'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      title: Text('朝早自動講行程'),
                      subtitle: Text(autoSpeak ? '開咗' : '熄咗'),
                      value: autoSpeak,
                      onChanged: (v) {
                        setState(() => autoSpeak = v);
                        setD(() {});
                        save();
                        if (autoSpeak) scheduleSpeak();
                      },
                    ),
                    ListTile(
                      title: Text('自動講嘢時間'),
                      subtitle: Text('${autoTime.hour.toString().padLeft(2, '0')}:${autoTime.minute.toString().padLeft(2, '0')}'),
                      trailing: Icon(Icons.access_time),
                      onTap: () async {
                        var t = await showTimePicker(context: context, initialTime: autoTime);
                        if (t != null) {
                          setState(() => autoTime = t);
                          setD(() {});
                          save();
                          scheduleSpeak();
                        }
                      },
                    ),
                    SizedBox(height: 8),
                    Text('講嘢速度：${speechRate.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold)),
                    Slider(
                      value: speechRate,
                      min: 0.3,
                      max: 0.8,
                      divisions: 10,
                      label: speechRate.toStringAsFixed(2),
                      onChanged: (v) {
                        setState(() => speechRate = v);
                        setD(() {});
                      },
                      onChangeEnd: (v) {
                        save();
                        setVoice(tts, speechRate);
                        tts.speak('呢個速度啱唔啱？');
                      },
                    ),
                    SizedBox(height: 8),
                    Divider(),
                    ListTile(
                      leading: Icon(Icons.volume_up, color: Color(0xFF2A7CFF)),
                      title: Text('講今日行程'),
                      onTap: () {
                        Navigator.pop(ctx);
                        speakDate(DateTime.now(), "今日");
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.date_range, color: Color(0xFF5B5BD6)),
                      title: Text('講三日行程'),
                      onTap: () {
                        Navigator.pop(ctx);
                        speakThreeDays();
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.stop_circle, color: Colors.red),
                      title: Text('停止講嘢'),
                      onTap: () {
                        tts.stop();
                        Navigator.pop(ctx);
                      },
                    ),
                    Divider(),
                    ListTile(
                      leading: Icon(Icons.delete_forever, color: Colors.red),
                      title: Text('刪除全部行程', style: TextStyle(color: Colors.red)),
                      onTap: () async {
                        Navigator.pop(ctx);
                        bool? ok = await showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: Text('真係刪除晒？'),
                            content: Text('所有行程會冇晒，唔可以返轉頭。'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text('取消'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text('刪除', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          setState(() => events.clear());
                          save();
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已刪除全部行程')));
                        }
                      },
                    ),
                    SizedBox(height: 8),
                    Center(child: Text('行事曆 v1.0\n長撳桌面 icon 可以直接講嘢入行程', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey))),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('完成'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> speakDate(DateTime date, String label) async {
    await setVoice(tts, speechRate);
    await tts.stop();
    var list = events[keyOf(date)] ?? [];
    String dateStr = DateFormat('M月d日').format(date);
    String text = "$label，$dateStr，";
    if (list.isEmpty) {
      text += "呢日暫時冇安排。";
    } else {
      text += "呢日有 ${list.length} 個行程。";
      for (var e in list) {
        text += "${e['time'].toString().replaceAll(':', '點')}，${e['title']}。";
      }
    }
    text += "講完啦！";
    await tts.speak(text);
  }

  Future<void> speakThreeDays() async {
    await setVoice(tts, speechRate);
    await tts.stop();
    DateTime now = DateTime.now();
    List<String> labels = ["今日", "聽日", "後日"];
    String text = "講三日行程。";
    for (int i = 0; i < 3; i++) {
      DateTime d = now.add(Duration(days: i));
      var list = events[keyOf(d)] ?? [];
      String dateStr = DateFormat('M月d日').format(d);
      text += "${labels[i]}，$dateStr，";
      if (list.isEmpty) {
        text += "冇安排。";
      } else {
        text += "有 ${list.length} 個行程，";
        for (var e in list) {
          text += "${e['time'].toString().replaceAll(':', '點')}，${e['title']}。";
        }
      }
    }
    text += "講完啦！";
    await tts.speak(text);
  }

  Future<void> speakDaily() async {
    await speakDate(_selected, "你撳咗");
  }

  Map<String, dynamic> parseVoice(String raw) {
    String text = raw.trim();
    DateTime date = _selected;
    DateTime now = DateTime.now();
    String time = "10:00";
    String title = text;
    if (text.contains('後日') || text.contains('后日')) {
      date = now.add(Duration(days: 2));
      title = title.replaceAll('後日', '').replaceAll('后日', '');
    } else if (text.contains('聽日') || text.contains('听日') || text.contains('明天')) {
      date = now.add(Duration(days: 1));
      title = title.replaceAll('聽日', '').replaceAll('听日', '').replaceAll('明天', '');
    } else if (text.contains('大後日')) {
      date = now.add(Duration(days: 3));
      title = title.replaceAll('大後日', '');
    } else if (text.contains('今日') || text.contains('今天')) {
      date = now;
      title = title.replaceAll('今日', '').replaceAll('今天', '');
    }
    var mMonth = RegExp(r'(\d{1,2})月(\d{1,2})[號日]').firstMatch(title);
    if (mMonth != null) {
      int mo = int.parse(mMonth.group(1)!);
      int da = int.parse(mMonth.group(2)!);
      date = DateTime(now.year, mo, da);
      title = title.replaceFirst(mMonth.group(0)!, '');
    } else {
      var mDay = RegExp(r'(\d{1,2})[號日]').firstMatch(title);
      if (mDay != null) {
        int da = int.parse(mDay.group(1)!);
        date = DateTime(now.year, now.month, da);
        if (date.isBefore(DateTime(now.year, now.month, now.day))) {
          date = DateTime(now.year, now.month + 1, da);
        }
        title = title.replaceFirst(mDay.group(0)!, '');
      }
    }
    bool isPm = title.contains('下午') || title.contains('夜晚') || title.contains('晚上') || title.contains('傍晚');
    title = title.replaceAll('下午', '').replaceAll('上午', '').replaceAll('早上', '').replaceAll('夜晚', '').replaceAll('晚上', '').replaceAll('傍晚', '').replaceAll('中午', '');
    var mTime = RegExp(r'(\d{1,2})[點时時:：](半|(\d{1,2})[分]?)?').firstMatch(title);
    if (mTime != null) {
      int h = int.parse(mTime.group(1)!);
      int min = 0;
      if (mTime.group(2) == '半') {
        min = 30;
      } else if (mTime.group(3) != null) {
        min = int.parse(mTime.group(3)!);
      }
      if (isPm && h < 12) h += 12;
      time = "${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}";
      title = title.replaceFirst(mTime.group(0)!, '');
    }
    title = title.replaceAll('去', '').replaceAll('要', '').replaceAll('做', '').trim();
    if (title.isEmpty) title = "新行程";
    return {'date': date, 'time': time, 'title': title};
  }

  Future<void> startVoiceInput() async {
    await Permission.microphone.request();
    bool ok = await _speech.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') setState(() => _listening = false);
      },
      onError: (e) {
        setState(() => _listening = false);
      },
    );
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('開唔到咪，請去設定俾錄音權限')));
      return;
    }
    setState(() {
      _listening = true;
      _voiceText = "聽緊...";
    });
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            return AlertDialog(
              title: Text(_listening ? '🎤 講緊嘢...' : '聽到啦！'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_voiceText, style: TextStyle(fontSize: 18)),
                  SizedBox(height: 10),
                  Text('講法：聽日三點去飲茶 / 8號六點半 bbq', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
              actions: [
                if (!_listening)
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      showVoiceConfirm(_voiceText);
                    },
                    child: Text('確認'),
                  ),
                TextButton(
                  onPressed: () {
                    _speech.stop();
                    setState(() => _listening = false);
                    Navigator.pop(ctx);
                  },
                  child: Text(_listening ? '停' : '取消'),
                ),
              ],
            );
          },
        );
      },
    );
    _speech.listen(
      onResult: (r) {
        setState(() => _voiceText = r.recognizedWords);
      },
      localeId: "yue-Hant-HK",
      listenFor: Duration(seconds: 15),
      pauseFor: Duration(seconds: 3),
    );
  }

  void showVoiceConfirm(String raw) {
    if (raw.trim().isEmpty || raw == "聽緊...") {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('聽唔到嘢，再講多次')));
      return;
    }
    var p = parseVoice(raw);
    DateTime d = p['date'];
    var titleC = TextEditingController(text: p['title']);
    var timeC = TextEditingController(text: p['time']);
    var dateC = TextEditingController(text: DateFormat('yyyy-MM-dd').format(d));
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('係咪呢個？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('你講：$raw', style: TextStyle(fontSize: 12, color: Colors.grey)),
            SizedBox(height: 10),
            TextField(controller: titleC, decoration: InputDecoration(labelText: '標題')),
            TextField(controller: dateC, decoration: InputDecoration(labelText: '日期 yyyy-mm-dd')),
            TextField(controller: timeC, decoration: InputDecoration(labelText: '時間')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () {
              String k = dateC.text;
              if (events[k] == null) events[k] = [];
              events[k]!.add({'title': titleC.text, 'time': timeC.text});
              save();
              setState(() {
                _selected = DateTime.parse(k);
                _focused = DateTime.parse(k);
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已加入 $k ${titleC.text}')));
            },
            child: Text('加入行事曆'),
          ),
        ],
      ),
    );
  }

  Widget _cell(DateTime day, bool isSel, bool isToday) {
    var evs = events[keyOf(day)] ?? [];
    Color bg = isSel ? Color(0xFF5B5BD6) : (isToday ? Color(0xFFB8B8E8) : Colors.transparent);
    Color txt = (isSel || isToday) ? Colors.white : Colors.black87;
    List<Widget> chips = [];
    for (var e in evs.take(2)) {
      final m = e as Map;
      chips.add(Container(
        width: double.infinity,
        margin: EdgeInsets.only(left: 2, right: 2, top: 1),
        padding: EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        decoration: BoxDecoration(color: Color(0xFF2A7CFF), borderRadius: BorderRadius.circular(4)),
        child: Text(m['title'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 7.5, color: Colors.white)),
      ));
    }
    if (evs.length > 2) {
      chips.add(Padding(padding: EdgeInsets.only(top: 1), child: Text('+${evs.length - 2}', style: TextStyle(fontSize: 8, color: Colors.grey))));
    }
    return Container(
      margin: EdgeInsets.all(2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Container(height: 22, alignment: Alignment.center, child: Text('${day.day}', style: TextStyle(fontSize: 15, color: txt, fontWeight: isSel ? FontWeight.bold : FontWeight.normal))),
          Expanded(child: Column(children: chips)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        tts.stop();
      },
      child: Scaffold(
        backgroundColor: Color(0xFFF5F5F7),
        appBar: AppBar(
          title: Text(['行事曆', '待辦', '倒數日'][_tab]),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          actions: [
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.black),
              onSelected: (v) {
                if (v == 'settings') showSettings();
                else if (v == 'stop') tts.stop();
                else if (v == 'today') speakDate(DateTime.now(), "今日");
                else if (v == 'three') speakThreeDays();
                else if (v == 'voice') startVoiceInput();
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(value: 'settings', child: Row(children: [Icon(Icons.settings, size: 20), SizedBox(width: 10), Text('設定')])),
                PopupMenuItem(value: 'voice', child: Row(children: [Icon(Icons.mic, size: 20, color: Colors.red), SizedBox(width: 10), Text('🎤 講嘢入行程')])),
                PopupMenuItem(value: 'today', child: Row(children: [Icon(Icons.volume_up, size: 20, color: Color(0xFF2A7CFF)), SizedBox(width: 10), Text('講今日行程')])),
                PopupMenuItem(value: 'three', child: Row(children: [Icon(Icons.date_range, size: 20, color: Color(0xFF5B5BD6)), SizedBox(width: 10), Text('講三日行程')])),
                PopupMenuItem(value: 'stop', child: Row(children: [Icon(Icons.stop_circle, size: 20, color: Colors.red), SizedBox(width: 10), Text('停止講嘢')])),
              ],
            ),
          ],
        ),
        body: _tab == 0 ? buildCal() : _tab == 1 ? buildTodo() : buildCount(),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _tab,
          onTap: (i) => setState(() => _tab = i),
          selectedItemColor: Color(0xFF2A7CFF),
          items: [
            BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: '行事曆'),
            BottomNavigationBarItem(icon: Icon(Icons.check_circle), label: '待辦'),
            BottomNavigationBarItem(icon: Icon(Icons.hourglass_bottom), label: '倒數'),
          ],
        ),
        floatingActionButton: _tab == 0 ? FloatingActionButton(onPressed: addEvent, child: Icon(Icons.add), backgroundColor: Color(0xFF2A7CFF)) : null,
      ),
    );
  }

  Widget buildCal() {
    var list = events[keyOf(_selected)] ?? [];
    return Column(
      children: [
        Container(
          margin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: TableCalendar(
            firstDay: DateTime(2020),
            lastDay: DateTime(2030),
            focusedDay: _focused,
            selectedDayPredicate: (d) => isSameDay(_selected, d),
            onDaySelected: (s, f) {
              setState(() {
                _selected = s;
                _focused = f;
              });
            },
            eventLoader: (d) => events[keyOf(d)] ?? [],
            rowHeight: 72,
            daysOfWeekHeight: 28,
            daysOfWeekStyle: DaysOfWeekStyle(weekdayStyle: TextStyle(fontSize: 11, color: Colors.grey), weekendStyle: TextStyle(fontSize: 11, color: Colors.grey)),
            calendarStyle: CalendarStyle(cellMargin: EdgeInsets.zero, cellPadding: EdgeInsets.zero, markersMaxCount: 0, markersAlignment: Alignment.bottomCenter),
            headerStyle: HeaderStyle(formatButtonVisible: false, titleCentered: true, headerPadding: EdgeInsets.symmetric(vertical: 4), leftChevronPadding: EdgeInsets.all(4), rightChevronPadding: EdgeInsets.all(4)),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focused) => _cell(day, false, false),
              selectedBuilder: (context, day, focused) => _cell(day, true, false),
              todayBuilder: (context, day, focused) => _cell(day, isSameDay(day, _selected), true),
              outsideBuilder: (context, day, focused) => _cell(day, false, false),
              markerBuilder: (context, day, evs) => SizedBox.shrink(),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(child: ElevatedButton.icon(onPressed: speakDaily, icon: Icon(Icons.volume_up), label: Text("講出撳咗嗰日"), style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF2A7CFF), padding: EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))),
              SizedBox(width: 8),
              Expanded(child: ElevatedButton.icon(onPressed: startVoiceInput, icon: Icon(Icons.mic), label: Text("🎤 語音輸入"), style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFFF6B6B), padding: EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(child: ElevatedButton.icon(onPressed: () => speakDate(DateTime.now(), "今日"), icon: Icon(Icons.today), label: Text("講今日"), style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, padding: EdgeInsets.all(10)))),
              SizedBox(width: 8),
              Expanded(child: ElevatedButton.icon(onPressed: speakThreeDays, icon: Icon(Icons.date_range), label: Text("講三日行程"), style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF5B5BD6), padding: EdgeInsets.all(10)))),
            ],
          ),
        ),
        SizedBox(height: 8),
        Expanded(
          child: Container(
            margin: EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: list.isEmpty
                ? InkWell(onTap: addEvent, child: Center(child: Text('撳呢度新增行程 / 撳上面 🎤 用口講', style: TextStyle(color: Colors.grey))))
                : ListView(
                    padding: EdgeInsets.only(bottom: 160),
                    children: list.asMap().entries.map((en) {
                      var e = en.value;
                      return Container(
                        margin: EdgeInsets.only(bottom: 8),
                        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
                        child: Row(
                          children: [
                            Container(width: 10, height: 10, decoration: BoxDecoration(color: Color(0xFF2A7CFF), shape: BoxShape.circle)),
                            SizedBox(width: 10),
                            Expanded(
                              child: InkWell(
                                onTap: () => editEvent(en.key, e),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(e['title'].toString(), style: TextStyle(fontSize: 16)),
                                    SizedBox(height: 2),
                                    Text('撳呢度可以修改', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(e['time'].toString(), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            SizedBox(width: 4),
                            IconButton(
                              icon: Icon(Icons.close, size: 24),
                              padding: EdgeInsets.all(6),
                              constraints: BoxConstraints(minWidth: 40, minHeight: 40),
                              onPressed: () {
                                setState(() => events[keyOf(_selected)]!.remove(e));
                                save();
                              },
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ),
      ],
    );
  }

  Widget buildTodo() {
    return ListView(
      padding: EdgeInsets.all(12),
      children: [
        TextField(
          onSubmitted: (v) {
            if (v.trim().isEmpty) return;
            setState(() => todos.add({'text': v, 'done': false}));
            save();
          },
          decoration: InputDecoration(
            hintText: '輸入待辦',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        SizedBox(height: 12),
        Column(
          children: todos.asMap().entries.map((en) {
            return Container(
              margin: EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: CheckboxListTile(
                value: en.value['done'],
                title: Text(en.value['text']),
                onChanged: (v) {
                  setState(() => todos[en.key]['done'] = v);
                  save();
                },
                secondary: IconButton(
                  icon: Icon(Icons.delete_outline),
                  onPressed: () {
                    setState(() => todos.removeAt(en.key));
                    save();
                  },
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget buildCount() {
    List<Widget> countWidgets = [];
    for (var en in counts.asMap().entries) {
      int diff = DateTime.parse(en.value['date']).difference(DateTime.now()).inDays + 1;
      countWidgets.add(
        Container(
          margin: EdgeInsets.only(top: 10),
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(en.value['title'], style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(en.value['date'], style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
              Text('$diff日', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF2A7CFF))),
              IconButton(
                icon: Icon(Icons.close),
                onPressed: () {
                  setState(() => counts.removeAt(en.key));
                  save();
                },
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.all(12),
      children: [
        ElevatedButton(onPressed: addCountDialog, child: Text('新增倒數日'), style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF2A7CFF))),
        Column(children: countWidgets),
      ],
    );
  }

  void addEvent() {
    var titleC = TextEditingController();
    var timeC = TextEditingController(text: '10:00');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('新增行程'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleC, decoration: InputDecoration(labelText: '標題')),
            TextField(controller: timeC, decoration: InputDecoration(labelText: '時間')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () {
              var k = keyOf(_selected);
              if (events[k] == null) events[k] = [];
              events[k]!.add({'title': titleC.text, 'time': timeC.text});
              save();
              setState(() {});
              Navigator.pop(context);
            },
            child: Text('儲存'),
          ),
        ],
      ),
    );
  }

  void editEvent(int index, dynamic e) {
    var titleC = TextEditingController(text: e['title'].toString());
    var timeC = TextEditingController(text: e['time'].toString());
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('修改行程'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleC, decoration: InputDecoration(labelText: '標題')),
            TextField(controller: timeC, decoration: InputDecoration(labelText: '時間，例如 18:00')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                events[keyOf(_selected)]![index]['title'] = titleC.text;
                events[keyOf(_selected)]![index]['time'] = timeC.text;
              });
              save();
              Navigator.pop(context);
            },
            child: Text('儲存修改'),
          ),
        ],
      ),
    );
  }

  void addCountDialog() {
    var titleC = TextEditingController();
    var dateC = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(
        DateTime.now().add(Duration(days: 30)),
      ),
    );
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('新增倒數'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleC,
              decoration: InputDecoration(labelText: '事件'),
            ),
            TextField(
              controller: dateC,
              decoration: InputDecoration(labelText: '日期 yyyy-mm-dd'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              counts.add({
                'title': titleC.text,
                'date': dateC.text,
              });
              save();
              setState(() {});
              Navigator.pop(context);
            },
            child: Text('加入'),
          ),
        ],
      ),
    );
  }
}
