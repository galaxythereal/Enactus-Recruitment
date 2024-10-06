// ignore_for_file: unrelated_type_equality_checks, avoid_print, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
// ignore: unused_import
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lottie/lottie.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:workmanager/workmanager.dart';

// Add these constants at the top of your file
// Sophisticated color palette for a professional recruiting tool
const Color kPrimaryColor = Color(0xFF1E88E5);
const Color kSecondaryColor = Color(0xFF42A5F5);
const Color kAccentColor = Color(0xFF64B5F6);
const Color kBackgroundColor = Color(0xFFF5F5F5);
const Color kCardColor = Colors.white;
const Color kTextColor = Color(0xFF333333);
const Color kSubtitleColor = Color(0xFF757575);
// const Color kPrimaryColor = Color(0xFFD2B48C);  // Beige
// const Color kSecondaryColor = Color(0xFFB5A57D);  // Muted beige for secondary elements
// const Color kAccentColor = Color(0xFF7D674C);  // Darker beige accent
// const Color kBackgroundColor = Color(0xFFF8F4E3);  // Light beige background
// const Color kCardColor = Color(0xFFF5F0DC);  // Lighter beige for cards
// const Color kTextColor = Color(0xFF4B4B4B);  // Darker gray-brown for text
// const Color kSubtitleColor = Color(0xFF8A7E6D);  // Muted brown-gray for subtitles

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(callbackDispatcher);
  final sharedPreferences = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPreferences),
    ],
    child: const EnactusRecruitmentApp(),
  ));
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case 'syncData':
        await syncDataToGoogleSheets();
        break;
    }
    return Future.value(true);
  });
}

Future<void> syncDataToGoogleSheets() async {
  final prefs = await SharedPreferences.getInstance();
  final applications = prefs.getStringList('pendingApplications') ?? [];

  if (applications.isEmpty) return;

  final connectivityResult = await Connectivity().checkConnectivity();
  if (connectivityResult == ConnectivityResult.none) return;

  const sheetUrl =
      'https://script.google.com/macros/s/AKfycbxdNZe7Qnr5Rr2rEBR_KkOxmkbxa-_YkgH3OWz3-mpdBV30aFdntb3_NvCAQJ4AeA64/exec';

  for (var appJson in applications) {
    try {
      final response = await http.post(
        Uri.parse(sheetUrl),
        body: appJson,
      );

      if (response.statusCode == 200) {
        applications.remove(appJson);
      }
    } catch (e) {
      print('Error syncing data: $e');
    }
  }

  await prefs.setStringList('pendingApplications', applications);
}

// Providers
final sharedPreferencesProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError());

final themeProvider = StateProvider<ThemeMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getString('themeMode') == 'dark'
      ? ThemeMode.dark
      : ThemeMode.light;
});

final applicationsProvider =
    StateNotifierProvider<ApplicationsNotifier, List<Application>>((ref) {
  return ApplicationsNotifier(ref.watch(sharedPreferencesProvider));
});

final recruiterLeaderboardProvider =
    StateNotifierProvider<RecruiterLeaderboardNotifier, List<RecruiterStats>>(
        (ref) {
  return RecruiterLeaderboardNotifier();
});

class RecruiterStats {
  final String name;
  final int recruitCount;

  RecruiterStats({required this.name, required this.recruitCount});
}

class RecruiterLeaderboardNotifier extends StateNotifier<List<RecruiterStats>> {
  RecruiterLeaderboardNotifier() : super([]);

  Future<void> fetchLeaderboard() async {
    try {
      final response = await http.get(Uri.parse(
          'https://script.google.com/macros/s/AKfycbxdNZe7Qnr5Rr2rEBR_KkOxmkbxa-_YkgH3OWz3-mpdBV30aFdntb3_NvCAQJ4AeA64/exec?action=getLeaderboard'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        state = data
            .map((item) => RecruiterStats(
                  name: item['recruiter'],
                  recruitCount: item['count'],
                ))
            .toList();
      }
    } catch (e) {
      print('Error fetching leaderboard: $e');
    }
  }
}

// Models
class Application {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String college;
  final String committee;
  final DateTime timestamp;
  final String? profileImagePath;
  final String recruiter;

  Application({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.college,
    required this.committee,
    required this.timestamp,
    this.profileImagePath,
    required this.recruiter,
  });

