import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pw;
import 'package:pdf/widgets.dart' as pwWidgets;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as excelPkg;
import 'package:local_auth/local_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';

// دالة موحدة لتوليد تاريخ اليوم بالصيغة الرسمية الجزائرية DD/MM/YYYY
String todayStr() {
  final now = DateTime.now();
  final d = now.day.toString().padLeft(2, '0');
  final m = now.month.toString().padLeft(2, '0');
  return '$d/$m/${now.year}';
}

// دالة موحدة لتوليد الوقت الحالي بالصيغة الرسمية HH:mm
String currentTimeStr() {
  final now = DateTime.now();
  final h = now.hour.toString().padLeft(2, '0');
  final m = now.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SchoolData.loadData();
  final initialDarkMode = await SchoolData.loadThemeMode();
  runApp(EducationalRegisterApp(initialDarkMode: initialDarkMode));
}

// ============================================================================
// 1. نماذج البيانات (DATA MODELS)
// ============================================================================

class BehaviorLog {
  final String description;
  final int pointsChange;
  final String time;
  final String? reason;
  final String date;

  BehaviorLog({
    required this.description,
    required this.pointsChange,
    required this.time,
    this.reason,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'description': description,
        'pointsChange': pointsChange,
        'time': time,
        'reason': reason,
        'date': date,
      };

  factory BehaviorLog.fromJson(Map<String, dynamic> json) => BehaviorLog(
        description: json['description'] ?? '',
        pointsChange: json['pointsChange'] is int ? json['pointsChange'] : 0,
        time: json['time'] ?? '',
        reason: json['reason'],
        date: json['date'] ?? todayStr(),
      );
}

class LessonNote {
  String date;
  String title;
  String summary;
  String homework;

  LessonNote({
    required this.date,
    required this.title,
    required this.summary,
    required this.homework,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'title': title,
        'summary': summary,
        'homework': homework,
      };

  factory LessonNote.fromJson(Map<String, dynamic> json) => LessonNote(
        date: json['date'] ?? todayStr(),
        title: json['title'] ?? '',
        summary: json['summary'] ?? '',
        homework: json['homework'] ?? '',
      );
}

class AttendanceDetail {
  String status; // حاضر، غائب، متأخر، هروب، خروج بإذن، معفى
  String? time;   // مثال: 08:25
  String? reason; // مثال: عيادة طبية / استدعاء إدارة

  AttendanceDetail({
    required this.status,
    this.time,
    this.reason,
  });

  Map<String, dynamic> toJson() => {
        'status': status,
        'time': time,
        'reason': reason,
      };

  factory AttendanceDetail.fromJson(dynamic json) {
    if (json is String) {
      return AttendanceDetail(status: json);
    }
    return AttendanceDetail(
      status: json['status'] ?? 'حاضر',
      time: json['time'],
      reason: json['reason'],
    );
  }
}

class DailyAttendanceRecord {
  String date;
  Map<String, AttendanceDetail> studentStatuses; // regNumber -> AttendanceDetail

  DailyAttendanceRecord({
    required this.date,
    required this.studentStatuses,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'studentStatuses':
            studentStatuses.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory DailyAttendanceRecord.fromJson(Map<String, dynamic> json) {
    Map<String, AttendanceDetail> details = {};
    if (json['studentStatuses'] != null) {
      (json['studentStatuses'] as Map).forEach((k, v) {
        details[k.toString()] = AttendanceDetail.fromJson(v);
      });
    }
    return DailyAttendanceRecord(
      date: json['date'] ?? todayStr(),
      studentStatuses: details,
    );
  }
}

// ✅ السجل اليومي للقسم بالوقت والتاريخ
class ClassDailyLogEntry {
  final String date;
  final String time;
  final String action; // تعديل علامة، إضافة تلميذ، حذف تلميذ، تسجيل حضور، استيراد إلخ
  final String details;
  final String performedBy; // اسم المستخدم / الأستاذ الذي نفذ الإجراء

  ClassDailyLogEntry({
    required this.date,
    required this.time,
    required this.action,
    required this.details,
    required this.performedBy,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'time': time,
        'action': action,
        'details': details,
        'performedBy': performedBy,
      };

  factory ClassDailyLogEntry.fromJson(Map<String, dynamic> json) =>
      ClassDailyLogEntry(
        date: json['date'] ?? todayStr(),
        time: json['time'] ?? currentTimeStr(),
        action: json['action'] ?? '',
        details: json['details'] ?? '',
        performedBy: json['performedBy'] ?? '',
      );
}

// ✅ سجل كل تلميذ لوحده بالوقت والتاريخ بالضبط
class StudentPersonalLogEntry {
  final String date;
  final String time;
  final String action; // ملاحظة سلوكية، استدعاء ولي، تعديل بيانات، إلخ
  final String details;
  final String performedBy;

  StudentPersonalLogEntry({
    required this.date,
    required this.time,
    required this.action,
    required this.details,
    required this.performedBy,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'time': time,
        'action': action,
        'details': details,
        'performedBy': performedBy,
      };

  factory StudentPersonalLogEntry.fromJson(Map<String, dynamic> json) =>
      StudentPersonalLogEntry(
        date: json['date'] ?? todayStr(),
        time: json['time'] ?? currentTimeStr(),
        action: json['action'] ?? '',
        details: json['details'] ?? '',
        performedBy: json['performedBy'] ?? '',
      );
}

class TimetableItem {
  String day;
  String timeSlot;
  String className;
  String room;

  TimetableItem({
    required this.day,
    required this.timeSlot,
    required this.className,
    required this.room,
  });

  Map<String, dynamic> toJson() => {
        'day': day,
        'timeSlot': timeSlot,
        'className': className,
        'room': room,
      };

  factory TimetableItem.fromJson(Map<String, dynamic> json) => TimetableItem(
        day: json['day'] ?? 'الأحد',
        timeSlot: json['timeSlot'] ?? '08:00 - 09:00',
        className: json['className'] ?? '',
        room: json['room'] ?? '',
      );
}

class Student {
  String firstName;
  String lastName;
  String regNumber;
  String birthDate;
  String birthPlace;
  String status; // حاضر، غائب، متأخر، هروب، خروج بإذن، معفى
  String? statusTime; // وقت تسجيل التأخر أو الهروب أو الخروج
  String? statusReason; // سبب الإذن أو ملاحظة الواقعة
  double continuousEval;
  double exam1;
  double exam2;
  double test;
  double coefficient;
  int points;
  List<BehaviorLog> logs;

  // ✅ سجل تلميذ فردي
  List<StudentPersonalLogEntry> personalLogs;

  Student({
    required this.firstName,
    required this.lastName,
    required this.regNumber,
    required this.birthDate,
    required this.birthPlace,
    this.status = 'حاضر',
    this.statusTime,
    this.statusReason,
    this.continuousEval = 10.0,
    this.exam1 = 10.0,
    this.exam2 = 0.0,
    this.test = 10.0,
    this.coefficient = 1.0,
    this.points = 0,
    List<BehaviorLog>? logs,
    List<StudentPersonalLogEntry>? personalLogs,
  })  : logs = logs ?? [],
        personalLogs = personalLogs ?? [];

  /// حساب معدل المادة وفق المنظومة الرسمية الجزائرية
  double get average {
    double continuousMonitoring;
    if (exam2 > 0.0) {
      continuousMonitoring = (continuousEval + ((exam1 + exam2) / 2.0)) / 2.0;
    } else {
      continuousMonitoring = (continuousEval + exam1) / 2.0;
    }
    return (continuousMonitoring + (test * 2.0)) / 3.0;
  }

  /// التقدير البيداغوجي المعتمد
  String get appreciation {
    final avg = average;
    if (avg >= 18.0) return 'ممتاز';
    if (avg >= 16.0) return 'جيد جداً';
    if (avg >= 14.0) return 'جيد';
    if (avg >= 12.0) return 'قريب من الجيد';
    if (avg >= 10.0) return 'متوسط';
    if (avg >= 8.0) return 'دون المتوسط';
    return 'ضعيف';
  }

  /// قرار مجلس الأقسام الشرفي
  String get councilDecision {
    final avg = average;
    if (avg >= 16.0) return 'تهنئة + لوحة شرف';
    if (avg >= 14.0) return 'تشجيع + لوحة شرف';
    if (avg >= 12.0) return 'لوحة شرف';
    if (avg >= 10.0) return 'ينتقل';
    if (avg >= 8.0) return 'إنذار بالمواظبة';
    return 'توبيخ وطلب لقاء الولي';
  }

  Map<String, dynamic> toJson() => {
        'firstName': firstName,
        'lastName': lastName,
        'regNumber': regNumber,
        'birthDate': birthDate,
        'birthPlace': birthPlace,
        'status': status,
        'statusTime': statusTime,
        'statusReason': statusReason,
        'continuousEval': continuousEval,
        'exam1': exam1,
        'exam2': exam2,
        'test': test,
        'coefficient': coefficient,
        'points': points,
        'logs': logs.map((l) => l.toJson()).toList(),
        // ✅ حفظ سجل التلميذ الفردي
        'personalLogs': personalLogs.map((l) => l.toJson()).toList(),
      };

  factory Student.fromJson(Map<String, dynamic> json) => Student(
        firstName: json['firstName'] ?? '',
        lastName: json['lastName'] ?? '',
        regNumber: json['regNumber'] ?? '',
        birthDate: json['birthDate'] ?? '',
        birthPlace: json['birthPlace'] ?? '',
        status: json['status'] ?? 'حاضر',
        statusTime: json['statusTime'],
        statusReason: json['statusReason'],
        continuousEval: (json['continuousEval'] as num?)?.toDouble() ?? 10.0,
        exam1: (json['exam1'] as num?)?.toDouble() ?? 10.0,
        exam2: (json['exam2'] as num?)?.toDouble() ?? 0.0,
        test: (json['test'] as num?)?.toDouble() ?? 10.0,
        coefficient: (json['coefficient'] as num?)?.toDouble() ?? 1.0,
        points: json['points'] is int ? json['points'] : 0,
        logs: json['logs'] != null
            ? (json['logs'] as List)
                .map((l) => BehaviorLog.fromJson(l))
                .toList()
            : [],
        // ✅ استرجاع سجل التلميذ الفردي
        personalLogs: json['personalLogs'] != null
            ? (json['personalLogs'] as List)
                .map((l) => StudentPersonalLogEntry.fromJson(l))
                .toList()
            : [],
      );
}

class SchoolClass {
  String name;
  List<Student> students;
  List<LessonNote> lessonNotes;
  List<DailyAttendanceRecord> dailyRecords;

  // ✅ سجل القسم اليومي
  List<ClassDailyLogEntry> dailyLogs;

  SchoolClass({
    required this.name,
    required this.students,
    List<LessonNote>? lessonNotes,
    List<DailyAttendanceRecord>? dailyRecords,
    List<ClassDailyLogEntry>? dailyLogs,
  })  : lessonNotes = lessonNotes ?? [],
        dailyRecords = dailyRecords ?? [],
        dailyLogs = dailyLogs ?? [];

  Map<String, dynamic> toJson() => {
        'name': name,
        'students': students.map((s) => s.toJson()).toList(),
        'lessonNotes': lessonNotes.map((l) => l.toJson()).toList(),
        'dailyRecords': dailyRecords.map((d) => d.toJson()).toList(),
        // ✅ حفظ سجل القسم اليومي
        'dailyLogs': dailyLogs.map((d) => d.toJson()).toList(),
      };

  factory SchoolClass.fromJson(Map<String, dynamic> json) => SchoolClass(
        name: json['name'] ?? '',
        students: json['students'] != null
            ? (json['students'] as List)
                .map((s) => Student.fromJson(s))
                .toList()
            : [],
        lessonNotes: json['lessonNotes'] != null
            ? (json['lessonNotes'] as List)
                .map((l) => LessonNote.fromJson(l))
                .toList()
            : [],
        dailyRecords: json['dailyRecords'] != null
            ? (json['dailyRecords'] as List)
                .map((d) => DailyAttendanceRecord.fromJson(d))
                .toList()
            : [],
        // ✅ استرجاع سجل القسم اليومي
        dailyLogs: json['dailyLogs'] != null
            ? (json['dailyLogs'] as List)
                .map((d) => ClassDailyLogEntry.fromJson(d))
                .toList()
            : [],
      );
}

class Teacher {
  String name;
  String subject;
  String? imagePath;
  List<SchoolClass> classes;
  List<TimetableItem> timetable;

  Teacher({
    required this.name,
    required this.subject,
    this.imagePath,
    List<SchoolClass>? classes,
    List<TimetableItem>? timetable,
  })  : classes = classes ?? [],
        timetable = timetable ?? [];

  Map<String, dynamic> toJson() => {
        'name': name,
        'subject': subject,
        'imagePath': imagePath,
        'classes': classes.map((c) => c.toJson()).toList(),
        'timetable': timetable.map((t) => t.toJson()).toList(),
      };

  factory Teacher.fromJson(Map<String, dynamic> json) => Teacher(
        name: json['name'] ?? '',
        subject: json['subject'] ?? '',
        imagePath: json['imagePath'],
        classes: json['classes'] != null
            ? (json['classes'] as List)
                .map((c) => SchoolClass.fromJson(c))
                .toList()
            : [],
        timetable: json['timetable'] != null
            ? (json['timetable'] as List)
                .map((t) => TimetableItem.fromJson(t))
                .toList()
            : [],
      );
}

class Institution {
  String name;
  List<Teacher> teachers;

  Institution({required this.name, List<Teacher>? teachers})
      : teachers = teachers ?? [];

  Map<String, dynamic> toJson() => {
        'name': name,
        'teachers': teachers.map((t) => t.toJson()).toList(),
      };

  factory Institution.fromJson(Map<String, dynamic> json) => Institution(
        name: json['name'] ?? '',
        teachers: json['teachers'] != null
            ? (json['teachers'] as List)
                .map((t) => Teacher.fromJson(t))
                .toList()
            : [],
      );
}

// ============================================================================
// 2. إدارة التخزين وحفظ النمط الدائم (STORAGE & PERSISTENCE)
// ============================================================================

class SchoolData {
  static List<Institution> institutions = [];
  static String appPin = "1234";
  static const String _themePrefKey = "app_persisted_dark_mode";

  static Future<void> saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'institutionsData', jsonEncode(institutions.map((i) => i.toJson()).toList()));
    await prefs.setString('appPin', appPin);
  }

  // ✅ حفظ الوضع الليلي في الذاكرة الدائمة
  static Future<void> saveThemeMode(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themePrefKey, isDark);
  }

  // ✅ استرجاع الوضع الليلي الدائم عند فتح التطبيق
  static Future<bool> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_themePrefKey) ?? false;
  }

