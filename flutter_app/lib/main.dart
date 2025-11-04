import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget { const MyApp({super.key}); @override State<MyApp> createState() => _MyAppState(); }

class _MyAppState extends State<MyApp> {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'));
  String? token;
  MqttServerClient? client;
  String logs = '';

  Future<void> login() async {
    final res = await dio.post('/auth/login', data: { 'email': 'demo@example.com', 'password': 'x' });
    token = res.data['access_token'];
    dio.options.headers['Authorization'] = 'Bearer $token';
    setState(() => logs += '\nHTTP: Login OK');
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
      setState(() => logs += '\nMQTT: Connected');

      const topicStatus = 't0/devices/+/status';
      client!.subscribe(topicStatus, MqttQos.atLeastOnce);

      // listen chung cho mọi topic
      client!.updates!.listen((events) {
        final recMess = events[0].payload as MqttPublishMessage;
        final pt = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        final t = events[0].topic;
        setState(() => logs += '\n[$t] $pt');
      });

      // (Tuỳ chọn) subscribe luôn telemetry của dev-01 cho dễ thấy
      const topicTelemetry = 't0/devices/dev-01/telemetry';
      client!.subscribe(topicTelemetry, MqttQos.atLeastOnce);

    } catch (e) {
      setState(() => logs += '\nMQTT error: $e');
      client!.disconnect();
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
                ElevatedButton(onPressed: login, child: const Text('Login REST')),
                const SizedBox(width: 12),
                ElevatedButton(onPressed: connectMqtt, child: const Text('Connect MQTT')),
              ]),
              const SizedBox(height: 12),
              Expanded(child: SingleChildScrollView(child: Text(logs)))
            ],
          ),
        ),
      ),
    );
  }
}