  factory Application.fromJson(Map<String, dynamic> json) {
    return Application(
      id: json['id'],
      name: json['name'],
      email: json['email'],
      phone: json['phone'],
      college: json['college'],
      committee: json['committee'],
      timestamp: DateTime.parse(json['timestamp']),
      profileImagePath: json['profileImagePath'],
      recruiter: json['recruiter'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'college': college,
      'committee': committee,
      'timestamp': timestamp.toIso8601String(),
      'profileImagePath': profileImagePath,
      'recruiter': recruiter,
    };
  }
}

class ApplicationsNotifier extends StateNotifier<List<Application>> {
  final SharedPreferences _prefs;

  ApplicationsNotifier(this._prefs) : super([]) {
    _loadApplications();
  }

  void _loadApplications() {
    final applicationsJson = _prefs.getString('applications');
    if (applicationsJson != null) {
      final List<dynamic> decoded = jsonDecode(applicationsJson);
      state = decoded.map((item) => Application.fromJson(item)).toList();
    }
  }

  void _saveApplications() {
    final applicationsJson =
        jsonEncode(state.map((app) => app.toJson()).toList());
    _prefs.setString('applications', applicationsJson);
  }

  Future<void> addApplication(Application application) async {
    state = [...state, application];
    _saveApplications();

    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult != ConnectivityResult.none) {
      await _syncApplicationToGoogleSheets(application);
    } else {
      _savePendingApplication(application);
    }
  }

  Future<void> _syncApplicationToGoogleSheets(Application application) async {
    const sheetUrl =
        'https://script.google.com/macros/s/AKfycbxdNZe7Qnr5Rr2rEBR_KkOxmkbxa-_YkgH3OWz3-mpdBV30aFdntb3_NvCAQJ4AeA64/exec';
    try {
      final response = await http.post(
        Uri.parse(sheetUrl),
        body: jsonEncode(application.toJson()),
      );

      if (response.statusCode != 200) {
        _savePendingApplication(application);
      }
    } catch (e) {
      print('Error syncing data: $e');
      _savePendingApplication(application);
    }
  }

  void _savePendingApplication(Application application) {
    final pendingApps = _prefs.getStringList('pendingApplications') ?? [];
    pendingApps.add(jsonEncode(application.toJson()));
    _prefs.setStringList('pendingApplications', pendingApps);
  }

  Future<bool> syncPendingApplications() async {
    final pendingApps = _prefs.getStringList('pendingApplications') ?? [];

    if (pendingApps.isEmpty) return true;

    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      throw Exception('No internet connection');
    }

    const sheetUrl =
        'https://script.google.com/macros/s/AKfycbxdNZe7Qnr5Rr2rEBR_KkOxmkbxa-_YkgH3OWz3-mpdBV30aFdntb3_NvCAQJ4AeA64/exec';
    List<String> successfulSyncs = [];

    for (var appJson in pendingApps) {
      try {
        final response = await http.post(
          Uri.parse(sheetUrl),
          body: appJson,
        );

        if (response.statusCode == 200) {
          successfulSyncs.add(appJson);
        }
      } catch (e) {
        print('Error syncing data: $e');
      }
    }

    // Remove successfully synced applications
    for (var syncedApp in successfulSyncs) {
      pendingApps.remove(syncedApp);
    }

    await _prefs.setStringList('pendingApplications', pendingApps);
    return pendingApps.isEmpty;
  }

  void removeApplication(String id) {
    state = state.where((app) => app.id != id).toList();
    _saveApplications();
  }
}