  static Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    appPin = prefs.getString('appPin') ?? "1234";
    String? dataStr = prefs.getString('institutionsData');
    if (dataStr != null) {
      try {
        List<dynamic> decoded = jsonDecode(dataStr);
        institutions = decoded.map((i) => Institution.fromJson(i)).toList();
      } catch (e) {
        _initSampleData();
      }
    } else {
      _initSampleData();
    }
  }

  static void _initSampleData() {
    institutions = [
      Institution(
        name: 'ثانوية السكومي نوري - الجلفة',
        teachers: [
          Teacher(
            name: 'الأستاذ: عبد الرحمن',
            subject: 'الرياضيات',
            timetable: [
              TimetableItem(
                  day: 'الأحد',
                  timeSlot: '08:00 - 10:00',
                  className: '3 ثانوي رياضيات 1',
                  room: 'قاعة 04'),
            ],
            classes: [
              SchoolClass(
                name: '3 ثانوي رياضيات 1',
                students: [
                  Student(
                      firstName: 'أحمد',
                      lastName: 'بن علي',
                      regNumber: '2026101',
                      birthDate: '15/05/2007',
                      birthPlace: 'الجلفة',
                      continuousEval: 17.5,
                      exam1: 16.0,
                      exam2: 17.0,
                      test: 18.0),
                  Student(
                      firstName: 'فاطمة الزهراء',
                      lastName: 'قاسمي',
                      regNumber: '2026102',
                      birthDate: '22/08/2007',
                      birthPlace: 'الجلفة',
                      continuousEval: 18.5,
                      exam1: 17.5,
                      exam2: 19.0,
                      test: 18.5),
                  Student(
                      firstName: 'يوسف',
                      lastName: 'إبراهيمي',
                      regNumber: '2026103',
                      birthDate: '10/02/2007',
                      birthPlace: 'الجلفة',
                      continuousEval: 12.0,
                      exam1: 11.5,
                      exam2: 0.0,
                      test: 11.0),
                  Student(
                      firstName: 'سارة',
                      lastName: 'محدادي',
                      regNumber: '2026104',
                      birthDate: '03/11/2007',
                      birthPlace: 'الجلفة',
                      continuousEval: 09.0,
                      exam1: 08.5,
                      exam2: 0.0,
                      test: 08.0),
                ],
              )
            ],
          )
        ],
      )
    ];
  }

  static String exportBackupJson() =>
      jsonEncode(institutions.map((i) => i.toJson()).toList());

  static Future<bool> importBackupJson(String jsonString) async {
    try {
      List<dynamic> decoded = jsonDecode(jsonString);
      institutions = decoded.map((i) => Institution.fromJson(i)).toList();
      await saveData();
      return true;
    } catch (e) {
      return false;
    }
  }
}

int compareArabicNames(String a, String b) {
  String normalize(String str) {
    return str
        .replaceAll(RegExp(r'[أإآا]'), 'ا')
        .replaceAll(RegExp(r'ة'), 'ه')
        .replaceAll(RegExp(r'ى'), 'ي')
        .trim();
  }
  return normalize(a).compareTo(normalize(b));
}

double? parseGrade(String val) {
  String cleaned = val.trim().replaceAll(',', '.');
  double? parsed = double.tryParse(cleaned);
  if (parsed != null && parsed >= 0.0 && parsed <= 20.0) {
    return parsed;
  }
  return null;
}

String extractCellString(dynamic cell) {
  if (cell == null) return '';
  try {
    dynamic val = cell.value;
    if (val == null) return '';
    return val.toString().trim();
  } catch (_) {
    return cell.toString().trim();
  }
}

// ============================================================================
// 3. التطبيق والهوية البصرية الرسمية (APPLICATION THEME)
// ============================================================================

class EducationalRegisterApp extends StatefulWidget {
  final bool initialDarkMode;
  const EducationalRegisterApp({super.key, this.initialDarkMode = false});

  @override
  State<EducationalRegisterApp> createState() => _EducationalRegisterAppState();
}

class _EducationalRegisterAppState extends State<EducationalRegisterApp> {
  late bool _isDarkMode;
  bool _isLocked = true;

  @override
  void initState() {
    super.initState();
    _isDarkMode = widget.initialDarkMode;
    SchoolData.loadData().then((_) {
      if (mounted) setState(() {});
    });
  }

  // ✅ تبديل النمط وحفظه فوراً في الذاكرة الدائمة
  void _toggleTheme() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
    SchoolData.saveThemeMode(_isDarkMode);
  }

  void _unlockApp() {
    setState(() {
      _isLocked = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    const deepNavy = Color(0xFF0F172A);
    const emeraldAccent = Color(0xFF059669);
    const royalGold = Color(0xFFD97706);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'السجل التربوي التنفيذي Pro 2026',
      locale: const Locale('ar', 'DZ'),
      supportedLocales: const [Locale('ar', 'DZ'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        cardColor: Colors.white,
        fontFamily: 'Cairo',
        colorScheme: const ColorScheme.light(
          primary: deepNavy,
          secondary: emeraldAccent,
          tertiary: royalGold,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: deepNavy,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B132B),
        cardColor: const Color(0xFF1E293B),
        fontFamily: 'Cairo',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B82F6),
          secondary: Color(0xFF10B981),
          tertiary: Color(0xFFF59E0B),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B132B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: _isLocked
          ? PinLockScreen(onUnlock: _unlockApp)
          : InstitutionsListScreen(
              onThemeToggle: _toggleTheme, isDarkMode: _isDarkMode),
    );
  }
}

// ============================================================================
// 4. شاشة الحماية وقفل التطبيق (PIN & BIOMETRIC AUTH)
// ============================================================================

class PinLockScreen extends StatefulWidget {
  final VoidCallback onUnlock;
  const PinLockScreen({super.key, required this.onUnlock});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  final TextEditingController _pinController = TextEditingController();
  final LocalAuthentication _auth = LocalAuthentication();
  String errorMessage = "";
  int attempts = 0;

  @override
  void initState() {
    super.initState();
    _checkBiometricsAutomatically();
  }

  Future<void> _checkBiometricsAutomatically() async {
    try {
      bool canCheck =
          await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      if (canCheck) {
        bool authenticated = await _auth.authenticate(
          localizedReason: 'المصادقة لفتح السجل التربوي 2026',
        );
        if (authenticated) {
          widget.onUnlock();
        }
      }
    } catch (e) {
      debugPrint("Biometric error: $e");
    }
  }

  void _verifyPin() {
    if (_pinController.text == SchoolData.appPin) {
      widget.onUnlock();
    } else {
      setState(() {
        attempts++;
        errorMessage = "رمز المرور غير صحيح! (المحاولة: $attempts)";
        _pinController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B132B), Color(0xFF1C2541), Color(0xFF047857)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 12,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shield_outlined,
                        size: 54, color: Color(0xFFD97706)),
                    const SizedBox(height: 16),
                    const Text('السجل التربوي التنفيذي Pro',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('أدخل رمز المرور الافتراضي (1234) أو البصمة',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 4,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 28,
                          letterSpacing: 12,
                          fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16)),
                        counterText: "",
                        hintText: "••••",
                      ),
                      onSubmitted: (_) => _verifyPin(),
                    ),
                    if (errorMessage.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(errorMessage,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12)),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16))),
                        onPressed: _verifyPin,
                        child: const Text('دخول النظام',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _checkBiometricsAutomatically,
                      icon: const Icon(Icons.fingerprint,
                          color: Color(0xFF059669)),
                      label: const Text('المصادقة بالبصمة البيومترية',
                          style: TextStyle(
                              color: Color(0xFF059669),
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 5. شاشة المؤسسات التربوية (INSTITUTIONS SCREEN)
// ============================================================================

class InstitutionsListScreen extends StatefulWidget {
  const InstitutionsListScreen(
      {super.key, required this.onThemeToggle, required this.isDarkMode});
  final VoidCallback onThemeToggle;
  final bool isDarkMode;

  @override
  State<InstitutionsListScreen> createState() => _InstitutionsListScreenState();
}

class _InstitutionsListScreenState extends State<InstitutionsListScreen> {
  void _showInstitutionDialog({Institution? institution}) {
    final nameCtrl = TextEditingController(text: institution?.name ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(institution == null
            ? 'إضافة مؤسسة تربوية'
            : 'تعديل اسم المؤسسة'),
        content: TextField(
            controller: nameCtrl,
            decoration:
                const InputDecoration(labelText: 'اسم المؤسسة والولاية')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white),
            onPressed: () async {
              if (nameCtrl.text.trim().isNotEmpty) {
                setState(() {
                  if (institution == null) {
                    SchoolData.institutions
                        .add(Institution(name: nameCtrl.text.trim()));
                  } else {
                    institution.name = nameCtrl.text.trim();
                  }
                });
                await SchoolData.saveData();
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _deleteInstitution(Institution institution) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المؤسسة'),
        content: Text('هل أنت متأكد من حذف مؤسسة "${institution.name}"؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              setState(() {
                SchoolData.institutions.remove(institution);
              });
              await SchoolData.saveData();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  void _changePinDialog() {
    final pinCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تغيير رمز الحماية (PIN)'),
        content: TextField(
          controller: pinCtrl,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          decoration:
              const InputDecoration(labelText: 'الرمز السري الجديد (4 أرقام)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (pinCtrl.text.length == 4) {
                SchoolData.appPin = pinCtrl.text;
                await SchoolData.saveData();
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('تم تحديث رمز الحماية بنجاح!')));
                }
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المؤسسات التربوية Pro 2026',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
              icon: const Icon(Icons.lock_reset),
              tooltip: 'تغيير رمز PIN',
              onPressed: _changePinDialog),
          IconButton(
              icon:
                  Icon(widget.isDarkMode ? Icons.light_mode : Icons.dark_mode),
              onPressed: widget.onThemeToggle),
        ],
      ),
      body: SchoolData.institutions.isEmpty
          ? const Center(child: Text('لا توجد مؤسسات تعليمية مسجلة بعد.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: SchoolData.institutions.length,
              itemBuilder: (context, index) {
                final inst = SchoolData.institutions[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.account_balance,
                          color: Color(0xFFF59E0B)),
                    ),
                    title: Text(inst.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 17)),
                    subtitle: Text('عدد الأساتذة: ${inst.teachers.length}',
                        style: const TextStyle(color: Colors.grey)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            icon:
                                const Icon(Icons.edit, color: Colors.blueGrey),
                            onPressed: () =>
                                _showInstitutionDialog(institution: inst)),
                        IconButton(
                            icon: const Icon(Icons.delete,
                                color: Colors.redAccent),
                            onPressed: () => _deleteInstitution(inst)),
                        const Icon(Icons.arrow_forward_ios, size: 16),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => TeachersListScreen(
                                  institution: inst,
                                  onThemeToggle: widget.onThemeToggle,
                                  isDarkMode: widget.isDarkMode))).then(
                          (_) => setState(() {}));
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: const Color(0xFFF59E0B),
        onPressed: () => _showInstitutionDialog(),
        icon: const Icon(Icons.add_business),
        label: const Text('إضافة مؤسسة'),
      ),
    );
  }
}

