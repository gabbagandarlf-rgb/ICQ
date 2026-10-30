import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:file_picker/file_picker.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    
    bool isChatWindow = args.isNotEmpty && args[0] == 'chat';

    if (isChatWindow) {
      final targetNick = args.length > 4 ? args[4] : 'Chat';
      WindowOptions windowOptions = const WindowOptions(
        size: Size(500, 450),
        minimumSize: Size(350, 300),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.setResizable(true);
        await windowManager.show();
        await windowManager.focus();
      });

      runApp(MaterialApp(
        title: 'ICQ Chat - $targetNick',
        theme: ThemeData(
          scaffoldBackgroundColor: const Color(0xFFD4E6D1),
          fontFamily: 'Tahoma',
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF8AC176),
            primary: const Color(0xFF5A9E48),
            secondary: const Color(0xFFFFCC00),
          ),
        ),
        home: StandaloneChatWindow(
          uin: args[1],
          nick: args[2],
          targetUin: args[3],
          targetNick: targetNick,
          serverIp: args[5],
          serverPort: int.parse(args[6]),
        ),
        debugShowCheckedModeBanner: false,
      ));
      return;
    }

    Size initialSize = const Size(280, 540);
    Offset? initialPosition;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/icq_window_bounds.json');
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        initialSize = Size(data['width']?.toDouble() ?? 280.0, data['height']?.toDouble() ?? 540.0);
        if (data['x'] != null && data['y'] != null) {
          initialPosition = Offset((data['x'] as num).toDouble(), (data['y'] as num).toDouble());
        }
      }
    } catch (_) {}

    WindowOptions windowOptions = WindowOptions(
      size: initialSize,
      minimumSize: const Size(260, 450),
      center: initialPosition == null,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (initialPosition != null) {
        await windowManager.setPosition(initialPosition);
      }
      await windowManager.setResizable(true);
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const IcqApp());
}

class IcqApp extends StatelessWidget {
  const IcqApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ICQ',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFD4E6D1),
        fontFamily: 'Tahoma',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8AC176),
          primary: const Color(0xFF5A9E48),
          secondary: const Color(0xFFFFCC00),
        ),
      ),
      home: const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

Future<void> saveWindowBounds() async {
  try {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final size = await windowManager.getSize();
      final pos = await windowManager.getPosition();
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/icq_window_bounds.json');
      await file.writeAsString(jsonEncode({
        'width': size.width,
        'height': size.height,
        'x': pos.dx,
        'y': pos.dy,
      }));
    }
  } catch (_) {}
}

class SocketBuffer {
  final SecureSocket socket;
  final List<int> _queue = [];
  bool _done = false;

  SocketBuffer(this.socket) {
    socket.listen(
      (data) {
        _queue.addAll(data);
      },
      onDone: () => _done = true,
      onError: (_) => _done = true,
    );
  }

  Future<Uint8List?> readExact(int length, {Duration timeout = const Duration(seconds: 5)}) async {
    final stopwatch = Stopwatch()..start();
    while (_queue.length < length) {
      if (_done) return null;
      if (stopwatch.elapsed > timeout) return null;
      await Future.delayed(const Duration(milliseconds: 15));
    }
    final result = Uint8List.fromList(_queue.sublist(0, length));
    _queue.removeRange(0, length);
    return result;
  }
}

class IcqFlowerIcon extends StatelessWidget {
  final double size;
  const IcqFlowerIcon({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: IcqFlowerPainter(),
      ),
    );
  }
}

class IcqFlowerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintGreen = Paint()
      ..color = const Color(0xFF5A9E48)
      ..style = PaintingStyle.fill;

    final paintYellow = Paint()
      ..color = const Color(0xFFFFCC00)
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.22;
    final distance = size.width * 0.28;

    for (int i = 0; i < 5; i++) {
      final angle = i * 2 * math.pi / 5 - math.pi / 2;
      final offset = Offset(
        center.dx + math.cos(angle) * distance,
        center.dy + math.sin(angle) * distance,
      );
      canvas.drawCircle(offset, radius, paintGreen);
    }
    canvas.drawCircle(center, size.width * 0.16, paintYellow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==================== LOGIN SCREEN ====================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WindowListener {
  final _ipController = TextEditingController(text: '127.0.0.1');
  final _portController = TextEditingController(text: '6667');
  final _uinController = TextEditingController();
  final _pwdController = TextEditingController();
  
  bool _savePassword = false;
  bool _isLoading = false;
  String _errorMessage = '';

  static const int magicNumber = 0x4C494351; // 'LICQ'

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _loadSavedConfig();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMoved() => saveWindowBounds();

  @override
  void onWindowResized() => saveWindowBounds();

  Future<File> _getConfigfile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/icq_login_config.json');
  }

  Future<void> _loadSavedConfig() async {
    try {
      final file = await _getConfigfile();
      if (await file.exists()) {
        final contents = await file.readAsString();
        final data = jsonDecode(contents) as Map<String, dynamic>;
        setState(() {
          _ipController.text = data['ip'] ?? '127.0.0.1';
          _portController.text = data['port'] ?? '6667';
          _uinController.text = data['uin'] ?? '';
          _savePassword = data['savePassword'] ?? false;
          if (_savePassword) {
            _pwdController.text = data['password'] ?? '';
          }
        });
      }
    } catch (e) {
      debugPrint('Fehler beim Laden der Konfiguration: $e');
    }
  }

  Future<void> _saveConfig(String ip, String port, String uin, String password) async {
    try {
      final file = await _getConfigfile();
      final data = {
        'ip': ip,
        'port': port,
        'uin': uin,
        'savePassword': _savePassword,
        'password': _savePassword ? password : '',
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Fehler beim Speichern der Konfiguration: $e');
    }
  }

  Future<void> _performLogin() async {
    final serverAddress = _ipController.text.trim();
    final serverPort = int.tryParse(_portController.text.trim()) ?? 6667;
    final uin = _uinController.text.trim();
    final password = _pwdController.text;

    if (serverAddress.isEmpty || uin.length != 9 || password.isEmpty) {
      setState(() {
        _errorMessage = 'Bitte alle Felder korrekt ausfüllen (UIN = 9 Ziffern).';
      });
      return;
    }

    await _saveConfig(serverAddress, _portController.text.trim(), uin, password);

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    SecureSocket? socket;
    try {
      socket = await SecureSocket.connect(
        serverAddress,
        serverPort,
        onBadCertificate: (cert) => true,
      );

      final reader = SocketBuffer(socket);

      final magicData = ByteData(4);
      magicData.setUint32(0, magicNumber, Endian.little);
      socket.add(magicData.buffer.asUint8List());

      socket.add([ 'A'.codeUnitAt(0) ]);
      socket.add(uin.codeUnits);

      final pwdBytes = Uint8List.fromList(password.codeUnits);
      final pwdLenData = ByteData(2);
      pwdLenData.setInt16(0, pwdBytes.length, Endian.big);
      socket.add(pwdLenData.buffer.asUint8List());
      socket.add(pwdBytes);

      await socket.flush();

      final statusByte = await reader.readExact(1);
      if (statusByte == null || statusByte[0] != 1) {
        setState(() {
          _errorMessage = 'Login fehlgeschlagen: Falsches Passwort oder ungültige ID.';
          _isLoading = false;
        });
        socket.destroy();
        return;
      }

      final nickLenBytes = await reader.readExact(2);
      if (nickLenBytes == null) throw Exception('Fehler beim Lesen der Nickname-Länge');
      final nickLen = ByteData.view(nickLenBytes.buffer).getInt16(0, Endian.big);
      final nickBytes = await reader.readExact(nickLen);
      final nick = nickBytes != null ? String.fromCharCodes(nickBytes) : 'Unbekannt';

      final buddyCountBytes = await reader.readExact(2);
      final buddyCount = buddyCountBytes != null ? ByteData.view(buddyCountBytes.buffer).getInt16(0, Endian.big) : 0;

      List<Map<String, dynamic>> serverBuddies = [];
      for (int i = 0; i < buddyCount; i++) {
        final bUinLenBytes = await reader.readExact(2);
        if (bUinLenBytes == null) break;
        final bUinLen = ByteData.view(bUinLenBytes.buffer).getInt16(0, Endian.big);
        final bUinBytes = await reader.readExact(bUinLen);
        final bUin = bUinBytes != null ? String.fromCharCodes(bUinBytes) : '';

        final bNameLenBytes = await reader.readExact(2);
        if (bNameLenBytes == null) break;
        final bNameLen = ByteData.view(bNameLenBytes.buffer).getInt16(0, Endian.big);
        final bNameBytes = await reader.readExact(bNameLen);
        final bName = bNameBytes != null ? String.fromCharCodes(bNameBytes) : '';

        final bOnlineByte = await reader.readExact(1);
        final bOnline = bOnlineByte != null && bOnlineByte[0] == 1;

        String bAvatar = '';
        try {
          final avLenBytes = await reader.readExact(2);
          if (avLenBytes != null) {
            final avLen = ByteData.view(avLenBytes.buffer).getInt16(0, Endian.big);
            if (avLen > 0) {
              final avBytes = await reader.readExact(avLen);
              if (avBytes != null) bAvatar = String.fromCharCodes(avBytes);
            }
          }
        } catch (_) {}

        if (bUin.isNotEmpty) {
          serverBuddies.add({
            'uin': bUin,
            'name': bName,
            'online': bOnline,
            'avatar': bAvatar,
          });
        }
      }

      final msgCountBytes = await reader.readExact(4);
      final msgCount = msgCountBytes != null ? ByteData.view(msgCountBytes.buffer).getInt32(0, Endian.big) : 0;

      List<Map<String, dynamic>> messages = [];
      for (int i = 0; i < msgCount; i++) {
        final sIdLenBytes = await reader.readExact(2);
        if (sIdLenBytes == null) break;
        final sIdLen = ByteData.view(sIdLenBytes.buffer).getInt16(0, Endian.big);
        final senderIdBytes = await reader.readExact(sIdLen);
        final senderId = senderIdBytes != null ? String.fromCharCodes(senderIdBytes) : '';

        final sNickLenBytes = await reader.readExact(2);
        if (sNickLenBytes == null) break;
        final sNickLen = ByteData.view(sNickLenBytes.buffer).getInt16(0, Endian.big);
        final senderNickBytes = await reader.readExact(sNickLen);
        final senderNick = senderNickBytes != null ? String.fromCharCodes(senderNickBytes) : '';

        final kindByte = await reader.readExact(1);
        final kind = kindByte != null ? String.fromCharCode(kindByte[0]) : 'T';

        final tsLenBytes = await reader.readExact(2);
        if (tsLenBytes == null) break;
        final tsLen = ByteData.view(tsLenBytes.buffer).getInt16(0, Endian.big);
        final tsBytes = await reader.readExact(tsLen);
        final timestamp = tsBytes != null ? String.fromCharCodes(tsBytes) : '';

        final plLenBytes = await reader.readExact(4);
        if (plLenBytes == null) break;
        final plLen = ByteData.view(plLenBytes.buffer).getInt32(0, Endian.big);
        final payloadBytes = await reader.readExact(plLen);
        final payload = payloadBytes != null ? String.fromCharCodes(payloadBytes) : '';

        messages.add({
          'senderId': senderId,
          'senderNick': senderNick,
          'kind': kind,
          'timestamp': timestamp,
          'payload': payload,
        });
      }

      socket.destroy();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MainContactListScreen(
            uin: uin,
            nick: nick,
            initialBuddies: serverBuddies,
            initialMessages: messages,
            serverIp: serverAddress,
            serverPort: serverPort,
          ),
        ),
      );

    } catch (e) {
      setState(() {
        _errorMessage = 'Verbindungsfehler: $e';
        _isLoading = false;
      });
      socket?.destroy();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE2F0DE),
      body: WindowRegion(
        child: Column(
          children: [
            GestureDetector(
              onPanStart: (_) => windowManager.startDragging(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFA6D196), Color(0xFF6AA84F)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        IcqFlowerIcon(size: 16),
                        SizedBox(width: 8),
                        Text('ICQ Login', style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Row(
                      children: [
                        InkWell(
                          onTap: () => windowManager.minimize(),
                          child: Container(
                            width: 16, height: 16,
                            decoration: BoxDecoration(color: const Color(0xFF82B366), border: Border.all(color: Colors.white)),
                            child: const Icon(Icons.remove, size: 10, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 3),
                        InkWell(
                          onTap: () => windowManager.close(),
                          child: Container(
                            width: 16, height: 16,
                            decoration: BoxDecoration(color: const Color(0xFFCC4125), border: Border.all(color: Colors.white)),
                            child: const Icon(Icons.close, size: 12, color: Colors.white),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 380),
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2F0DE),
                      border: Border.all(color: const Color(0xFF6AA84F), width: 2),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [BoxShadow(color: Colors.black26, offset: Offset(3, 3), blurRadius: 6)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(flex: 3, child: TextField(controller: _ipController, style: const TextStyle(fontSize: 12), decoration: _icqInputDecoration('Server IP / Domain'))),
                            const SizedBox(width: 6),
                            Expanded(flex: 2, child: TextField(controller: _portController, keyboardType: TextInputType.number, style: const TextStyle(fontSize: 12), decoration: _icqInputDecoration('Port'))),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(controller: _uinController, maxLength: 9, keyboardType: TextInputType.number, style: const TextStyle(fontSize: 12), decoration: _icqInputDecoration('9-stellige UIN')),
                        const SizedBox(height: 6),
                        TextField(controller: _pwdController, obscureText: true, style: const TextStyle(fontSize: 12), decoration: _icqInputDecoration('Passwort')),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            SizedBox(height: 20, width: 20, child: Checkbox(value: _savePassword, onChanged: (val) => setState(() => _savePassword = val ?? false))),
                            const SizedBox(width: 6),
                            const Text('Passwort speichern', style: TextStyle(fontSize: 11, color: Colors.black87)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_errorMessage.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_errorMessage, style: const TextStyle(color: Colors.red, fontSize: 11))),
                        SizedBox(
                          height: 34,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFCC00),
                              foregroundColor: Colors.black87,
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              side: const BorderSide(color: Color(0xFFD4AC0D)),
                            ),
                            onPressed: _isLoading ? null : _performLogin,
                            child: _isLoading ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Anmelden / Registrieren', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _icqInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 11, color: Colors.black54),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFFB7D7A8))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFFB7D7A8))),
    );
  }
}

// ==================== HAUPTFENSTER ====================
class MainContactListScreen extends StatefulWidget {
  final String uin;
  final String nick;
  final List<Map<String, dynamic>> initialBuddies;
  final List<Map<String, dynamic>> initialMessages;
  final String serverIp;
  final int serverPort;

  const MainContactListScreen({
    super.key,
    required this.uin,
    required this.nick,
    required this.initialBuddies,
    required this.initialMessages,
    required this.serverIp,
    required this.serverPort,
  });

  @override
  State<MainContactListScreen> createState() => _MainContactListScreenState();
}

class _MainContactListScreenState extends State<MainContactListScreen> with WindowListener {
  List<Map<String, dynamic>> _buddies = [];
  late List<Map<String, dynamic>> _messages;
  String _myAvatarBase64 = '';

  // Einstellungen (Lautstärke, Ton, Schriftart, Schriftgröße)
  double _volume = 0.8;
  String _notificationSound = 'Classic Beep';
  String _fontFamily = 'Tahoma';
  double _fontSize = 11.0;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _messages = List.from(widget.initialMessages);
    _loadLocalData();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMoved() => saveWindowBounds();

  @override
  void onWindowResized() => saveWindowBounds();

  Future<File> _getDataFile(String suffix) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/icq_${widget.uin}_$suffix.json');
  }

  Future<void> _loadLocalData() async {
    List<Map<String, dynamic>> loadedBuddies = [];
    String loadedAvatar = '';

    try {
      final fileBuddies = await _getDataFile('buddies');
      if (await fileBuddies.exists()) {
        final contents = await fileBuddies.readAsString();
        if (contents.isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(contents);
          loadedBuddies = jsonList.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
    } catch (e) {
      debugPrint('Fehler beim Laden der lokalen Buddies: $e');
    }

    try {
      final fileAvatar = await _getDataFile('avatar');
      if (await fileAvatar.exists()) {
        loadedAvatar = await fileAvatar.readAsString();
      }
    } catch (e) {
      debugPrint('Fehler beim Laden des Avatars: $e');
    }

    setState(() {
      if (loadedBuddies.isNotEmpty) {
        _buddies = loadedBuddies;
      } else {
        _buddies = List.from(widget.initialBuddies);
        _saveLocalData();
      }
      _myAvatarBase64 = loadedAvatar;
    });
  }

  Future<void> _saveLocalData() async {
    try {
      final fileBuddies = await _getDataFile('buddies');
      await fileBuddies.writeAsString(jsonEncode(_buddies));

      final fileAvatar = await _getDataFile('avatar');
      await fileAvatar.writeAsString(_myAvatarBase64);
    } catch (e) {
      debugPrint('Fehler beim lokalen Speichern: $e');
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final bytes = await File(result.files.single.path!).readAsBytes();
        if (bytes.length > 200 * 1024) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bild ist zu groß (max. 200 KB empfohlen).')),
          );
          return;
        }

        final base64String = base64Encode(bytes);
        setState(() {
          _myAvatarBase64 = base64String;
        });

        await _saveLocalData();
        await _sendAvatarToServer(base64String);
      }
    } catch (e) {
      debugPrint('Avatar-Auswahl Fehler: $e');
    }
  }

  Future<void> _sendAvatarToServer(String base64Avatar) async {
    try {
      final socket = await SecureSocket.connect(
        widget.serverIp,
        widget.serverPort,
        onBadCertificate: (cert) => true,
      );

      final magicData = ByteData(4);
      magicData.setUint32(0, 0x4C494351, Endian.little);
      socket.add(magicData.buffer.asUint8List());

      socket.add([ 'P'.codeUnitAt(0) ]);
      socket.add(widget.uin.codeUnits);

      final avatarBytes = utf8.encode(base64Avatar);
      final lenData = ByteData(4);
      lenData.setInt32(0, avatarBytes.length, Endian.big);
      socket.add(lenData.buffer.asUint8List());
      socket.add(avatarBytes);

      await socket.flush();
      socket.destroy();
    } catch (e) {
      debugPrint('Avatar Server-Sync Fehler: $e');
    }
  }

  Future<void> _syncBuddiesWithServer() async {
    await _saveLocalData();
    try {
      final socket = await SecureSocket.connect(
        widget.serverIp,
        widget.serverPort,
        onBadCertificate: (cert) => true,
      );

      final magicData = ByteData(4);
      magicData.setUint32(0, 0x4C494351, Endian.little);
      socket.add(magicData.buffer.asUint8List());

      socket.add([ 'S'.codeUnitAt(0) ]);
      socket.add(widget.uin.codeUnits);

      final countData = ByteData(2);
      countData.setInt16(0, _buddies.length, Endian.big);
      socket.add(countData.buffer.asUint8List());

      for (var buddy in _buddies) {
        final uinBytes = buddy['uin'].toString().codeUnits;
        final uinLenData = ByteData(2);
        uinLenData.setInt16(0, uinBytes.length, Endian.big);
        socket.add(uinLenData.buffer.asUint8List());
        socket.add(uinBytes);

        final nameBytes = utf8.encode(buddy['name']);
        final nameLenData = ByteData(2);
        nameLenData.setInt16(0, nameBytes.length, Endian.big);
        socket.add(nameLenData.buffer.asUint8List());
        socket.add(nameBytes);
      }

      await socket.flush();
      socket.destroy();
    } catch (e) {
      debugPrint('Buddy-Sync Fehler: $e');
    }
  }

  void _showAddBuddyDialog() {
    final uinController = TextEditingController();
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Freund hinzufügen', style: TextStyle(fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: uinController,
              keyboardType: TextInputType.number,
              maxLength: 9,
              decoration: const InputDecoration(labelText: 'UIN (9 Ziffern)', isDense: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nickname / Name', isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () {
              final newUin = uinController.text.trim();
              final newName = nameController.text.trim();
              if (newUin.length == 9 && newName.isNotEmpty) {
                setState(() {
                  _buddies.add({
                    'uin': newUin,
                    'name': newName,
                    'online': false,
                    'avatar': '',
                  });
                });
                _syncBuddiesWithServer();
                Navigator.pop(context);
              }
            },
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );
  }

  void _showCreateGroupDialog() {
    final groupController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gruppe erstellen', style: TextStyle(fontSize: 14)),
        content: TextField(
          controller: groupController,
          decoration: const InputDecoration(labelText: 'Gruppenname', isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () {
              final groupName = groupController.text.trim();
              if (groupName.isNotEmpty) {
                // Gruppen-Logik oder Benachrichtigung
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Gruppe "$groupName" erstellt.')),
                );
                Navigator.pop(context);
              }
            },
            child: const Text('Erstellen'),
          ),
        ],
      ),
    );
  }

  // Untermenü für "Freund hinzufügen / Gruppe erstellen"
  void _showAddContactMenu(TapDownDetails details) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = details.globalPosition;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(position, position),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(
          value: 'add_friend',
          child: Row(
            children: [
              Icon(Icons.person_add, size: 16, color: Color(0xFF38761D)),
              SizedBox(width: 8),
              Text('Freund hinzufügen', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'create_group',
          child: Row(
            children: [
              Icon(Icons.group_add, size: 16, color: Color(0xFF38761D)),
              SizedBox(width: 8),
              Text('Gruppe erstellen', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'add_friend') {
        _showAddBuddyDialog();
      } else if (value == 'create_group') {
        _showCreateGroupDialog();
      }
    });
  }

  void _showInboxDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Posteingang (${_messages.length} Nachrichten)', style: const TextStyle(fontSize: 14)),
        content: SizedBox(
          width: 350,
          height: 300,
          child: _messages.isEmpty
              ? const Center(child: Text('Keine ungelesenen Nachrichten.', style: TextStyle(fontSize: 12)))
              : ListView.builder(
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${msg['senderNick']} (${msg['timestamp']}):', style: TextStyle(fontSize: _fontSize, fontWeight: FontWeight.bold, color: const Color(0xFF38761D))),
                            const SizedBox(height: 4),
                            Text(msg['payload'], style: TextStyle(fontSize: _fontSize)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _messages.clear();
              });
              Navigator.pop(context);
            },
            child: const Text('Alle als gelesen markieren'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  // Einstellungen-Menü beim Klick auf das Zahnrad
  void _showSettingsMenu(TapDownDetails details) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = details.globalPosition;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(position, position),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          enabled: false,
          child: StatefulBuilder(
            builder: (context, setMenuState) {
              return SizedBox(
                width: 220,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Lautstärke', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                    Row(
                      children: [
                        const Icon(Icons.volume_mute, size: 14),
                        Expanded(
                          child: Slider(
                            value: _volume,
                            min: 0.0,
                            max: 1.0,
                            divisions: 10,
                            onChanged: (val) {
                              setMenuState(() => _volume = val);
                              setState(() => _volume = val);
                            },
                          ),
                        ),
                        const Icon(Icons.volume_up, size: 14),
                      ],
                    ),
                    const Divider(),
                    const Text('Benachrichtigungston', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                    DropdownButton<String>(
                      value: _notificationSound,
                      isDense: true,
                      isExpanded: true,
                      items: ['Classic Beep', 'ICQ Chime', 'Bubble', 'Silent']
                          .map((sound) => DropdownMenuItem(value: sound, child: Text(sound, style: const TextStyle(fontSize: 11))))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setMenuState(() => _notificationSound = val);
                          setState(() => _notificationSound = val);
                        }
                      },
                    ),
                    const Divider(),
                    const Text('Schriftart', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                    DropdownButton<String>(
                      value: _fontFamily,
                      isDense: true,
                      isExpanded: true,
                      items: ['Tahoma', 'Arial', 'Courier']
                          .map((font) => DropdownMenuItem(value: font, child: Text(font, style: TextStyle(fontSize: 11, fontFamily: font))))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setMenuState(() => _fontFamily = val);
                          setState(() => _fontFamily = val);
                        }
                      },
                    ),
                    const Divider(),
                    const Text('Schriftgröße', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                    DropdownButton<double>(
                      value: _fontSize,
                      isDense: true,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 9.0, child: Text('Klein (9)', style: TextStyle(fontSize: 11))),
                        DropdownMenuItem(value: 11.0, child: Text('Normal (11)', style: TextStyle(fontSize: 11))),
                        DropdownMenuItem(value: 14.0, child: Text('Groß (14)', style: TextStyle(fontSize: 11))),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setMenuState(() => _fontSize = val);
                          setState(() => _fontSize = val);
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _openChatWindow(String buddyUin, String buddyName) async {
    try {
      final executable = Platform.resolvedExecutable;
      await Process.start(
        executable,
        ['chat', widget.uin, widget.nick, buddyUin, buddyName, widget.serverIp, widget.serverPort.toString()],
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      debugPrint('Fehler beim Öffnen des Chat-Fensters: $e');
    }
  }

  void _showBuddyContextMenu(TapDownDetails details, int index) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = details.globalPosition;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(position, position),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(value: 'rename', child: Text('Nickname ändern', style: TextStyle(fontSize: 12))),
        const PopupMenuItem(value: 'delete', child: Text('Kontakt löschen', style: TextStyle(fontSize: 12, color: Colors.red))),
      ],
    ).then((value) {
      if (value == 'rename') {
        _renameBuddy(index);
      } else if (value == 'delete') {
        setState(() {
          _buddies.removeAt(index);
        });
        _syncBuddiesWithServer();
      }
    });
  }

  void _renameBuddy(int index) {
    final controller = TextEditingController(text: _buddies[index]['name']);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nickname ändern', style: TextStyle(fontSize: 14)),
        content: TextField(controller: controller, decoration: const InputDecoration(isDense: true)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  _buddies[index]['name'] = controller.text.trim();
                });
                _syncBuddiesWithServer();
              }
              Navigator.pop(context);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(fontFamily: _fontFamily),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFD4E6D1),
        body: WindowRegion(
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFE2F0DE),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onPanStart: (_) => windowManager.startDragging(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFA6D196), Color(0xFF6AA84F)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const IcqFlowerIcon(size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'ICQ - ${widget.nick}',
                              style: TextStyle(fontSize: _fontSize + 1, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            InkWell(
                              onTap: () => windowManager.minimize(),
                              child: Container(
                                width: 16, height: 16,
                                decoration: BoxDecoration(color: const Color(0xFF82B366), border: Border.all(color: Colors.white)),
                                child: const Icon(Icons.remove, size: 10, color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 3),
                            InkWell(
                              onTap: () => windowManager.close(),
                              child: Container(
                                width: 16, height: 16,
                                decoration: BoxDecoration(color: const Color(0xFFCC4125), border: Border.all(color: Colors.white)),
                                child: const Icon(Icons.close, size: 12, color: Colors.white),
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                ),

                Container(
                  color: const Color(0xFFC4E0B3),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    children: [
                      Text('Main', style: TextStyle(fontSize: _fontSize, fontWeight: FontWeight.bold, decoration: TextDecoration.underline, color: const Color(0xFF2C5E1A))),
                      const SizedBox(width: 12),
                      Text('Update', style: TextStyle(fontSize: _fontSize, color: Colors.black54)),
                    ],
                  ),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  color: const Color(0xFFD4E6D1),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: _pickAndUploadAvatar,
                        child: Tooltip(
                          message: 'Eigenes Profilbild wählen & hochladen',
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF5A9E48), width: 1.5),
                              color: Colors.white,
                            ),
                            child: ClipOval(
                              child: _myAvatarBase64.isNotEmpty
                                  ? Image.memory(base64Decode(_myAvatarBase64), fit: BoxFit.cover)
                                  : const Icon(Icons.person, size: 16, color: Color(0xFF5A9E48)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Profilbild: ${widget.nick}',
                          style: TextStyle(fontSize: _fontSize, fontWeight: FontWeight.bold, color: const Color(0xFF2C5E1A)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(50, 20),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _pickAndUploadAvatar,
                        child: Text('Ändern', style: TextStyle(fontSize: _fontSize - 1, color: const Color(0xFF38761D), fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  color: const Color(0xFFE2F0DE),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      GestureDetector(
                        onTapDown: (details) => _showSettingsMenu(details),
                        child: const Tooltip(
                          message: 'Einstellungen (Lautstärke, Ton, Schriftart)',
                          child: Icon(Icons.settings, size: 16, color: Color(0xFF38761D)),
                        ),
                      ),
                      GestureDetector(
                        onTapDown: (details) => _showAddContactMenu(details),
                        child: const Tooltip(
                          message: 'Kontakt / Gruppe hinzufügen',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.group, size: 16, color: Color(0xFF38761D)),
                              Icon(Icons.arrow_drop_down, size: 14, color: Color(0xFF38761D)),
                            ],
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: _showInboxDialog,
                        child: Tooltip(
                          message: 'Posteingang (${_messages.length} ungelesen)',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.chat_bubble, size: 16, color: Color(0xFFCC4125)),
                              if (_messages.isNotEmpty) ...[
                                const SizedBox(width: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFCC4125),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${_messages.length}',
                                    style: TextStyle(fontSize: _fontSize - 2, color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFF93C47D)),
                    ),
                    child: ListView(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          color: const Color(0xFFF2F9EE),
                          child: Row(
                            children: [
                              const Icon(Icons.remove_circle_outline, size: 12, color: Color(0xFF38761D)),
                              const SizedBox(width: 4),
                              Text('Buddies (0/${_buddies.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: _fontSize, color: const Color(0xFF38761D))),
                            ],
                          ),
                        ),
                        for (int i = 0; i < _buddies.length; i++)
                          GestureDetector(
                            onSecondaryTapDown: (details) => _showBuddyContextMenu(details, i),
                            child: InkWell(
                              onTap: () => _openChatWindow(_buddies[i]['uin'], _buddies[i]['name']),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                decoration: const BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(color: const Color(0xFF93C47D), width: 1),
                                      ),
                                      child: ClipOval(
                                        child: (_buddies[i]['avatar'] != null && (_buddies[i]['avatar'] as String).isNotEmpty)
                                            ? Image.memory(base64Decode(_buddies[i]['avatar']), fit: BoxFit.cover)
                                            : const IcqFlowerIcon(size: 14),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(_buddies[i]['name'], style: TextStyle(fontSize: _fontSize, fontWeight: FontWeight.bold, color: const Color(0xFF134F2C))),
                                        Text(_buddies[i]['online'] == true ? 'Online' : 'Offline', style: TextStyle(fontSize: _fontSize - 2, color: _buddies[i]['online'] == true ? Colors.green : Colors.grey)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                Container(
                  height: 14,
                  color: const Color(0xFFD4E6D1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WindowRegion extends StatelessWidget {
  final Widget child;
  const WindowRegion({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: child,
    );
  }
}

// ==================== EIGENSTÄNDIGES CHAT-FENSTER ====================
class StandaloneChatWindow extends StatefulWidget {
  final String uin;
  final String nick;
  final String targetUin;
  final String targetNick;
  final String serverIp;
  final int serverPort;

  const StandaloneChatWindow({
    super.key,
    required this.uin,
    required this.nick,
    required this.targetUin,
    required this.targetNick,
    required this.serverIp,
    required this.serverPort,
  });

  @override
  State<StandaloneChatWindow> createState() => _StandaloneChatWindowState();
}

class _StandaloneChatWindowState extends State<StandaloneChatWindow> with WindowListener {
  final TextEditingController _msgController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    _msgController.clear();
    setState(() => _isSending = true);

    try {
      final socket = await SecureSocket.connect(
        widget.serverIp,
        widget.serverPort,
        onBadCertificate: (cert) => true,
      );

      final magicData = ByteData(4);
      magicData.setUint32(0, 0x4C494351, Endian.little);
      socket.add(magicData.buffer.asUint8List());

      socket.add([ 'M'.codeUnitAt(0) ]);
      socket.add(widget.uin.codeUnits);
      socket.add(widget.targetUin.codeUnits);
      socket.add([ 'T'.codeUnitAt(0) ]);

      final textBytes = utf8.encode(text);
      final lenData = ByteData(4);
      lenData.setInt32(0, textBytes.length, Endian.big);
      socket.add(lenData.buffer.asUint8List());
      socket.add(textBytes);

      await socket.flush();
      socket.destroy();

      setState(() {
        _messages.add({
          'senderNick': widget.nick,
          'timestamp': DateTime.now().toString().substring(11, 19),
          'payload': text,
        });
      });
    } catch (e) {
      debugPrint('Sende-Fehler: $e');
    } finally {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: WindowRegion(
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFE2F0DE),
            border: Border.all(color: const Color(0xFF6AA84F), width: 2),
          ),
          child: Column(
            children: [
              GestureDetector(
                onPanStart: (_) => windowManager.startDragging(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFA6D196), Color(0xFF6AA84F)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const IcqFlowerIcon(size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'Chat mit ${widget.targetNick}',
                            style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          InkWell(
                            onTap: () => windowManager.minimize(),
                            child: Container(
                              width: 16, height: 16,
                              decoration: BoxDecoration(color: const Color(0xFF82B366), border: Border.all(color: Colors.white)),
                              child: const Icon(Icons.remove, size: 10, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 3),
                          InkWell(
                            onTap: () => windowManager.close(),
                            child: Container(
                              width: 16, height: 16,
                              decoration: BoxDecoration(color: const Color(0xFFCC4125), border: Border.all(color: Colors.white)),
                              child: const Icon(Icons.close, size: 12, color: Colors.white),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFF93C47D)),
                  ),
                  child: _messages.isEmpty
                      ? const Center(child: Text('Keine Nachrichten bisher...', style: TextStyle(fontSize: 11, color: Colors.black54)))
                      : ListView.builder(
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages.length > index ? _messages[index] : null;
                            if (msg == null) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.all(6.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${msg['senderNick']} (${msg['timestamp']}):', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF38761D))),
                                  const SizedBox(height: 2),
                                  Text(msg['payload'], style: const TextStyle(fontSize: 12, color: Colors.black87)),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                color: const Color(0xFFE2F0DE),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _msgController,
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          hintText: 'Nachricht eingeben...',
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF93C47D))),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFCC00), foregroundColor: Colors.black87, minimumSize: const Size(60, 36)),
                      onPressed: _isSending ? null : _sendMessage,
                      child: const Text('Senden', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}