class EnactusRecruitmentApp extends ConsumerWidget {
  const EnactusRecruitmentApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'Enactus Recruitment',
      themeMode: themeMode,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: const HomePage(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    var baseTheme =
        brightness == Brightness.light ? ThemeData.light() : ThemeData.dark();

    return baseTheme.copyWith(
      primaryColor: kPrimaryColor,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? kBackgroundColor
          : const Color(0xFF1A1A1A),
      cardColor:
          brightness == Brightness.light ? kCardColor : const Color(0xFF2D2D2D),
      colorScheme: ColorScheme.fromSwatch().copyWith(
        secondary: kSecondaryColor,
        brightness: brightness,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(baseTheme.textTheme),
      cardTheme: CardTheme(
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 4,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200.0,
            floating: false,
            pinned: true,
            stretch: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    'https://i.postimg.cc/x84T6xRZ/IMG-7344-topaz-faceai-sharpen.jpg',
                    fit: BoxFit.cover,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    left: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Enactus Menoufia Recruitment',
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'One Team One Dream.',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.leaderboard, color: Colors.white),
                onPressed: () =>
                    _navigateWithAnimation(const RecruiterLeaderboardPage()),
              ),
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.white),
                onPressed: () => _navigateWithAnimation(const SettingsPage()),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome, Recruiter',
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: kPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Empower change through recruitment',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          color: kSubtitleColor,
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: _buildFeatureCard(
                          title: 'Register New Recruit',
                          subtitle: 'Add a new member to Enactus Menoufia',
                          icon: Icons.person_add,
                          onTap: () =>
                              _navigateWithAnimation(const RegistrationPage()),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildRecruiterTools(),
                      const SizedBox(height: 24),
                      _buildRecentActivity(),
                      const SizedBox(height: 24),
                      _buildTributeBanner(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity, // This makes the card take full width
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [kPrimaryColor, kSecondaryColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: kPrimaryColor,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: Text(
                      'Get Started',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecruiterTools() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recruiter Tools',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: kTextColor,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildToolButton(
                    icon: Icons.sync,
                    label: 'Sync Data',
                    onPressed: () async {
                      try {
                        await ref
                            .read(applicationsProvider.notifier)
                            .syncPendingApplications();
                        _showSuccessSnackBar('Sync completed successfully');
                      } catch (e) {
                        _showErrorSnackBar('Sync failed: ${e.toString()}');
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildToolButton(
                    icon: Icons.admin_panel_settings,
                    label: 'Admin Panel',
                    onPressed: () =>
                        _navigateWithAnimation(const AdminLoginPage()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: kSecondaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
    );
  }

  Widget _buildRecentActivity() {
    final applications = ref.watch(applicationsProvider);
    final recentApplications = applications.take(5).toList();

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Activity',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: kTextColor,
              ),
            ),
            const SizedBox(height: 16),
            if (recentApplications.isEmpty)
              Text(
                'No recent applications',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: kSubtitleColor,
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recentApplications.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final application = recentApplications[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: application.profileImagePath != null
                          ? FileImage(File(application.profileImagePath!))
                          : null,
                      child: application.profileImagePath == null
                          ? Text(application.name[0])
                          : null,
                    ),
                    title: Text(
                      application.name,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        color: kTextColor,
                      ),
                    ),
                    subtitle: Text(
                      application.committee,
                      style: GoogleFonts.poppins(
                        color: kSubtitleColor,
                      ),
                    ),
                    trailing: Text(
                      _formatDate(application.timestamp),
                      style: GoogleFonts.poppins(
                        color: kSubtitleColor,
                        fontSize: 12,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTributeBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kAccentColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: kAccentColor,
            child: const Icon(Icons.code, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Developed with ❤️ by',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: kSubtitleColor,
                  ),
                ),
                Text(
                  'Mahmoud Ezzat',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: kTextColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _navigateWithAnimation(Widget page) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOutCubic;
          var tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);
          return SlideTransition(position: offsetAnimation, child: child);
        },
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class RegistrationPage extends ConsumerStatefulWidget {
  const RegistrationPage({super.key});

  @override
  _RegistrationPageState createState() => _RegistrationPageState();
}

// Add this new widget
class RecruiterLeaderboardPage extends ConsumerStatefulWidget {
  const RecruiterLeaderboardPage({super.key});

  @override
  _RecruiterLeaderboardPageState createState() =>
      _RecruiterLeaderboardPageState();
}

class _RecruiterLeaderboardPageState
    extends ConsumerState<RecruiterLeaderboardPage> {
  @override
  void initState() {
    super.initState();
    ref.read(recruiterLeaderboardProvider.notifier).fetchLeaderboard();
  }

  @override
  Widget build(BuildContext context) {
    final leaderboard = ref.watch(recruiterLeaderboardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Recruiter Leaderboard')),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(recruiterLeaderboardProvider.notifier).fetchLeaderboard(),
        child: ListView.builder(
          itemCount: leaderboard.length,
          itemBuilder: (context, index) {
            final stats = leaderboard[index];
            return ListTile(
              leading: CircleAvatar(child: Text('${index + 1}')),
              title: Text(stats.name),
              trailing: Text('${stats.recruitCount} recruits'),
            );
          },
        ),
      ),
    );
  }
}

class _RegistrationPageState extends ConsumerState<RegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _recruiterController = TextEditingController();
  final TextEditingController _collegeController = TextEditingController();
  String _selectedCommittee = '';
  bool _isLoading = false;
  File? _profileImage;
  String _selectedEmailSuffix = '@gmail.com';
  List<String> _registeredColleges = [];

  List<String> committees = [
    'Project',
    'Presentation',
    'Graphic Design',
    'Video Editing and Photography',
    'PR&FR',
    'Logistics',
    'HR',
    'Digital Marketing'
  ];

  List<String> emailSuffixes = [
    '@gmail.com',
    '@hotmail.com',
    '@outlook.com',
    '@yahoo.com',
  ];

  @override
  void initState() {
    super.initState();
    _loadRegisteredColleges();
  }

  void _loadRegisteredColleges() {
    final prefs = ref.read(sharedPreferencesProvider);
    _registeredColleges = prefs.getStringList('registeredColleges') ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Apply to Enactus')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GestureDetector(
                  onTap: _pickImage,
                  child: CircleAvatar(
                    radius: 50,
                    backgroundImage: _profileImage != null
                        ? FileImage(_profileImage!)
                        : null,
                    child: _profileImage == null
                        ? const Icon(Icons.add_a_photo, size: 40)
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email Address',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your email';
                          }
                          if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(value)) {
                            return 'Invalid email format';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _selectedEmailSuffix,
                      items: emailSuffixes.map((String suffix) {
                        return DropdownMenuItem<String>(
                          value: suffix,
                          child: Text(suffix),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedEmailSuffix = newValue!;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your phone number';
                    }
                    if (!RegExp(r'^01[0125][0-9]{8}$').hasMatch(value)) {
                      return 'Please enter a valid Egyptian phone number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _registeredColleges.isEmpty
                    ? TextFormField(
                        controller: _collegeController,
                        decoration: const InputDecoration(
                          labelText: 'College',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.school),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your college name';
                          }
                          return null;
                        },
                      )
                    : DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'College',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.school),
                        ),
                        value: _collegeController.text.isNotEmpty
                            ? _collegeController.text
                            : null,
                        items: _registeredColleges.map((String college) {
                          return DropdownMenuItem<String>(
                            value: college,
                            child: Text(college),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            _collegeController.text = newValue!;
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please select your college';
                          }
                          return null;
                        },
                      ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Committee',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.group),
                  ),
                  value:
                      _selectedCommittee.isNotEmpty ? _selectedCommittee : null,
                  items: committees.map((String committee) {
                    return DropdownMenuItem<String>(
                      value: committee,
                      child: Text(committee),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedCommittee = newValue!;
                    });
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please select a committee';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _recruiterController,
                  decoration: const InputDecoration(
                    labelText: 'Recruiter Name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_add),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter the recruiter\'s name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submitForm,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Submit Application'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _profileImage = File(image.path);
      });
    }
  }

  void _submitForm() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        String? profileImagePath;
        if (_profileImage != null) {
          final directory = await getApplicationDocumentsDirectory();
          final imagePath =
              '${directory.path}/${DateTime.now().millisecondsSinceEpoch}.png';
          await _profileImage!.copy(imagePath);
          profileImagePath = imagePath;
        }

        final newApplication = Application(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: _nameController.text,
          email: '${_emailController.text}$_selectedEmailSuffix',
          phone: _phoneController.text,
          college: _collegeController.text,
          committee: _selectedCommittee,
          timestamp: DateTime.now(),
          profileImagePath: profileImagePath,
          recruiter: _recruiterController.text,
        );

        await ref
            .read(applicationsProvider.notifier)
            .addApplication(newApplication);

        // Add the college to registered colleges if it's not already there
        if (!_registeredColleges.contains(_collegeController.text)) {
          _registeredColleges.add(_collegeController.text);
          final prefs = ref.read(sharedPreferencesProvider);
          await prefs.setStringList('registeredColleges', _registeredColleges);
        }

        setState(() {
          _isLoading = false;
        });

        _showSuccessDialog();
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        _showErrorDialog();
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Application Submitted'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Lottie.network(
                'https://assets10.lottiefiles.com/packages/lf20_wcnjmdp1.json',
                width: 200,
                height: 200,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              const Text(
                  'Thank you for applying to Enactus! We will contact you soon.'),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // Return to home page
              },
            ),
          ],
        );
      },
    );
  }

  void _showErrorDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error'),
          content: const Text(
              'An error occurred while submitting your application. Please try again later.'),
          actions: [
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  _AdminLoginPageState createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your username';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your password';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _login,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                child: const Text('Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _login() {
    if (_formKey.currentState!.validate()) {
      // For demonstration purposes, we're using a hardcoded username and password
      // In a real application, you should implement proper authentication
      if (_usernameController.text == 'admin' &&
          _passwordController.text == 'password') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const AdminDashboardPage()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid credentials')),
        );
      }
    }
  }
}

