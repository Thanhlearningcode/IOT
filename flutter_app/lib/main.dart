import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:convert';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget { const MyApp({super.key}); @override State<MyApp> createState() => _MyAppState(); }

class _MyAppState extends State<MyApp> {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'));
  String? token;
  MqttServerClient? client;
  String logs = '';
  String deviceUid = 'dev-01';
  List<Map<String, dynamic>> telemetry = [];
  bool mqttConnected = false;
  bool loadingTelemetry = false;
  final Set<String> seenMsgIds = {};
  static const int maxTelemetry = 300; // giới hạn để tránh tràn bộ nhớ demo

  Future<void> login() async {
    final res = await dio.post('/auth/login', data: { 'email': 'demo@example.com', 'password': 'x' });
    token = res.data['access_token'];
    dio.options.headers['Authorization'] = 'Bearer $token';
    setState(() => logs += '\nHTTP: Login OK');
  }

  void _attachMqttListener() {
    // Lắng nghe mọi publish
    client!.updates!.listen((events) {
      final publish = events[0].payload as MqttPublishMessage;
      final topic = events[0].topic;
      final payloadString = MqttPublishPayload.bytesToStringAsString(publish.payload.message);
      // Ghi log thô
      setState(() => logs += '\n[$topic] $payloadString');
      // Nếu là telemetry cho deviceUid hiện tại, append realtime
      if (topic == 't0/devices/$deviceUid/telemetry') {
        try {
          final decoded = json.decode(payloadString) as Map<String, dynamic>;
          final msgId = decoded['msg_id']?.toString() ?? 'no-id-${DateTime.now().millisecondsSinceEpoch}';
          if (!seenMsgIds.contains(msgId)) {
            seenMsgIds.add(msgId);
            final row = {
              'ts': decoded['ts']?.toString(),
              'payload': decoded,
            };
            telemetry.insert(0, row); // mới nhất lên đầu
            if (telemetry.length > maxTelemetry) {
              telemetry.removeRange(maxTelemetry, telemetry.length);
            }
            setState(() {});
          }
        } catch (_) {}
      }
    });
  }

  Future<void> connectMqtt() async {
    // Nếu chạy trên mobile device thật: đổi 'localhost' thành IP LAN của máy chạy EMQX
    client = MqttServerClient.withPort('localhost', 'flutter_client', 8083);
    client!.useWebSocket = true; // ws://host:8083/mqtt
    client!.logging(on: false);
    client!.keepAlivePeriod = 20;
    client!.onDisconnected = () => setState(() => logs += '\nMQTT: Disconnected');

    final connMess = MqttConnectMessage()
        .withClientIdentifier('flutter_${DateTime.now().millisecondsSinceEpoch}')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    client!.connectionMessage = connMess;

    try {
  await client!.connect();
  mqttConnected = true;
  setState(() => logs += '\nMQTT: Connected');

      const topicStatus = 't0/devices/+/status';
      client!.subscribe(topicStatus, MqttQos.atLeastOnce);

      _attachMqttListener();

  // Subscribe telemetry cho device hiện tại
  final topicTelemetry = 't0/devices/$deviceUid/telemetry';
  client!.subscribe(topicTelemetry, MqttQos.atLeastOnce);

    } catch (e) {
      setState(() => logs += '\nMQTT error: $e');
      client!.disconnect();
    }
  }

  Future<void> fetchTelemetry() async {
    if (token == null) {
      setState(() => logs += '\nNeed login before fetch');
      return;
    }
    setState(() { loadingTelemetry = true; });
    try {
      final res = await dio.get('/telemetry/$deviceUid');
      final List data = res.data as List;
      telemetry = data.map((e) => {
        'ts': e['ts'],
        'payload': e['payload'],
      }).toList();
      setState(() => logs += '\nFetched telemetry: ${telemetry.length} rows');
    } catch (e) {
      setState(() => logs += '\nFetch error: $e');
    } finally {
      setState(() { loadingTelemetry = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Flutter + FastAPI + MQTT')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(labelText: 'Device UID'),
                    controller: TextEditingController(text: deviceUid),
                    onSubmitted: (v) {
                      final newUid = v.trim();
                      final oldUid = deviceUid;
                      setState(() { deviceUid = newUid; });
                      if (mqttConnected && client != null) {
                        final oldTopic = 't0/devices/$oldUid/telemetry';
                        final newTopic = 't0/devices/$newUid/telemetry';
                        client!.unsubscribe(oldTopic);
                        client!.subscribe(newTopic, MqttQos.atLeastOnce);
                        logs += '\nResubscribed telemetry from $oldUid -> $newUid';
                        setState(() {});
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(onPressed: login, child: const Text('Login REST')),
                const SizedBox(width: 12),
                ElevatedButton(onPressed: connectMqtt, child: const Text('Connect MQTT')),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                ElevatedButton(onPressed: fetchTelemetry, child: const Text('Fetch History')),
                const SizedBox(width: 12),
                if (loadingTelemetry) const SizedBox(width:16, height:16, child: CircularProgressIndicator(strokeWidth:2)),
              ]),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade300))),
                        child: ListView.builder(
                          itemCount: telemetry.length,
                          itemBuilder: (ctx, i) {
                            final row = telemetry[i];
                            final ts = row['ts'] ?? '-';
                            final payload = row['payload'];
                            final pretty = const JsonEncoder.withIndent('  ').convert(payload);
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text('$ts\n$pretty', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: SingleChildScrollView(child: Text(logs, style: const TextStyle(fontSize: 12))),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