// ============================================================================
// 6. شاشة الأساتذة والمواد (TEACHERS SCREEN)
// ============================================================================

class TeachersListScreen extends StatefulWidget {
  final Institution institution;
  final VoidCallback onThemeToggle;
  final bool isDarkMode;
  const TeachersListScreen(
      {super.key,
      required this.institution,
      required this.onThemeToggle,
      required this.isDarkMode});

  @override
  State<TeachersListScreen> createState() => _TeachersListScreenState();
}

class _TeachersListScreenState extends State<TeachersListScreen> {
  void _showTeacherDialog({Teacher? teacher}) {
    final nameCtrl = TextEditingController(text: teacher?.name ?? '');
    final subjectCtrl = TextEditingController(text: teacher?.subject ?? '');
    String? tempImagePath = teacher?.imagePath;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
              teacher == null ? 'إضافة أستاذ جديد' : 'تعديل بيانات الأستاذ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    try {
                      final picker = ImagePicker();
                      final pickedFile =
                          await picker.pickImage(source: ImageSource.gallery);
                      if (pickedFile != null) {
                        setDialogState(() {
                          tempImagePath = pickedFile.path;
                        });
                      }
                    } catch (_) {}
                  },
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.grey.shade300,
                    backgroundImage: tempImagePath != null
                        ? FileImage(File(tempImagePath!))
                        : null,
                    child: tempImagePath == null
                        ? const Icon(Icons.camera_alt,
                            size: 28, color: Colors.grey)
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: nameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'اسم الأستاذ')),
                const SizedBox(height: 10),
                TextField(
                    controller: subjectCtrl,
                    decoration:
                        const InputDecoration(labelText: 'المادة التعليمية')),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white),
              onPressed: () async {
                if (nameCtrl.text.trim().isNotEmpty &&
                    subjectCtrl.text.trim().isNotEmpty) {
                  setState(() {
                    if (teacher == null) {
                      widget.institution.teachers.add(Teacher(
                          name: nameCtrl.text.trim(),
                          subject: subjectCtrl.text.trim(),
                          imagePath: tempImagePath));
                    } else {
                      teacher.name = nameCtrl.text.trim();
                      teacher.subject = subjectCtrl.text.trim();
                      teacher.imagePath = tempImagePath;
                    }
                  });
                  await SchoolData.saveData();
                  if (mounted) Navigator.pop(context);
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteTeacher(Teacher teacher) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الأستاذ'),
        content: Text('هل أنت متأكد من حذف الأستاذ "${teacher.name}"؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              setState(() {
                widget.institution.teachers.remove(teacher);
              });
              await SchoolData.saveData();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.institution.name)),
      body: widget.institution.teachers.isEmpty
          ? const Center(child: Text('لا يوجد أساتذة مسجلون في هذه المؤسسة.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.institution.teachers.length,
              itemBuilder: (context, index) {
                final teacher = widget.institution.teachers[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF059669),
                      backgroundImage: teacher.imagePath != null
                          ? FileImage(File(teacher.imagePath!))
                          : null,
                      child: teacher.imagePath == null
                          ? const Icon(Icons.person, color: Colors.white)
                          : null,
                    ),
                    title: Text(teacher.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 17)),
                    subtitle: Text(
                        'المادة: ${teacher.subject} | عدد الأفواج: ${teacher.classes.length}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            icon:
                                const Icon(Icons.edit, color: Colors.blueGrey),
                            onPressed: () =>
                                _showTeacherDialog(teacher: teacher)),
                        IconButton(
                            icon: const Icon(Icons.delete,
                                color: Colors.redAccent),
                            onPressed: () => _deleteTeacher(teacher)),
                        const Icon(Icons.arrow_forward_ios, size: 16),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => ClassesScreen(
                                  institution: widget.institution,
                                  teacher: teacher))).then(
                          (_) => setState(() {}));
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF059669),
        foregroundColor: Colors.white,
        onPressed: () => _showTeacherDialog(),
        icon: const Icon(Icons.person_add),
        label: const Text('إضافة أستاذ'),
      ),
    );
  }
}

// ============================================================================
// 7. شاشة الأقسام والجدول الأسبوعي ورقمنة (CLASSES SCREEN)
// ============================================================================