class AdminDashboardPage extends ConsumerWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final applications = ref.watch(applicationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('Applications Overview',
                style: Theme.of(context).textTheme.headlineSmall),
          ),
          AspectRatio(
            aspectRatio: 1.70,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: ApplicationsChart(applications: applications),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Recent Applications',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref
                    .read(applicationsProvider.notifier)
                    .syncPendingApplications();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sync completed successfully')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Sync failed: ${e.toString()}')),
                );
              }
            },
            child: const Text('Sync Pending Applications'),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: applications.length,
            itemBuilder: (context, index) {
              final application = applications[index];
              return ListTile(
                leading: application.profileImagePath != null
                    ? CircleAvatar(
                        backgroundImage:
                            FileImage(File(application.profileImagePath!)))
                    : CircleAvatar(child: Text(application.name[0])),
                title: Text(application.name),
                subtitle: Text(application.committee),
                trailing: Text(application.timestamp.toString().split(' ')[0]),
                onTap: () => _showApplicationDetails(context, application),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showApplicationDetails(BuildContext context, Application application) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Application Details'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (application.profileImagePath != null)
                  Image.file(File(application.profileImagePath!),
                      height: 100, width: 100),
                Text('Name: ${application.name}'),
                Text('Email: ${application.email}'),
                Text('Phone: ${application.phone}'),
                Text('College: ${application.college}'),
                Text('Committee: ${application.committee}'),
                Text('Applied on: ${application.timestamp}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Close'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }
}

class ApplicationsChart extends StatelessWidget {
  final List<Application> applications;

  const ApplicationsChart({super.key, required this.applications});

  @override
  Widget build(BuildContext context) {
    final committeeData = _getCommitteeData();
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: committeeData.isNotEmpty
            ? committeeData.map((d) => d.y).reduce((a, b) => a > b ? a : b)
            : 0,
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                int index = value.toInt();
                return Text(
                  index < committeeData.length ? committeeData[index].x[0] : '',
                  style: const TextStyle(
                    color: Color(0xff7589a2),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                );
              },
              reservedSize: 20,
            ),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: committeeData
            .asMap()
            .entries
            .map((entry) => BarChartGroupData(
                  x: entry.key,
                  barRods: [
                    BarChartRodData(toY: entry.value.y, color: Colors.blue)
                  ],
                ))
            .toList(),
      ),
    );
  }

  List<CommitteeData> _getCommitteeData() {
    final Map<String, int> committeeCounts = {};
    for (var app in applications) {
      committeeCounts[app.committee] =
          (committeeCounts[app.committee] ?? 0) + 1;
    }
    return committeeCounts.entries
        .map((entry) => CommitteeData(entry.key, entry.value.toDouble()))
        .toList();
  }
}

class CommitteeData {
  final String x;
  final double y;

  CommitteeData(this.x, this.y);
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Dark Mode'),
            trailing: Switch(
              value: themeMode == ThemeMode.dark,
              onChanged: (value) {
                ref.read(themeProvider.notifier).state =
                    value ? ThemeMode.dark : ThemeMode.light;
                final prefs = ref.read(sharedPreferencesProvider);
                prefs.setString('themeMode', value ? 'dark' : 'light');
              },
            ),
          ),
        ],
      ),
    );
  }
}