class ClassesScreen extends StatefulWidget {
  final Institution institution;
  final Teacher teacher;
  const ClassesScreen(
      {super.key, required this.institution, required this.teacher});

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  void _showClassDialog({SchoolClass? schoolClass}) {
    final classCtrl = TextEditingController(text: schoolClass?.name ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            schoolClass == null ? 'إضافة فوج تربوي جديد' : 'تعديل اسم الفوج'),
        content: TextField(
            controller: classCtrl,
            decoration: const InputDecoration(
                hintText: 'مثال: 3 ثانوي علوم تجريبية 1')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white),
            onPressed: () async {
              if (classCtrl.text.trim().isNotEmpty) {
                setState(() {
                  if (schoolClass == null) {
                    widget.teacher.classes.add(SchoolClass(
                        name: classCtrl.text.trim(), students: []));
                  } else {
                    schoolClass.name = classCtrl.text.trim();
                  }
                });
                await SchoolData.saveData();
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _deleteClass(SchoolClass schoolClass) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الفوج'),
        content: Text('هل أنت متأكد من حذف فوج "${schoolClass.name}"؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              setState(() {
                widget.teacher.classes.remove(schoolClass);
              });
              await SchoolData.saveData();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  void _showTimetableDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('جدول الحصص والتوقيت الأسبوعي'),
          content: SizedBox(
            width: double.maxFinite,
            height: 350,
            child: Column(
              children: [
                Expanded(
                  child: widget.teacher.timetable.isEmpty
                      ? const Center(
                          child: Text('لا توجد حصص مضافة بعد في الجدول.'))
                      : ListView.builder(
                          itemCount: widget.teacher.timetable.length,
                          itemBuilder: (context, index) {
                            final item = widget.teacher.timetable[index];
                            return Card(
                              child: ListTile(
                                title: Text('${item.day} | ${item.timeSlot}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                    'القسم: ${item.className} | القاعة: ${item.room}'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.redAccent),
                                  onPressed: () async {
                                    setState(() {
                                      widget.teacher.timetable.removeAt(index);
                                    });
                                    setDialogState(() {});
                                    await SchoolData.saveData();
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة حصة دراسية جديدة'),
                  onPressed: () {
                    _showAddTimetableItemDialog(onAdded: () {
                      setDialogState(() {});
                      setState(() {});
                    });
                  },
                )
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق')),
          ],
        ),
      ),
    );
  }

  void _showAddTimetableItemDialog({required VoidCallback onAdded}) {
    final dayCtrl = TextEditingController(text: 'الأحد');
    final timeCtrl = TextEditingController(text: '08:00 - 10:00');
    final classCtrl = TextEditingController();
    final roomCtrl = TextEditingController(text: 'قاعة 01');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة حصة دراسية'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: dayCtrl,
                  decoration:
                      const InputDecoration(labelText: 'اليوم (مثال: الأحد)')),
              TextField(
                  controller: timeCtrl,
                  decoration: const InputDecoration(
                      labelText: 'التوقيت (مثال: 08:00 - 10:00)')),
              TextField(
                  controller: classCtrl,
                  decoration: const InputDecoration(labelText: 'اسم القسم')),
              TextField(
                  controller: roomCtrl,
                  decoration: const InputDecoration(labelText: 'رقم القاعة')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (classCtrl.text.isNotEmpty) {
                setState(() {
                  widget.teacher.timetable.add(TimetableItem(
                    day: dayCtrl.text.trim(),
                    timeSlot: timeCtrl.text.trim(),
                    className: classCtrl.text.trim(),
                    room: roomCtrl.text.trim(),
                  ));
                });
                await SchoolData.saveData();
                if (mounted) Navigator.pop(context);
                onAdded();
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  void _showBackupRestoreDialog() {
    final backupCtrl =
        TextEditingController(text: SchoolData.exportBackupJson());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('النسخ الاحتياطي والاستعادة'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    'انسخ هذا النص المشفر كنسخة احتياطية، أو الصق نسخة سابقة للاسترجاع الفوري:',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 10),
                TextField(
                    controller: backupCtrl,
                    maxLines: 6,
                    decoration: InputDecoration(
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)))),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق')),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('نسخ'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: backupCtrl.text));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم نسخ البيانات بنجاح!')));
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white),
            onPressed: () async {
              bool success =
                  await SchoolData.importBackupJson(backupCtrl.text);
              if (success) {
                setState(() {});
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('تمت استعادة البيانات بنجاح!')));
                }
              }
            },
            child: const Text('استعادة'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportRaqmanaExcel() async {
    try {
      var excel = excelPkg.Excel.createExcel();
      excelPkg.Sheet sheet = excel['كشف رقمنة'];

      sheet.appendRow([
        excelPkg.TextCellValue('المؤسسة التربوية: ${widget.institution.name}'),
        excelPkg.TextCellValue('الأستاذ: ${widget.teacher.name}'),
        excelPkg.TextCellValue('المادة: ${widget.teacher.subject}'),
        excelPkg.TextCellValue('تاريخ التصدير: ${todayStr()}'),
      ]);
      sheet.appendRow([]);

      for (var c in widget.teacher.classes) {
        sheet.appendRow([excelPkg.TextCellValue('القسم: ${c.name}')]);
        sheet.appendRow([
          excelPkg.TextCellValue('الرقم'),
          excelPkg.TextCellValue('رقم التعريف المدرسي'),
          excelPkg.TextCellValue('اللقب'),
          excelPkg.TextCellValue('الاسم'),
          excelPkg.TextCellValue('التقويم المستمر'),
          excelPkg.TextCellValue('الفرض 1'),
          excelPkg.TextCellValue('الفرض 2'),
          excelPkg.TextCellValue('الاختبار'),
          excelPkg.TextCellValue('المعدل الفصلي'),
          excelPkg.TextCellValue('التقدير'),
        ]);

        for (int i = 0; i < c.students.length; i++) {
          var s = c.students[i];
          sheet.appendRow([
            excelPkg.TextCellValue('${i + 1}'),
            excelPkg.TextCellValue(s.regNumber),
            excelPkg.TextCellValue(s.lastName),
            excelPkg.TextCellValue(s.firstName),
            excelPkg.TextCellValue('${s.continuousEval}'),
            excelPkg.TextCellValue('${s.exam1}'),
            excelPkg.TextCellValue(s.exam2 > 0 ? '${s.exam2}' : '-'),
            excelPkg.TextCellValue('${s.test}'),
            excelPkg.TextCellValue(s.average.toStringAsFixed(2)),
            excelPkg.TextCellValue(s.appreciation),
          ]);
        }
        sheet.appendRow([]);
      }

      Directory? dir = await getApplicationDocumentsDirectory();
      String path =
          '${dir.path}/Raqmana_Export_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = File(path);
      file.createSync(recursive: true);
      file.writeAsBytesSync(excel.encode()!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('تم تصدير ملف رقمنة بنجاح في:\n$path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ أثناء التصدير: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    int totalStudents =
        widget.teacher.classes.fold(0, (sum, c) => sum + c.students.length);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.teacher.name} (${widget.teacher.subject})'),
        actions: [
          IconButton(
              icon: const Icon(Icons.calendar_month),
              tooltip: 'جدول الحصص الأسبوعي',
              onPressed: _showTimetableDialog),
          IconButton(
              icon: const Icon(Icons.table_chart, color: Color(0xFFF59E0B)),
              tooltip: 'تصدير جدول رقمنة',
              onPressed: _exportRaqmanaExcel),
          IconButton(
              icon: const Icon(Icons.settings_backup_restore),
              tooltip: 'النسخ الاحتياطي',
              onPressed: _showBackupRestoreDialog),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(children: [
                  const Text('إجمالي الأفواج',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('${widget.teacher.classes.length}',
                      style: const TextStyle(
                          color: Color(0xFFF59E0B),
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                ]),
                Container(height: 36, width: 1, color: Colors.white24),
                Column(children: [
                  const Text('إجمالي التلاميذ',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('$totalStudents',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                ]),
              ],
            ),
          ),
          Expanded(
            child: widget.teacher.classes.isEmpty
                ? const Center(child: Text('لا توجد أقسام مسجلة بعد.'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: widget.teacher.classes.length,
                    itemBuilder: (context, index) {
                      final schoolClass = widget.teacher.classes[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          leading: const CircleAvatar(
                              backgroundColor: Color(0xFF0F172A),
                              child: Icon(Icons.school,
                                  color: Color(0xFFF59E0B))),
                          title: Text(schoolClass.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 17)),
                          subtitle: Text(
                              'عدد التلاميذ: ${schoolClass.students.length}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                  icon: const Icon(Icons.edit,
                                      color: Colors.blueGrey),
                                  onPressed: () => _showClassDialog(
                                      schoolClass: schoolClass)),
                              IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.redAccent),
                                  onPressed: () =>
                                      _deleteClass(schoolClass)),
                              const Icon(Icons.arrow_forward_ios, size: 16),
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => ClassDashboardScreen(
                                        institution: widget.institution,
                                        teacher: widget.teacher,
                                        schoolClass: schoolClass,
                                        isDarkMode: (Theme.of(context).brightness == Brightness.dark)))).then(
                                (_) => setState(() {}));
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: const Color(0xFFF59E0B),
        onPressed: () => _showClassDialog(),
        icon: const Icon(Icons.add),
        label: const Text('إضافة قسم'),
      ),
    );
  }
}

// ============================================================================
// 8. لوحة تحكم القسم، التقييم، والحضور الشامل (CLASS DASHBOARD ENGINE)
// ============================================================================

class ClassDashboardScreen extends StatefulWidget {
  final Institution institution;
  final Teacher teacher;
  final SchoolClass schoolClass;
  final bool isDarkMode;

  const ClassDashboardScreen({
    super.key,
    required this.institution,
    required this.teacher,
    required this.schoolClass,
    this.isDarkMode = false,
  });

  @override
  State<ClassDashboardScreen> createState() => _ClassDashboardScreenState();
}

class _ClassDashboardScreenState extends State<ClassDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _studentSearchQuery = '';
  String _sortCriteria = 'alphabetical'; // alphabetical, gradeDesc, gradeAsc, regNumber

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  // ✅ 1. نافذة تعديل معلومات التلميذ الشاملة (طلب المستخدم)
  void _showEditStudentInfoDialog(Student student) {
    final firstCtrl = TextEditingController(text: student.firstName);
    final lastCtrl = TextEditingController(text: student.lastName);
    final regCtrl = TextEditingController(text: student.regNumber);
    final birthDateCtrl = TextEditingController(text: student.birthDate);
    final birthPlaceCtrl = TextEditingController(text: student.birthPlace);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: const [
            Icon(Icons.person_pin_rounded, color: Color(0xFF059669), size: 28),
            SizedBox(width: 8),
            Text('تعديل معلومات التلميذ',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: lastCtrl,
                decoration: const InputDecoration(labelText: 'اللقب', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: firstCtrl,
                decoration: const InputDecoration(labelText: 'الاسم', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: regCtrl,
                decoration: const InputDecoration(labelText: 'رقم التعريف المدرسي', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: birthDateCtrl,
                decoration: const InputDecoration(labelText: 'تاريخ الازدياد (DD/MM/YYYY)', prefixIcon: Icon(Icons.cake), border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: birthPlaceCtrl,
                decoration: const InputDecoration(labelText: 'مكان الازدياد', prefixIcon: Icon(Icons.location_on), border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.save_rounded),
            label: const Text('حفظ التعديلات'),
            onPressed: () async {
              if (firstCtrl.text.trim().isNotEmpty && lastCtrl.text.trim().isNotEmpty) {
                setState(() {
                  student.firstName = firstCtrl.text.trim();
                  student.lastName = lastCtrl.text.trim();
                  student.regNumber = regCtrl.text.trim();
                  student.birthDate = birthDateCtrl.text.trim();
                  student.birthPlace = birthPlaceCtrl.text.trim();
                });
                await SchoolData.saveData();
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تم تحديث بيانات التلميذ: ${student.lastName} ${student.firstName} بنجاح ✅')),
                  );
                }
                // ✅ تسجيل السجلات
                _addClassLog('تعديل معلومات تلميذ', 'تم تعديل بيانات الطالب: ${student.lastName} ${student.firstName}');
                _addStudentLog(student, 'تعديل بيانات شخصية', 'تم تحديث الاسم، اللقب، رقم التعريف، تاريخ ومكان الميلاد');
              }
            },
          ),
        ],
      ),
    );
  }

  // ✅ 2. النافذة المنبثقة التتابعية لتسجيل الحضور (طالب بطالب مع التوقيت)
  void _showSequentialAttendanceDialog() {
    final list = widget.schoolClass.students;
    if (list.isEmpty) return;

    int activeIndex = 0;
    String liveTime = currentTimeStr();
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final student = list[activeIndex];

          void applyStatusAndGoNext(String status) {
            String? timeToSave;
            if (status != 'حاضر' && status != 'معفى') {
              timeToSave = liveTime.trim().isEmpty ? currentTimeStr() : liveTime.trim();
            }
            _applyAttendanceStatus(
              student,
              status,
              timeToSave,
              reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
            );

            if (activeIndex < list.length - 1) {
              setModalState(() {
                activeIndex++;
                liveTime = currentTimeStr();
                reasonCtrl.clear();
              });
            } else {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('🎉 اكتمل تسجيل حضور وغياب كافة تلاميذ القسم بنجاح!')),
              );
            }
          }

          final isDark = Theme.of(context).brightness == Brightness.dark;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('التسجيل التتابعي (طالب بطالب)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                    Text('تلميذ ${activeIndex + 1} من ${list.length} • ${widget.schoolClass.name}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // شريط التقدم
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: (activeIndex + 1) / list.length,
                        minHeight: 7,
                        backgroundColor: Colors.grey.shade300,
                        color: const Color(0xFF059669),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // بطاقة التلميذ الكبيرة بوضوح تام
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade400.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: const Color(0xFF059669),
                            child: Text(
                              '${activeIndex + 1}',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${student.lastName} ${student.firstName}',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                Text('رقم التعريف: ${student.regNumber} | المعدل: ${student.average.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // توقيت الحالة والملاحظة
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: liveTime,
                            decoration: const InputDecoration(
                              labelText: 'توقيت الحالة (للتأخر والهروب)',
                              prefixIcon: Icon(Icons.access_time),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) => liveTime = v,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: reasonCtrl,
                            decoration: const InputDecoration(
                              labelText: 'السبب أو الملاحظة (اختياري)',
                              prefixIcon: Icon(Icons.notes),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Text('اختر الحالة ليتم حفظها والانتقال التلقائي للتلميذ الموالي:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    const SizedBox(height: 10),

                    // أزرار الحالات الخمسة الكبيرة
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          icon: const Icon(Icons.check_circle),
                          label: const Text('حاضر 🟢'),
                          onPressed: () => applyStatusAndGoNext('حاضر'),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE11D48),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          icon: const Icon(Icons.cancel),
                          label: const Text('غائب 🔴'),
                          onPressed: () => applyStatusAndGoNext('غائب'),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD97706),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          icon: const Icon(Icons.watch_later_outlined),
                          label: const Text('متأخر 🟡'),
                          onPressed: () => applyStatusAndGoNext('متأخر'),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFB91C1C),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          icon: const Icon(Icons.directions_run),
                          label: const Text('هروب 🚨'),
                          onPressed: () => applyStatusAndGoNext('هروب'),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          icon: const Icon(Icons.assignment_outlined),
                          label: const Text('خروج بإذن 📜'),
                          onPressed: () => applyStatusAndGoNext('خروج بإذن'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (activeIndex > 0)
                TextButton(
                  onPressed: () => setModalState(() => activeIndex--),
                  child: const Text('التلميذ السابق'),
                ),
              TextButton(
                onPressed: () {
                  if (activeIndex < list.length - 1) {
                    setModalState(() => activeIndex++);
                  } else {
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('تخطي دون تسجيل'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddStudentDialog() {
    final firstCtrl = TextEditingController();
    final lastCtrl = TextEditingController();
    final regCtrl = TextEditingController();
    final birthDateCtrl = TextEditingController(text: '01/01/2007');
    final birthPlaceCtrl = TextEditingController(text: 'الجلفة');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة تلميذ جديد'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: lastCtrl, decoration: const InputDecoration(labelText: 'اللقب')),
              TextField(controller: firstCtrl, decoration: const InputDecoration(labelText: 'الاسم')),
              TextField(controller: regCtrl, decoration: const InputDecoration(labelText: 'رقم التعريف المدرسي')),
              TextField(controller: birthDateCtrl, decoration: const InputDecoration(labelText: 'تاريخ الازدياد')),
              TextField(controller: birthPlaceCtrl, decoration: const InputDecoration(labelText: 'مكان الازدياد')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (firstCtrl.text.trim().isNotEmpty && lastCtrl.text.trim().isNotEmpty) {
                setState(() {
                  widget.schoolClass.students.add(Student(
                    firstName: firstCtrl.text.trim(),
                    lastName: lastCtrl.text.trim(),
                    regNumber: regCtrl.text.trim().isEmpty
                        ? '2026${widget.schoolClass.students.length + 1}'
                        : regCtrl.text.trim(),
                    birthDate: birthDateCtrl.text.trim(),
                    birthPlace: birthPlaceCtrl.text.trim(),
                  ));
                });
                await SchoolData.saveData();
                if (mounted) Navigator.pop(context);
                // ✅ تسجيل السجلات
                _addClassLog('إضافة تلميذ جديد',
                    'تمت إضافة التلميذ ${lastCtrl.text.trim()} ${firstCtrl.text.trim()} (${regCtrl.text.trim()})');
                _addStudentLog(widget.schoolClass.students.last, 'إنشاء ملف تلميذ',
                    'تم إنشاء سجل تلميذ جديد في القسم ${widget.schoolClass.name}');
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  // ✅ إضافة سجل يومي للقسم (تاريخ، وقت، إجراء، تفاصيل، من قام به)
  void _addClassLog(String action, String details) {
    setState(() {
      widget.schoolClass.dailyLogs.add(ClassDailyLogEntry(
        date: todayStr(),
        time: currentTimeStr(),
        action: action,
        details: details,
        performedBy: widget.teacher.name,
      ));
    });
    SchoolData.saveData();
  }

  // ✅ إضافة سجل فردي لتلميذ (تاريخ، وقت، إجراء، تفاصيل، من قام به)
  void _addStudentLog(Student student, String action, String details) {
    setState(() {
      student.personalLogs.add(StudentPersonalLogEntry(
        date: todayStr(),
        time: currentTimeStr(),
        action: action,
        details: details,
        performedBy: widget.teacher.name,
      ));
    });
    SchoolData.saveData();
  }

  // تصدير سجل القسم المجمع بالكامل
  Future<void> _exportFullClassRegisterPdf() async {
    try {
      final pdf = pwWidgets.Document();
      final arabicFont = await PdfGoogleFonts.cairoRegular();
      final arabicBold = await PdfGoogleFonts.cairoBold();

      List<Student> sorted = List.from(widget.schoolClass.students)
        ..sort((a, b) => b.average.compareTo(a.average));

      pdf.addPage(
        pwWidgets.MultiPage(
          pageFormat: pw.PdfPageFormat.a4,
          textDirection: pwWidgets.TextDirection.rtl,
          theme: pwWidgets.ThemeData.withFont(base: arabicFont, bold: arabicBold),
          build: (pwWidgets.Context context) {
            return [
              pwWidgets.Center(
                child: pwWidgets.Text('الجمهورية الجزائرية الديمقراطية الشعبية',
                    style: pwWidgets.TextStyle(fontSize: 14, fontWeight: pwWidgets.FontWeight.bold)),
              ),
              pwWidgets.Center(
                child: pwWidgets.Text('وزارة التربية الوطنية - سجل نتائج ومواظبة القسم الشامل',
                    style: const pwWidgets.TextStyle(fontSize: 12)),
              ),
              pwWidgets.Divider(thickness: 1.5),
              pwWidgets.SizedBox(height: 6),
              pwWidgets.Row(
                mainAxisAlignment: pwWidgets.MainAxisAlignment.spaceBetween,
                children: [
                  pwWidgets.Text('المؤسسة: ${widget.institution.name}'),
                  pwWidgets.Text('القسم: ${widget.schoolClass.name}'),
                  pwWidgets.Text('الأستاذ: ${widget.teacher.name} (${widget.teacher.subject})'),
                  pwWidgets.Text('تاريخ الإنجاز: ${todayStr()}'),
                ],
              ),
              pwWidgets.SizedBox(height: 12),
              pwWidgets.Table(
                border: pwWidgets.TableBorder.all(color: pw.PdfColors.black, width: 0.8),
                children: [
                  pwWidgets.TableRow(
                    decoration: const pwWidgets.BoxDecoration(color: pw.PdfColors.grey300),
                    children: [
                      pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(5), child: pwWidgets.Center(child: pwWidgets.Text('الرتبة'))),
                      pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(5), child: pwWidgets.Center(child: pwWidgets.Text('رقم التعريف'))),
                      pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(5), child: pwWidgets.Center(child: pwWidgets.Text('اللقب والاسم'))),
                      pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(5), child: pwWidgets.Center(child: pwWidgets.Text('حالة المواظبة'))),
                      pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(5), child: pwWidgets.Center(child: pwWidgets.Text('التقويم'))),
                      pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(5), child: pwWidgets.Center(child: pwWidgets.Text('ف 1'))),
                      pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(5), child: pwWidgets.Center(child: pwWidgets.Text('ف 2'))),
                      pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(5), child: pwWidgets.Center(child: pwWidgets.Text('الاختبار'))),
                      pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(5), child: pwWidgets.Center(child: pwWidgets.Text('المعدل'))),
                      pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(5), child: pwWidgets.Center(child: pwWidgets.Text('التقدير'))),
                      pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(5), child: pwWidgets.Center(child: pwWidgets.Text('قرار المجلس'))),
                    ],
                  ),
                  ...sorted.asMap().entries.map((entry) {
                    int rank = entry.key + 1;
                    Student s = entry.value;
                    String statusTxt = s.status;
                    if (s.statusTime != null && s.statusTime!.isNotEmpty) {
                      statusTxt += ' (${s.statusTime})';
                    }
                    return pwWidgets.TableRow(
                      children: [
                        pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(4), child: pwWidgets.Center(child: pwWidgets.Text('$rank'))),
                        pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(4), child: pwWidgets.Center(child: pwWidgets.Text(s.regNumber))),
                        pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(4), child: pwWidgets.Text('${s.lastName} ${s.firstName}', style: pwWidgets.TextStyle(fontWeight: pwWidgets.FontWeight.bold))),
                        pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(4), child: pwWidgets.Center(child: pwWidgets.Text(statusTxt, style: const pwWidgets.TextStyle(fontSize: 8)))),
                        pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(4), child: pwWidgets.Center(child: pwWidgets.Text('${s.continuousEval}'))),
                        pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(4), child: pwWidgets.Center(child: pwWidgets.Text('${s.exam1}'))),
                        pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(4), child: pwWidgets.Center(child: pwWidgets.Text(s.exam2 > 0 ? '${s.exam2}' : '-'))),
                        pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(4), child: pwWidgets.Center(child: pwWidgets.Text('${s.test}'))),
                        pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(4), child: pwWidgets.Center(child: pwWidgets.Text(s.average.toStringAsFixed(2), style: pwWidgets.TextStyle(fontWeight: pwWidgets.FontWeight.bold)))),
                        pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(4), child: pwWidgets.Center(child: pwWidgets.Text(s.appreciation))),
                        pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(4), child: pwWidgets.Center(child: pwWidgets.Text(s.councilDecision, style: const pwWidgets.TextStyle(fontSize: 8)))),
                      ],
                    );
                  }),
                ],
              ),
              pwWidgets.SizedBox(height: 18),
              pwWidgets.Row(
                mainAxisAlignment: pwWidgets.MainAxisAlignment.spaceBetween,
                children: [
                  pwWidgets.BarcodeWidget(
                    barcode: pwWidgets.Barcode.qrCode(),
                    data: 'سجل قسم: ${widget.schoolClass.name}\nالمؤسسة: ${widget.institution.name}\nالأستاذ: ${widget.teacher.name}\nعدد التلاميذ: ${widget.schoolClass.students.length}\nتاريخ: ${todayStr()}',
                    width: 65,
                    height: 65,
                  ),
                  pwWidgets.Container(
                    width: 75,
                    height: 75,
                    decoration: pwWidgets.BoxDecoration(
                      shape: pwWidgets.BoxShape.circle,
                      border: pwWidgets.Border.all(color: pw.PdfColors.blue900, width: 2),
                    ),
                    child: pwWidgets.Center(
                      child: pwWidgets.Text('الختم الرسمي\nللمؤسسة\n★ 2026 ★',
                          textAlign: pwWidgets.TextAlign.center,
                          style: const pwWidgets.TextStyle(fontSize: 8)),
                    ),
                  ),
                  pwWidgets.Text('توقيع الأستاذ(ة): ${widget.teacher.name}'),
                ],
              ),
            ];
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (pw.PdfPageFormat format) async => pdf.save(),
        name: 'سجل_قسم_${widget.schoolClass.name}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ أثناء إنشاء سجل القسم PDF: $e')));
      }
    }
  }

  // كشف نقاط فردي رسمي
  Future<void> _exportStudentBulletinPdf(Student student, int rank) async {
    try {
      final pdf = pwWidgets.Document();
      final arabicFont = await PdfGoogleFonts.cairoRegular();
      final arabicBold = await PdfGoogleFonts.cairoBold();

      final verificationData =
          "المؤسسة: ${widget.institution.name}\nالتلميذ: ${student.lastName} ${student.firstName}\nالمعدل: ${student.average.toStringAsFixed(2)}\nالرتبة: $rank";

      pdf.addPage(
        pwWidgets.Page(
          pageFormat: pw.PdfPageFormat.a4,
          textDirection: pwWidgets.TextDirection.rtl,
          theme: pwWidgets.ThemeData.withFont(base: arabicFont, bold: arabicBold),
          build: (pwWidgets.Context context) {
            return pwWidgets.Container(
              padding: const pwWidgets.EdgeInsets.all(24),
              decoration: pwWidgets.BoxDecoration(
                  border: pwWidgets.Border.all(color: pw.PdfColors.black, width: 2)),
              child: pwWidgets.Column(
                crossAxisAlignment: pwWidgets.CrossAxisAlignment.stretch,
                children: [
                  pwWidgets.Center(
                    child: pwWidgets.Text('الجمهورية الجزائرية الديمقراطية الشعبية',
                        style: pwWidgets.TextStyle(fontSize: 14, fontWeight: pwWidgets.FontWeight.bold)),
                  ),
                  pwWidgets.Center(
                    child: pwWidgets.Text('وزارة التربية الوطنية - السجل البيداغوجي الشامل',
                        style: const pwWidgets.TextStyle(fontSize: 12)),
                  ),
                  pwWidgets.Divider(thickness: 1.5),
                  pwWidgets.SizedBox(height: 8),
                  pwWidgets.Row(
                    mainAxisAlignment: pwWidgets.MainAxisAlignment.spaceBetween,
                    children: [
                      pwWidgets.Text('المؤسسة: ${widget.institution.name}'),
                      pwWidgets.Text('تاريخ الكشف: ${todayStr()}'),
                    ],
                  ),
                  pwWidgets.SizedBox(height: 14),
                  pwWidgets.Container(
                    padding: const pwWidgets.EdgeInsets.all(10),
                    decoration: pwWidgets.BoxDecoration(
                        border: pwWidgets.Border.all(color: pw.PdfColors.grey400)),
                    child: pwWidgets.Row(
                      mainAxisAlignment: pwWidgets.MainAxisAlignment.spaceBetween,
                      children: [
                        pwWidgets.Text('التلميذ: ${student.lastName} ${student.firstName}',
                            style: pwWidgets.TextStyle(fontWeight: pwWidgets.FontWeight.bold, fontSize: 13)),
                        pwWidgets.Text('رقم التعريف: ${student.regNumber}'),
                        pwWidgets.Text('القسم: ${widget.schoolClass.name}'),
                      ],
                    ),
                  ),
                  pwWidgets.SizedBox(height: 16),
                  pwWidgets.Table(
                    border: pwWidgets.TableBorder.all(color: pw.PdfColors.black, width: 1),
                    children: [
                      pwWidgets.TableRow(
                        decoration: const pwWidgets.BoxDecoration(color: pw.PdfColors.grey300),
                        children: [
                          pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(6), child: pwWidgets.Center(child: pwWidgets.Text('المادة'))),
                          pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(6), child: pwWidgets.Center(child: pwWidgets.Text('التقويم'))),
                          pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(6), child: pwWidgets.Center(child: pwWidgets.Text('الفرض 1'))),
                          pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(6), child: pwWidgets.Center(child: pwWidgets.Text('الفرض 2'))),
                          pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(6), child: pwWidgets.Center(child: pwWidgets.Text('الاختبار (×2)'))),
                          pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(6), child: pwWidgets.Center(child: pwWidgets.Text('المعدل'))),
                          pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(6), child: pwWidgets.Center(child: pwWidgets.Text('الرتبة'))),
                        ],
                      ),
                      pwWidgets.TableRow(
                        children: [
                          pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(8), child: pwWidgets.Center(child: pwWidgets.Text(widget.teacher.subject))),
                          pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(8), child: pwWidgets.Center(child: pwWidgets.Text('${student.continuousEval}'))),
                          pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(8), child: pwWidgets.Center(child: pwWidgets.Text('${student.exam1}'))),
                          pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(8), child: pwWidgets.Center(child: pwWidgets.Text(student.exam2 > 0 ? '${student.exam2}' : '-'))),
                          pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(8), child: pwWidgets.Center(child: pwWidgets.Text('${student.test}'))),
                          pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(8), child: pwWidgets.Center(child: pwWidgets.Text(student.average.toStringAsFixed(2), style: pwWidgets.TextStyle(fontWeight: pwWidgets.FontWeight.bold)))),
                          pwWidgets.Padding(padding: const pwWidgets.EdgeInsets.all(8), child: pwWidgets.Center(child: pwWidgets.Text('$rank / ${widget.schoolClass.students.length}'))),
                        ],
                      ),
                    ],
                  ),
                  pwWidgets.SizedBox(height: 16),
                  pwWidgets.Text('التقدير البيداغوجي: ${student.appreciation}  |  قرار مجلس الأقسام: ${student.councilDecision}',
                      style: pwWidgets.TextStyle(fontWeight: pwWidgets.FontWeight.bold)),
                  pwWidgets.Spacer(),
                  pwWidgets.Row(
                    mainAxisAlignment: pwWidgets.MainAxisAlignment.spaceBetween,
                    children: [
                      pwWidgets.BarcodeWidget(
                        barcode: pwWidgets.Barcode.qrCode(),
                        data: verificationData,
                        width: 75,
                        height: 75,
                      ),
                      pwWidgets.Container(
                        width: 85,
                        height: 85,
                        decoration: pwWidgets.BoxDecoration(
                          shape: pwWidgets.BoxShape.circle,
                          border: pwWidgets.Border.all(color: pw.PdfColors.blue900, width: 2),
                        ),
                        child: pwWidgets.Center(
                          child: pwWidgets.Text('المطابقة الرسمية\nختم الإدارة\n★ 2026 ★',
                              textAlign: pwWidgets.TextAlign.center, style: const pwWidgets.TextStyle(fontSize: 8)),
                        ),
                      ),
                      pwWidgets.Text('توقيع الأستاذ(ة): ${widget.teacher.name}'),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (pw.PdfPageFormat format) async => pdf.save(),
        name: 'كشف_نقاط_${student.lastName}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ أثناء إنشاء PDF: $e')));
      }
    }
  }

  void _sendGuardianNotification(Student student) {
    String attendanceNotice = '';
    if (student.status == 'هروب') {
      attendanceNotice = '⚠️ تنبيه عاجل: تم تسجيل حالة (هروب من الحصة) في توقيت: (${student.statusTime ?? currentTimeStr()})، يرجى الاتصال بالإدارة فوراً لتبرير الوضعية.';
    } else if (student.status == 'خروج بإذن') {
      attendanceNotice = '📋 إشعار: غادر التلميذ الحصة بترخيص رسمي في توقيت: (${student.statusTime ?? currentTimeStr()}) بسبب: (${student.statusReason ?? "إذن إداري"}).';
    } else if (student.status == 'متأخر') {
      attendanceNotice = '⏰ إشعار: سجل التلميذ دخولاً متأخراً على الساعة: (${student.statusTime ?? currentTimeStr()}).';
    } else if (student.status == 'غائب') {
      attendanceNotice = '🔴 إشعار: التلميذ غائب عن الحصة اليوم بتاريخ: ${todayStr()}.';
    } else {
      attendanceNotice = '🟢 التلميذ حاضر وبحالة نظامية في الحصة.';
    }

    String msg = '''
السلام عليكم، إلى ولي أمر التلميذ(ة): ${student.lastName} ${student.firstName} (القسم: ${widget.schoolClass.name})
المؤسسة: ${widget.institution.name} | المادة: ${widget.teacher.subject}
التاريخ: ${todayStr()}

$attendanceNotice

معدل المادة الفصلي: ${student.average.toStringAsFixed(2)} / 20 (${student.appreciation}).
مع تحيات الأستاذ(ة): ${widget.teacher.name}.
''';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              student.status == 'هروب' ? Icons.warning_amber_rounded : Icons.mark_chat_unread_outlined,
              color: student.status == 'هروب' ? Colors.red : const Color(0xFF059669),
            ),
            const SizedBox(width: 8),
            const Text('إشعار ولي الأمر الفوري'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('النص المنسق للمشاركة الفورية عبر WhatsApp أو SMS:',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
              child: Text(msg, style: const TextStyle(fontSize: 12, color: Colors.black87)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: student.status == 'هروب' ? Colors.red : const Color(0xFF059669),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.copy),
            label: const Text('نسخ الرسالة'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: msg));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ نص الإشعار بنجاح!')));
            },
          ),
        ],
      ),
    );
  }

  void _showEditStudentGradesDialog(Student student) {
    final continuousCtrl = TextEditingController(text: student.continuousEval.toString());
    final exam1Ctrl = TextEditingController(text: student.exam1.toString());
    final exam2Ctrl = TextEditingController(text: student.exam2.toString());
    final testCtrl = TextEditingController(text: student.test.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('علامات التلميذ: ${student.lastName} ${student.firstName}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: continuousCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'التقويم المستمر والمشاركة'),
              ),
              TextField(
                controller: exam1Ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'الفرض 1'),
              ),
              TextField(
                controller: exam2Ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'الفرض 2 (أدخل 0 إن كان غير مبرمج)'),
              ),
              TextField(
                controller: testCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'الاختبار الفصلي'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white),
            onPressed: () async {
              double? c = parseGrade(continuousCtrl.text);
              double? e1 = parseGrade(exam1Ctrl.text);
              double? e2 = parseGrade(exam2Ctrl.text);
              double? t = parseGrade(testCtrl.text);

              if (c != null && e1 != null && e2 != null && t != null) {
                setState(() {
                  student.continuousEval = c;
                  student.exam1 = e1;
                  student.exam2 = e2;
                  student.test = t;
                });
                await SchoolData.saveData();
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث العلامات بنجاح!')));
                }
                // ✅ تسجيل السجلات
                _addClassLog('تعديل علامات تلميذ', 'تم تحديث علامات الطالب: ${student.lastName} ${student.firstName}');
                _addStudentLog(student, 'تعديل العلامات', 'تم تحديث التقويم المستمر والفروض والاختبار');
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _showAttendanceActionDialog(Student student, String targetStatus) {
    if (targetStatus == 'حاضر' || targetStatus == 'غائب' || targetStatus == 'معفى') {
      _applyAttendanceStatus(student, targetStatus, null, null);
      return;
    }

    final timeCtrl = TextEditingController(text: currentTimeStr());
    final reasonCtrl = TextEditingController(
      text: targetStatus == 'خروج بإذن'
          ? 'عيادة طبية'
          : (targetStatus == 'هروب' ? 'مغادرة الحصة دون ترخيص' : 'تأخر في الدخول'),
    );

    String title = '';
    String labelField = 'السبب / الملاحظة';
    if (targetStatus == 'متأخر') {
      title = 'تسجيل دخول متأخر: ${student.lastName} ${student.firstName}';
      labelField = 'سبب التأخر (اختياري)';
    } else if (targetStatus == 'هروب') {
      title = '🚨 تسجيل هروب من الحصة: ${student.lastName} ${student.firstName}';
      labelField = 'ملاحظة الواقعة';
    } else if (targetStatus == 'خروج بإذن') {
      title = '📜 تسجيل خروج بترخيص: ${student.lastName} ${student.firstName}';
      labelField = 'سبب الخروج والوجهة';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: timeCtrl,
              decoration: const InputDecoration(labelText: 'توقيت التسجيل (HH:mm)', prefixIcon: Icon(Icons.access_time)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: InputDecoration(labelText: labelField, prefixIcon: const Icon(Icons.notes)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: targetStatus == 'هروب' ? Colors.red : const Color(0xFF0F172A),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _applyAttendanceStatus(
                student,
                targetStatus,
                timeCtrl.text.trim().isEmpty ? currentTimeStr() : timeCtrl.text.trim(),
                reasonCtrl.text.trim(),
              );
            },
            child: const Text('تأكيد وتسجيل'),
          ),
        ],
      ),
    );
  }

  void _applyAttendanceStatus(Student student, String newStatus, String? time, String? reason) {
    setState(() {
      student.status = newStatus;
      student.statusTime = time;
      student.statusReason = reason;

      String currentToday = todayStr();
      DailyAttendanceRecord? record;
      for (var d in widget.schoolClass.dailyRecords) {
        if (d.date == currentToday) {
          record = d;
          break;
        }
      }

      if (record == null) {
        record = DailyAttendanceRecord(date: currentToday, studentStatuses: {});
        widget.schoolClass.dailyRecords.add(record);
      }
      record.studentStatuses[student.regNumber] = AttendanceDetail(
        status: newStatus,
        time: time,
        reason: reason,
      );
    });
    SchoolData.saveData();
    // ✅ تسجيل السجلات عند تغيير الحضور
    _addClassLog('تسجيل حضور وغياب',
        'تم تسجيل حالة "$newStatus" للتلميذ ${student.lastName} ${student.firstName} في الوقت $time');
    _addStudentLog(student, 'تسجيل حضور',
        'تم تسجيل حالة الحضور: $newStatus في الوقت $time (${reason != null ? reason : "بدون سبب"})');
  }

  void _markAllStudentsPresent() {
    String currentToday = todayStr();
    setState(() {
      DailyAttendanceRecord? record;
      for (var d in widget.schoolClass.dailyRecords) {
        if (d.date == currentToday) {
          record = d;
          break;
        }
      }
      if (record == null) {
        record = DailyAttendanceRecord(date: currentToday, studentStatuses: {});
        widget.schoolClass.dailyRecords.add(record);
      }

      for (var s in widget.schoolClass.students) {
        s.status = 'حاضر';
        s.statusTime = null;
        s.statusReason = null;
        record.studentStatuses[s.regNumber] = AttendanceDetail(status: 'حاضر');
      }
    });
    SchoolData.saveData();
    // ✅ سجل قسم
    _addClassLog('تحضير حضور الكل', 'تم تسجيل جميع تلاميذ القسم ${widget.schoolClass.name} كحاضرين لهذا اليوم');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تسجيل جميع التلاميذ كـ (حاضرين) لهذا اليوم!')),
    );
  }

  // ✅ حذف تلميذ مع تسجيل السجل
  void _deleteStudent(Student student) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف التلميذ'),
        content: Text(
            'هل أنت متأكد من حذف التلميذ "${student.lastName} ${student.firstName}" نهائياً؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              setState(() {
                widget.schoolClass.students.remove(student);
              });
              _addClassLog('حذف تلميذ',
                  'تم حذف التلميذ ${student.lastName} ${student.firstName} (${student.regNumber})');
              await SchoolData.saveData();
              if (mounted) Navigator.pop(ctx);
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('تم حذف التلميذ بنجاح!')));
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  // ✅ 3. الألوان المتناسقة ذات التباين العالي (High Contrast Badges)
  Color _getStatusBgColor(String status, bool isDark) {
    if (isDark) {
      switch (status) {
        case 'حاضر':
          return const Color(0xFF064E3B); // خلفية خضراء ليلية
        case 'غائب':
          return const Color(0xFF881337); // خلفية حمراء ليلية
        case 'متأخر':
          return const Color(0xFF78350F); // خلفية كهرمانية ليلية
        case 'هروب':
          return const Color(0xFF4C1D95); // خلفية بنفسجية ليلية
        case 'خروج بإذن':
          return const Color(0xFF0C4A6E); // خلفية سماوية ليلية
        case 'معفى':
        default:
          return const Color(0xFF334155);
      }
    } else {
      switch (status) {
        case 'حاضر':
          return const Color(0xFFD1FAE5); // فاتح ناصع
        case 'غائب':
          return const Color(0xFFFFE4E6);
        case 'متأخر':
          return const Color(0xFFFEF3C7);
        case 'هروب':
          return const Color(0xFFF3E8FF);
        case 'خروج بإذن':
          return const Color(0xFFE0F2FE);
        case 'معفى':
        default:
          return const Color(0xFFF1F5F9);
      }
    }
  }

  Color _getStatusTextColor(String status, bool isDark) {
    if (isDark) {
      switch (status) {
        case 'حاضر':
          return const Color(0xFF6EE7B7); // نص أخضر ناصع مقروء
        case 'غائب':
          return const Color(0xFFFDA4AF); // نص وردي ساطع
        case 'متأخر':
          return const Color(0xFFFCD34D); // نص أصفر ذهبي واضح
        case 'هروب':
          return const Color(0xFFD8B4FE); // نص بنفسجي ساطع
        case 'خروج بإذن':
          return const Color(0xFF7DD3FC); // نص سماوي ساطع
        case 'معفى':
        default:
          return const Color(0xFFCBD5E1);
      }
    } else {
      switch (status) {
        case 'حاضر':
          return const Color(0xFF065F46); // نص داكن مقروء
        case 'غائب':
          return const Color(0xFF9F1239);
        case 'متأخر':
          return const Color(0xFF92400E);
        case 'هروب':
          return const Color(0xFF5B21B6);
        case 'خروج بإذن':
          return const Color(0xFF075985);
        case 'معفى':
        default:
          return const Color(0xFF334155);
      }
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'حاضر':
        return Icons.check_circle_outline;
      case 'غائب':
        return Icons.cancel_outlined;
      case 'متأخر':
        return Icons.watch_later_outlined;
      case 'هروب':
        return Icons.directions_run;
      case 'خروج بإذن':
        return Icons.assignment_outlined;
      default:
        return Icons.info_outline;
    }
  }

  // ✅ عرض سجل التلميذ الشخصي
  void _showStudentPersonalLogDialog(Student student) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('سجل التلميذ الشخصي: ${student.lastName} ${student.firstName}'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: Column(
            children: [
              Expanded(
                child: student.personalLogs.isEmpty
                    ? const Center(child: Text('لا توجد ملاحظات مسجلة لهذا التلميذ بعد.'))
                    : ListView.builder(
                        itemCount: student.personalLogs.length,
                        itemBuilder: (ctx, i) {
                          final log = student.personalLogs[i];
                          return ListTile(
                            title: Text(log.action),
                            subtitle: Text(
                                '${log.details}\n${log.date} - ${log.time} | بواسطة: ${log.performedBy}'),
                            trailing: Text('${log.time}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
            icon: const Icon(Icons.add),
            label: const Text('إضافة ملاحظة'),
            onPressed: () {
              Navigator.pop(ctx);
              _showAddStudentLogDialog(student);
            },
          ),
        ],
      ),
    );
  }

  // ✅ إضافة ملاحظة لسجل تلميذ فردي
  void _showAddStudentLogDialog(Student student) {
    final actionCtrl = TextEditingController();
    final detailsCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة ملاحظة شخصية للتلميذ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: actionCtrl,
                decoration: const InputDecoration(labelText: 'نوع الملاحظة (مثل: سلوك، استدعاء، تعديل بيانات)')),
            const SizedBox(height: 8),
            TextField(
                controller: detailsCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'تفاصيل الملاحظة')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
            onPressed: () async {
              if (actionCtrl.text.trim().isNotEmpty && detailsCtrl.text.trim().isNotEmpty) {
                _addStudentLog(student, actionCtrl.text.trim(), detailsCtrl.text.trim());
                if (mounted) Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تمت إضافة الملاحظة إلى سجل التلميذ: ${student.lastName} ${student.firstName}')),
                );
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  // ✅ إضافة سجل يومي للقسم يدوياً
  void _showAddClassLogDialog() {
    final actionCtrl = TextEditingController();
    final detailsCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة سجل يومي للقسم'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: actionCtrl,
                decoration: const InputDecoration(labelText: 'نوع السجل (مثل: تعديل علامة، حضور، استيراد)')),
            const SizedBox(height: 8),
            TextField(
                controller: detailsCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'تفاصيل السجل')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white),
            onPressed: () async {
              if (actionCtrl.text.trim().isNotEmpty && detailsCtrl.text.trim().isNotEmpty) {
                _addClassLog(actionCtrl.text.trim(), detailsCtrl.text.trim());
                if (mounted) Navigator.pop(ctx);
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('تمت إضافة السجل اليومي للقسم بنجاح!')));
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _showAddNoteDialog({LessonNote? note}) {
    final dateCtrl = TextEditingController(text: note?.date ?? todayStr());
    final titleCtrl = TextEditingController(text: note?.title ?? '');
    final summaryCtrl = TextEditingController(text: note?.summary ?? '');
    final homeworkCtrl = TextEditingController(text: note?.homework ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(note == null ? 'إضافة مذكرة درس جديد' : 'تعديل مذكرة الدرس'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: dateCtrl, decoration: const InputDecoration(labelText: 'التاريخ')),
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'عنوان الدرس والمحور')),
              TextField(controller: summaryCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'خلاصة الدرس')),
              TextField(controller: homeworkCtrl, decoration: const InputDecoration(labelText: 'الواجب المنزلي')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (titleCtrl.text.trim().isNotEmpty) {
                setState(() {
                  if (note == null) {
                    widget.schoolClass.lessonNotes.add(LessonNote(
                      date: dateCtrl.text.trim(),
                      title: titleCtrl.text.trim(),
                      summary: summaryCtrl.text.trim(),
                      homework: homeworkCtrl.text.trim(),
                    ));
                  } else {
                    note.date = dateCtrl.text.trim();
                    note.title = titleCtrl.text.trim();
                    note.summary = summaryCtrl.text.trim();
                    note.homework = homeworkCtrl.text.trim();
                  }
                });
                await SchoolData.saveData();
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  // ✅ استيراد Excel من ذاكرة الهاتف مع اختيار يدوي للملف
  Future<void> _importStudentsFromExcel() async {
    try {
      List<File> excelFiles = [];
      List<Directory> searchDirs = [];

      try {
        final docDir = await getApplicationDocumentsDirectory();
        searchDirs.add(docDir);
      } catch (_) {}

      for (var path in ['/storage/emulated/0/Download', '/storage/emulated/0/Documents']) {
        try {
          final dir = Directory(path);
          if (dir.existsSync()) {
            searchDirs.add(dir);
          }
        } catch (_) {}
      }

      for (var dir in searchDirs) {
        try {
          final entities = dir.listSync();
          for (var entity in entities) {
            if (entity is File) {
              final pathLower = entity.path.toLowerCase();
              if (pathLower.endsWith('.xlsx') || pathLower.endsWith('.xls')) {
                excelFiles.add(entity);
              }
            }
          }
        } catch (_) {}
      }

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: const [
              Icon(Icons.table_chart, color: Color(0xFF059669)),
              SizedBox(width: 8),
              Text('اختر ملف الإكسل (Excel)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 320,
            child: excelFiles.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.folder_open, size: 54, color: Colors.grey),
                          SizedBox(height: 12),
                          Text(
                            'لم يتم العثور على ملفات .xlsx في مجلد Downloads.\nيرجى وضع ملف القائمة في مجلد التنزيلات بهاتفك أو مجلد المستندات.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: excelFiles.length,
                    itemBuilder: (ctx, i) {
                      final f = excelFiles[i];
                      final fileName = f.path.split('/').last;
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: const Icon(Icons.description, color: Color(0xFF059669)),
                          title: Text(fileName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text(f.path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10, color: Colors.grey)),
                          onTap: () async {
                            Navigator.pop(ctx);
                            Uint8List bytes = await f.readAsBytes();
                            _processExcelBytes(bytes);
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ أثناء قراءة الملفات: $e')));
      }
    }
  }

  // ✅ اختيار ملف Excel يدوياً من أي مكان في ذاكرة الهاتف
  Future<void> _pickExcelFileManually() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        Uint8List bytes = await file.readAsBytes();
        _processExcelBytes(bytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطأ في اختيار الملف يدوياً: $e')));
      }
    }
  }

  void _processExcelBytes(Uint8List bytes) async {
    try {
      var excel = excelPkg.Excel.decodeBytes(bytes);
      int addedCount = 0;

      for (var table in excel.tables.keys) {
        var rows = excel.tables[table]!.rows;
        if (rows.isEmpty) continue;

        int startIndex = 0;
        if (rows.isNotEmpty) {
          String firstCell = extractCellString(rows[0][0]);
          if (firstCell.contains('اللقب') || firstCell.contains('Nom') || firstCell.contains('الرقم')) {
            startIndex = 1;
          }
        }

        for (int i = startIndex; i < rows.length; i++) {
          var row = rows[i];
          if (row.isEmpty) continue;

          String col0 = row.isNotEmpty ? extractCellString(row[0]) : '';
          String col1 = row.length > 1 ? extractCellString(row[1]) : '';
          String col2 = row.length > 2 ? extractCellString(row[2]) : '';
          String col3 = row.length > 3 ? extractCellString(row[3]) : '01/01/2007';

          String lastName = col0;
          String firstName = col1;
          String regNum = col2;

          if (int.tryParse(col0) != null && row.length >= 4) {
            regNum = col1;
            lastName = col2;
            firstName = col3;
          }

          if (lastName.isNotEmpty || firstName.isNotEmpty) {
            widget.schoolClass.students.add(Student(
              lastName: lastName,
              firstName: firstName,
              regNumber: regNum.isEmpty ? '2026${widget.schoolClass.students.length + addedCount + 1}' : regNum,
              birthDate: col3.isEmpty ? '01/01/2007' : col3,
              birthPlace: 'الجلفة',
            ));
            addedCount++;
          }
        }
      }

      await SchoolData.saveData();
      setState(() {});
      // ✅ سجل قسم للاستيراد
      _addClassLog('استيراد تلاميذ من ملف Excel',
          'تم استيراد $addedCount تلميذاً إلى قسم ${widget.schoolClass.name} من ملف رقمنة');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم استيراد $addedCount تلميذاً بنجاح من الهاتف!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ أثناء قراءة ملف الإكسل: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // تطبيق الترتيب المختار
    List<Student> workingList = List.from(widget.schoolClass.students);
    switch (_sortCriteria) {
      case 'alphabetical':
        workingList.sort((a, b) => compareArabicNames(a.lastName, b.lastName));
        break;
      case 'gradeDesc':
        workingList.sort((a, b) => b.average.compareTo(a.average));
        break;
      case 'gradeAsc':
        workingList.sort((a, b) => a.average.compareTo(b.average));
        break;
      case 'regNumber':
        workingList.sort((a, b) => a.regNumber.compareTo(b.regNumber));
        break;
    }

    final filteredStudents = workingList.where((s) {
      if (_studentSearchQuery.isEmpty) return true;
      final q = _studentSearchQuery.toLowerCase();
      return s.lastName.toLowerCase().contains(q) ||
          s.firstName.toLowerCase().contains(q) ||
          s.regNumber.contains(q);
    }).toList();

    int countWeak = widget.schoolClass.students.where((s) => s.average < 10.0).length;
    int countAverage = widget.schoolClass.students.where((s) => s.average >= 10.0 && s.average < 12.0).length;
    int countGood = widget.schoolClass.students.where((s) => s.average >= 12.0 && s.average < 14.0).length;
    int countVeryGood = widget.schoolClass.students.where((s) => s.average >= 14.0 && s.average < 16.0).length;
    int countExcellent = widget.schoolClass.students.where((s) => s.average >= 16.0).length;

    int totalPresentToday = widget.schoolClass.students.where((s) => s.status == 'حاضر').length;
    int totalAbsentToday = widget.schoolClass.students.where((s) => s.status == 'غائب').length;
    int totalEscapeToday = widget.schoolClass.students.where((s) => s.status == 'هروب').length;
    int totalLateToday = widget.schoolClass.students.where((s) => s.status == 'متأخر').length;
    int totalPermittedToday = widget.schoolClass.students.where((s) => s.status == 'خروج بإذن').length;

    return Scaffold(
      appBar: AppBar(
        title: Text('قسم: ${widget.schoolClass.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print, color: Color(0xFFF59E0B)),
            tooltip: 'طباعة سجل القسم الكامل PDF',
            onPressed: _exportFullClassRegisterPdf,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: const Color(0xFFF59E0B),
          tabs: const [
            Tab(icon: Icon(Icons.people), text: 'قائمة التلاميذ'),
            Tab(icon: Icon(Icons.bar_chart), text: 'مخطط الأداء'),
            Tab(icon: Icon(Icons.menu_book), text: 'دفتر النصوص'),
            Tab(icon: Icon(Icons.event_available), text: 'سجل الحضور'),
            Tab(icon: Icon(Icons.upload_file), text: 'استيراد رقمنة'),
            Tab(icon: Icon(Icons.history), text: 'سجل القسم اليومي'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 1. تبويب التلاميذ المطور
          Column(
            children: [
              // شريط البحث وخيارات الترتيب الأبجدي / بالمعدل
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'بحث بالاسم، اللقب، أو رقم التعريف...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        onChanged: (val) {
                          setState(() {
                            _studentSearchQuery = val;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    // زر الترتيب
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _sortCriteria,
                          icon: const Icon(Icons.sort, color: Color(0xFF0F172A)),
                          items: const [
                            DropdownMenuItem(value: 'alphabetical', child: Text('أبجدياً (أ-ي)')),
                            DropdownMenuItem(value: 'gradeDesc', child: Text('الأعلى معدلاً')),
                            DropdownMenuItem(value: 'gradeAsc', child: Text('الأدنى معدلاً')),
                            DropdownMenuItem(value: 'regNumber', child: Text('رقم التعريف')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _sortCriteria = val;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // شريط الأزرار السريعة والتسجيل التتابعي المنبثق
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // زر التسجيل التتابعي (طلبك المنبثق)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.flash_on, size: 18),
                        label: const Text('تسجيل تتابعي سريع (طالب بطالب)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        onPressed: _showSequentialAttendanceDialog,
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: _markAllStudentsPresent,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('تحضير الكل ✔', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('$totalPresentToday حاضر 🟢  ', style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 12)),
                      Text('$totalAbsentToday غائب 🔴  ', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                      if (totalLateToday > 0)
                        Text('$totalLateToday متأخر 🟡  ', style: TextStyle(color: Colors.amber.shade800, fontWeight: FontWeight.bold, fontSize: 12)),
                      if (totalEscapeToday > 0)
                        Text('$totalEscapeToday هروب 🚨  ', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                      if (totalPermittedToday > 0)
                        Text('$totalPermittedToday بإذن 📜  ', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
              ),

              // قائمة بطاقات التلاميذ الفسيحة مع إمكانية تعديل كل تلميذ
              Expanded(
                child: filteredStudents.isEmpty
                    ? const Center(child: Text('لا يوجد تلاميذ مطابقون.'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        itemCount: filteredStudents.length,
                        itemBuilder: (context, index) {
                          final student = filteredStudents[index];
                          List<Student> rankSorted = List.from(widget.schoolClass.students)
                            ..sort((a, b) => b.average.compareTo(a.average));
                          int rank = rankSorted.indexOf(student) + 1;

                          String statusDisplay = student.status;
                          if (student.statusTime != null && student.statusTime!.isNotEmpty) {
                            statusDisplay += ' (${student.statusTime})';
                          }

                          final badgeBg = _getStatusBgColor(student.status, isDark);
                          final badgeFg = _getStatusTextColor(student.status, isDark);

                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: student.status == 'هروب'
                                    ? Colors.red.shade400
                                    : (student.status == 'غائب'
                                        ? Colors.red.shade200
                                        : Colors.grey.shade300.withOpacity(0.4)),
                                width: student.status == 'هروب' ? 1.5 : 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // السطر الأول: الرتبة، الاسم الكامل، زر تعديل التلميذ، وشارة المواظبة
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 14,
                                        backgroundColor: student.average >= 10.0
                                            ? const Color(0xFF059669)
                                            : Colors.redAccent,
                                        child: Text('$rank',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${student.lastName} ${student.firstName}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                      ),
                                      // ✅ زر تعديل معلومات التلميذ (طلبك المباشر)
                                      IconButton(
                                        icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF059669)),
                                        tooltip: 'تعديل معلومات التلميذ',
                                        onPressed: () => _showEditStudentInfoDialog(student),
                                      ),
                                      const SizedBox(width: 4),

                                      // زر وشارة الحالة المتناسقة (عالية التباين والوضوح)
                                      PopupMenuButton<String>(
                                        tooltip: 'تغيير وضعية الحضور والمواظبة',
                                        onSelected: (target) => _showAttendanceActionDialog(student, target),
                                        itemBuilder: (context) => [
                                          const PopupMenuItem(value: 'حاضر', child: Text('حاضر 🟢')),
                                          const PopupMenuItem(value: 'غائب', child: Text('غائب 🔴')),
                                          const PopupMenuItem(value: 'متأخر', child: Text('دخول متأخر (مع وقت) 🟡')),
                                          const PopupMenuItem(value: 'هروب', child: Text('هروب من الحصة (مع وقت) 🚨')),
                                          const PopupMenuItem(value: 'خروج بإذن', child: Text('خروج بترخيص / إذن 📜')),
                                          const PopupMenuItem(value: 'معفى', child: Text('معفى ⚪')),
                                        ],
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: badgeBg,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: badgeFg.withOpacity(0.5), width: 1),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(_getStatusIcon(student.status), size: 15, color: badgeFg),
                                              const SizedBox(width: 5),
                                              Text(
                                                statusDisplay,
                                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeFg),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  // إذا كان هناك سبب مدون (كالخروج بإذن أو الهروب)
                                  if (student.statusReason != null && student.statusReason!.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'الملاحظة: ${student.statusReason}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                          fontWeight: FontWeight.bold,
                                          color: badgeFg),
                                    ),
                                  ],

                                  const Divider(height: 16),

                                  // السطر الثاني: تفاصيل العلامات والمعدل بوضوح تام
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'المعدل: ${student.average.toStringAsFixed(2)} / 20 (${student.appreciation})',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: student.average >= 10.0
                                                ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                                : Colors.redAccent,
                                            fontSize: 13),
                                      ),
                                      Text(
                                        'رقم: ${student.regNumber}',
                                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'تقويم: ${student.continuousEval} | ف1: ${student.exam1} | ف2: ${student.exam2 > 0 ? student.exam2 : '-'} | اختبار: ${student.test}',
                                    style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade300 : Colors.blueGrey.shade800),
                                  ),
                                  const SizedBox(height: 8),

                                  // السطر الثالث: أزرار العمليات بدون أي تداخل
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          foregroundColor: const Color(0xFFD97706),
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                        ),
                                        icon: const Icon(Icons.picture_as_pdf, size: 18),
                                        label: const Text('كشف نقاط', style: TextStyle(fontSize: 12)),
                                        onPressed: () => _exportStudentBulletinPdf(student, rank),
                                      ),
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          foregroundColor: student.status == 'هروب'
                                              ? Colors.red
                                              : const Color(0xFF059669),
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                        ),
                                        icon: Icon(
                                            student.status == 'هروب'
                                                ? Icons.warning_amber
                                                : Icons.notifications_active,
                                            size: 18),
                                        label: Text(
                                            student.status == 'هروب'
                                                ? 'إشعار هروب'
                                                : 'إشعار الولي',
                                            style: const TextStyle(fontSize: 12)),
                                        onPressed: () => _sendGuardianNotification(student),
                                      ),
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          foregroundColor: isDark ? Colors.lightBlueAccent : const Color(0xFF0F172A),
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                        ),
                                        icon: const Icon(Icons.edit_note, size: 18),
                                        label: const Text('العلامات', style: TextStyle(fontSize: 12)),
                                        onPressed: () => _showEditStudentGradesDialog(student),
                                      ),
                                      // ✅ سجل التلميذ الفردي
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          foregroundColor: const Color(0xFF6A0DAD),
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                        ),
                                        icon: const Icon(Icons.history, size: 18),
                                        label: const Text('سجل التلميذ', style: TextStyle(fontSize: 12)),
                                        onPressed: () => _showStudentPersonalLogDialog(student),
                                      ),
                                      // ✅ حذف تلميذ
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                        tooltip: 'حذف التلميذ',
                                        onPressed: () => _deleteStudent(student),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),

          // 2. تبويب المخطط البياني لإحصاءات النجاح
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        const Text('توزيع معدلات الفوج بيانيا',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 200,
                          child: BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: (widget.schoolClass.students.length.toDouble() + 2),
                              barTouchData: BarTouchData(enabled: true),
                              titlesData: FlTitlesData(
                                show: true,
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (v, m) {
                                      switch (v.toInt()) {
                                        case 0:
                                          return const Text('< 10');
                                        case 1:
                                          return const Text('10-12');
                                        case 2:
                                          return const Text('12-14');
                                        case 3:
                                          return const Text('14-16');
                                        case 4:
                                          return const Text('16-20');
                                        default:
                                          return const Text('');
                                      }
                                    },
                                  ),
                                ),
                                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              gridData: const FlGridData(show: false),
                              borderData: FlBorderData(show: false),
                              barGroups: [
                                BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: countWeak.toDouble(), color: Colors.redAccent, width: 22)]),
                                BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: countAverage.toDouble(), color: Colors.orange, width: 22)]),
                                BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: countGood.toDouble(), color: Colors.blueGrey, width: 22)]),
                                BarChartGroupData(x: 3, barRods: [BarChartRodData(toY: countVeryGood.toDouble(), color: const Color(0xFF0D9488), width: 22)]),
                                BarChartGroupData(x: 4, barRods: [BarChartRodData(toY: countExcellent.toDouble(), color: const Color(0xFFF59E0B), width: 22)]),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.trending_up, color: Color(0xFF059669), size: 32),
                    title: const Text('نسبة النجاح العامة في الفوج'),
                    trailing: Text(
                      '${widget.schoolClass.students.isEmpty ? "0" : ((widget.schoolClass.students.where((s) => s.average >= 10.0).length / widget.schoolClass.students.length) * 100).toStringAsFixed(1)} %',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. تبويب دفتر النصوص
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة مذكرة درس جديد'),
                  onPressed: () => _showAddNoteDialog(),
                ),
              ),
              Expanded(
                child: widget.schoolClass.lessonNotes.isEmpty
                    ? const Center(child: Text('لا توجد مذكرات دروس مسجلة بعد.'))
                    : ListView.builder(
                        itemCount: widget.schoolClass.lessonNotes.length,
                        itemBuilder: (context, index) {
                          final note = widget.schoolClass.lessonNotes[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: ListTile(
                              title: Text('${note.date}: ${note.title}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('الخلاصة: ${note.summary}\nالواجب: ${note.homework}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(icon: const Icon(Icons.edit, color: Colors.blueGrey), onPressed: () => _showAddNoteDialog(note: note)),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                                    onPressed: () async {
                                      setState(() {
                                        widget.schoolClass.lessonNotes.removeAt(index);
                                      });
                                      await SchoolData.saveData();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),

          // 4. تبويب سجل الحضور والغياب المفصل
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.done_all),
                        label: const Text('تسجيل حضور الجميع اليوم'),
                        onPressed: _markAllStudentsPresent,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: widget.schoolClass.dailyRecords.isEmpty
                    ? const Center(
                        child: Text(
                            'لا توجد جلسات حضور مسجلة بعد.\nقم بالنقر على حالة الحضور في قائمة التلاميذ لتسجيل جلسة اليوم.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: widget.schoolClass.dailyRecords.length,
                        itemBuilder: (context, index) {
                          final record = widget.schoolClass.dailyRecords[index];
                          int present = record.studentStatuses.values.where((v) => v.status == 'حاضر').length;
                          int absent = record.studentStatuses.values.where((v) => v.status == 'غائب').length;
                          int lateCount = record.studentStatuses.values.where((v) => v.status == 'متأخر').length;
                          int escapeCount = record.studentStatuses.values.where((v) => v.status == 'هروب').length;
                          int permitCount = record.studentStatuses.values.where((v) => v.status == 'خروج بإذن').length;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ExpansionTile(
                              leading: CircleAvatar(
                                  backgroundColor: escapeCount > 0 ? Colors.red : const Color(0xFF059669),
                                  child: Icon(escapeCount > 0 ? Icons.warning : Icons.event, color: Colors.white)),
                              title: Text('تاريخ الحصة: ${record.date}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  'حاضر: $present | غائب: $absent | متأخر: $lateCount ${escapeCount > 0 ? "| هروب: $escapeCount" : ""} ${permitCount > 0 ? "| إذن: $permitCount" : ""}'),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: record.studentStatuses.entries.map((entry) {
                                      final student = widget.schoolClass.students.firstWhere(
                                        (s) => s.regNumber == entry.key,
                                        orElse: () => Student(
                                            firstName: '',
                                            lastName: 'غير مسجل',
                                            regNumber: entry.key,
                                            birthDate: '',
                                            birthPlace: ''),
                                      );

                                      AttendanceDetail detail = entry.value;
                                      String label = detail.status;
                                      if (detail.time != null && detail.time!.isNotEmpty) {
                                        label += ' (${detail.time})';
                                      }

                                      final bBg = _getStatusBgColor(detail.status, isDark);
                                      final bFg = _getStatusTextColor(detail.status, isDark);

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 3.0),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                  '${student.lastName} ${student.firstName} (${student.regNumber}) ${detail.reason != null && detail.reason!.isNotEmpty ? " - " + detail.reason! : ""}'),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: bBg,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                label,
                                                style: TextStyle(
                                                  color: bFg,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                )
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),

          // 5. تبويب استيراد Excel ورقمنة من الهاتف
          Center(
            child: Padding(
              padding: const EdgeInsets.all(28.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_upload_outlined, size: 70, color: Color(0xFF059669)),
                  const SizedBox(height: 16),
                  const Text('استيراد قائمة التلاميذ من ملف Excel أو منصة «رقمنة»',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  const Text('يدعم ملفات الهاتف (.xlsx و .xls) مع التعرّف التلقائي على الأعمدة والأسماء.',
                      style: TextStyle(color: Colors.grey, fontSize: 13), textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: const Color(0xFFF59E0B),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('اختيار ملف من ذاكرة الهاتف', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: _importStudentsFromExcel,
                  ),
                  const SizedBox(height: 16),
                  // ✅ اختيار ملف يدوياً من أي مكان
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.file_present),
                    label: const Text('اختيار ملف يدوياً من أي مكان في الهاتف', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: _pickExcelFileManually,
                  ),
                ],
              ),
            ),
          ),

          // 6. تبويب السجل اليومي للقسم (بالوقت والتاريخ)
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة سجل يومي يدوي للقسم'),
                        onPressed: _showAddClassLogDialog,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: widget.schoolClass.dailyLogs.isEmpty
                    ? const Center(
                        child: Text(
                          'لا توجد سجلات يومية للقسم بعد.\nابدأ بتسجيل الحضور أو تعديل العلامات أو استيراد التلاميذ.',
                          textAlign: TextAlign.center,
                        ))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: widget.schoolClass.dailyLogs.length,
                        itemBuilder: (context, index) {
                          final log = widget.schoolClass.dailyLogs[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFF0F172A),
                                child: const Icon(Icons.history, color: Colors.white, size: 20),
                              ),
                              title: Text(log.action, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                '${log.details}\nالتاريخ: ${log.date} | الوقت: ${log.time} | المسجل: ${log.performedBy}',
                              ),
                              trailing: Text('${log.date} ${log.time}',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: const Color(0xFFF59E0B),
        onPressed: _showAddStudentDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('إضافة تلميذ'),
      ),
    );
  }
}
