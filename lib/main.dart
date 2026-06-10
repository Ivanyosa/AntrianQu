import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://nivxlapozweehskulitb.supabase.co';
const supabasePublishableKey = 'sb_publishable_hqIGWx411SXfDeiCamQcVA_uSC-tUbF';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
  runApp(const ProviderScope(child: AntrianQAIApp()));
}

final supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final sessionProvider = StreamProvider<Session?>((ref) async* {
  final client = ref.watch(supabaseProvider);
  yield client.auth.currentSession;
  yield* client.auth.onAuthStateChange.map((event) => event.session);
});

final profileProvider = FutureProvider<AppProfile?>((ref) async {
  final session = await ref.watch(sessionProvider.future);
  if (session == null) return null;
  final client = ref.watch(supabaseProvider);
  final data = await client
      .from('profiles')
      .select()
      .eq('id', session.user.id)
      .maybeSingle();
  if (data == null) return null;
  return AppProfile.fromJson(data);
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
      return AuthController(ref.watch(supabaseProvider), ref);
    });

final businessesProvider = FutureProvider<List<Business>>((ref) async {
  final client = ref.watch(supabaseProvider);
  final data = await client
      .from('businesses')
      .select()
      .inFilter('approval_status', ['approved', 'pending_update'])
      .order('name');
  return (data as List).map((item) => Business.fromJson(item)).toList();
});

final activeQueueProvider = FutureProvider<QueueTicket?>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile == null) return null;
  final client = ref.watch(supabaseProvider);
  final data = await client
      .from('queues')
      .select('*, businesses(*)')
      .eq('user_id', profile.id)
      .eq('status', 'waiting')
      .maybeSingle();
  if (data == null) return null;
  return QueueTicket.fromJson(data);
});

final queueHistoryProvider = FutureProvider<List<QueueTicket>>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile == null) return const [];
  final client = ref.watch(supabaseProvider);
  final data = await client
      .from('queues')
      .select('*, businesses(*)')
      .eq('user_id', profile.id)
      .neq('status', 'waiting')
      .order('created_at', ascending: false);
  return (data as List).map((item) => QueueTicket.fromJson(item)).toList();
});

final myBusinessProvider = FutureProvider<Business?>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile == null) return null;
  final client = ref.watch(supabaseProvider);
  final data = await client
      .from('businesses')
      .select()
      .eq('owner_id', profile.id)
      .maybeSingle();
  if (data == null) return null;
  return Business.fromJson(data);
});

final ownerQueuesProvider = FutureProvider.family<List<QueueTicket>, String>((
  ref,
  businessId,
) async {
  final client = ref.watch(supabaseProvider);
  final data = await client
      .from('queues')
      .select('*, businesses(*)')
      .eq('business_id', businessId)
      .eq('status', 'waiting')
      .order('queue_number');
  return (data as List).map((item) => QueueTicket.fromJson(item)).toList();
});

final adminStatsProvider = FutureProvider<AdminStats>((ref) async {
  final client = ref.watch(supabaseProvider);
  final profiles = await client.from('profiles').select('id');
  final businesses = await client.from('businesses').select('id');
  final activeQueues = await client
      .from('queues')
      .select('id')
      .eq('status', 'waiting');
  return AdminStats(
    users: (profiles as List).length,
    businesses: (businesses as List).length,
    activeQueues: (activeQueues as List).length,
  );
});

final pendingBusinessesProvider = FutureProvider<List<Business>>((ref) async {
  final client = ref.watch(supabaseProvider);
  final data = await client
      .from('businesses')
      .select()
      .eq('approval_status', 'pending')
      .order('created_at', ascending: false);
  return (data as List).map((item) => Business.fromJson(item)).toList();
});

final pendingUpdateRequestsProvider =
    FutureProvider<List<BusinessUpdateRequest>>((ref) async {
      final client = ref.watch(supabaseProvider);
      final data = await client
          .from('business_update_requests')
          .select('*, businesses(name)')
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      return (data as List)
          .map((item) => BusinessUpdateRequest.fromJson(item))
          .toList();
    });

final appActionProvider =
    StateNotifierProvider<AppActionController, AsyncValue<void>>((ref) {
      return AppActionController(ref.watch(supabaseProvider), ref);
    });

final hasAdminProvider = FutureProvider<bool>((ref) async {
  final client = ref.watch(supabaseProvider);

  final data = await client.from('profiles').select('id').eq('role', 'admin');

  return (data as List).isNotEmpty;
});

class AntrianQAIApp extends StatelessWidget {
  const AntrianQAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AntrianQAI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return session.when(
      loading: () => const BrandedLoadingScreen(),
      error: (error, stackTrace) => ErrorScreen(message: error.toString()),
      data: (value) {
        if (value == null) return const LoginScreen();
        final profile = ref.watch(profileProvider);
        return profile.when(
          loading: () => const BrandedLoadingScreen(),
          error: (error, stackTrace) => ErrorScreen(message: error.toString()),
          data: (profile) {
            if (profile == null) {
              return const ErrorScreen(
                message: 'Profil belum tersedia. Coba logout lalu login lagi.',
              );
            }
            if (profile.isAdmin) return AdminShell(profile: profile);
            return UserShell(profile: profile);
          },
        );
      },
    );
  }
}

class AuthController extends StateNotifier<AsyncValue<void>> {
  AuthController(this._client, this._ref) : super(const AsyncData(null));

  final SupabaseClient _client;
  final Ref _ref;

  Future<void> signIn(String username, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _client.auth.signInWithPassword(
        email: usernameToEmail(username),
        password: password,
      );
      _ref.invalidate(profileProvider);
    });
  }

  Future<void> register(String username, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _client.auth.signUp(
        email: usernameToEmail(username),
        password: password,
        data: {'username': normalizeUsername(username)},
      );
      _ref.invalidate(profileProvider);
    });
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _client.auth.signOut();
      _ref.invalidate(profileProvider);
    });
  }
}

class AppActionController extends StateNotifier<AsyncValue<void>> {
  AppActionController(this._client, this._ref) : super(const AsyncData(null));

  final SupabaseClient _client;
  final Ref _ref;

  Future<Map<String, dynamic>?> takeQueue(String businessId) async {
    state = const AsyncLoading();
    Map<String, dynamic>? result;
    state = await AsyncValue.guard(() async {
      final data = await _client.rpc(
        'take_queue',
        params: {'p_business_id': businessId},
      );
      result = Map<String, dynamic>.from(data as Map);
      _refreshQueueData();
    });
    return result;
  }

  Future<void> cancelQueue(String queueId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _client.rpc('cancel_queue', params: {'p_queue_id': queueId});
      _refreshQueueData();
    });
  }

  Future<void> registerBusiness({
    required String name,
    required String location,
    required String description,
    required int serviceDuration,
    required int maxDailyQueue,
    String? logoUrl,
  }) async {
    final profile = await _ref.read(profileProvider.future);
    if (profile == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _client.from('businesses').insert({
        'owner_id': profile.id,
        'name': name,
        'logo_url': logoUrl,
        'location': location,
        'description': description,
        'service_duration': serviceDuration,
        'max_daily_queue': maxDailyQueue,
        'status': 'closed',
        'approval_status': 'pending',
      });
      _ref.invalidate(myBusinessProvider);
    });
  }

  Future<void> setBusinessStatus(String businessId, String status) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _client.rpc(
        'set_business_status',
        params: {'p_business_id': businessId, 'p_status': status},
      );
      _refreshOwnerData(businessId);
    });
  }

  Future<void> nextQueue(String businessId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _client.rpc(
        'owner_next_queue',
        params: {'p_business_id': businessId},
      );
      _refreshOwnerData(businessId);
    });
  }

  Future<void> submitBusinessUpdate(
    String businessId,
    Map<String, dynamic> payload,
  ) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _client.rpc(
        'submit_business_update',
        params: {'p_business_id': businessId, 'p_payload': payload},
      );
      _ref.invalidate(myBusinessProvider);
    });
  }

  Future<void> approveBusiness(String businessId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _client.rpc(
        'approve_business',
        params: {'p_business_id': businessId},
      );
      _refreshAdminData();
    });
  }

  Future<void> rejectBusiness(String businessId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _client.rpc(
        'reject_business',
        params: {'p_business_id': businessId},
      );
      _refreshAdminData();
    });
  }

  Future<void> approveUpdate(String requestId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _client.rpc(
        'approve_business_update',
        params: {'p_request_id': requestId},
      );
      _refreshAdminData();
    });
  }

  Future<void> rejectUpdate(String requestId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _client.rpc(
        'reject_business_update',
        params: {'p_request_id': requestId},
      );
      _refreshAdminData();
    });
  }

  Future<void> claimInitialAdmin() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _client.rpc('claim_initial_admin');
      _ref.invalidate(profileProvider);
    });
  }

  void _refreshQueueData() {
    _ref.invalidate(activeQueueProvider);
    _ref.invalidate(queueHistoryProvider);
    _ref.invalidate(businessesProvider);
  }

  void _refreshOwnerData(String businessId) {
    _ref.invalidate(myBusinessProvider);
    _ref.invalidate(ownerQueuesProvider(businessId));
    _ref.invalidate(businessesProvider);
  }

  void _refreshAdminData() {
    _ref.invalidate(adminStatsProvider);
    _ref.invalidate(pendingBusinessesProvider);
    _ref.invalidate(pendingUpdateRequestsProvider);
    _ref.invalidate(businessesProvider);
  }
}

class AppProfile {
  const AppProfile({
    required this.id,
    required this.username,
    required this.role,
  });

  final String id;
  final String username;
  final String role;

  bool get isAdmin => role == 'admin';

  factory AppProfile.fromJson(Map<String, dynamic> json) {
    return AppProfile(
      id: json['id'] as String,
      username: json['username'] as String? ?? 'user',
      role: json['role'] as String? ?? 'user',
    );
  }
}

class Business {
  const Business({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.location,
    required this.description,
    required this.serviceDuration,
    required this.maxDailyQueue,
    required this.status,
    required this.approvalStatus,
    required this.currentQueueNumber,
    this.logoUrl,
    this.createdAt,
  });

  final String id;
  final String ownerId;
  final String name;
  final String location;
  final String description;
  final int serviceDuration;
  final int maxDailyQueue;
  final String status;
  final String approvalStatus;
  final int currentQueueNumber;
  final String? logoUrl;
  final DateTime? createdAt;

  bool get isOpen => status == 'open';
  bool get isApproved => approvalStatus == 'approved';
  String get statusLabel => switch (status) {
    'open' => 'Open',
    'break' => 'Break',
    _ => 'Closed',
  };

  factory Business.fromJson(Map<String, dynamic> json) {
    return Business(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String? ?? 'Usaha',
      location: json['location'] as String? ?? '-',
      description: json['description'] as String? ?? '',
      serviceDuration: json['service_duration'] as int? ?? 10,
      maxDailyQueue: json['max_daily_queue'] as int? ?? 50,
      status: json['status'] as String? ?? 'closed',
      approvalStatus: json['approval_status'] as String? ?? 'pending',
      currentQueueNumber: json['current_queue_number'] as int? ?? 0,
      logoUrl: json['logo_url'] as String?,
      createdAt: parseDate(json['created_at']),
    );
  }
}

class QueueTicket {
  const QueueTicket({
    required this.id,
    required this.businessId,
    required this.userId,
    required this.queueNumber,
    required this.status,
    required this.createdAt,
    this.business,
  });

  final String id;
  final String businessId;
  final String userId;
  final int queueNumber;
  final String status;
  final DateTime createdAt;
  final Business? business;

  int get currentNow => business?.currentQueueNumber ?? 0;
  int get remaining => (queueNumber - currentNow).clamp(0, 9999);
  int get estimatedMinutes => remaining * (business?.serviceDuration ?? 10);

  factory QueueTicket.fromJson(Map<String, dynamic> json) {
    final businessData = json['businesses'];
    return QueueTicket(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      userId: json['user_id'] as String,
      queueNumber: json['queue_number'] as int? ?? 0,
      status: json['status'] as String? ?? 'waiting',
      createdAt: parseDate(json['created_at']) ?? DateTime.now(),
      business: businessData is Map<String, dynamic>
          ? Business.fromJson(businessData)
          : null,
    );
  }
}

class BusinessUpdateRequest {
  const BusinessUpdateRequest({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String businessId;
  final String businessName;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  factory BusinessUpdateRequest.fromJson(Map<String, dynamic> json) {
    final business = json['businesses'];
    return BusinessUpdateRequest(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      businessName: business is Map<String, dynamic>
          ? business['name'] as String
          : '-',
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
      createdAt: parseDate(json['created_at']) ?? DateTime.now(),
    );
  }
}

class AdminStats {
  const AdminStats({
    required this.users,
    required this.businesses,
    required this.activeQueues,
  });

  final int users;
  final int businesses;
  final int activeQueues;
}

class UserShell extends StatefulWidget {
  const UserShell({super.key, required this.profile});

  final AppProfile profile;

  @override
  State<UserShell> createState() => _UserShellState();
}

class _UserShellState extends State<UserShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(profile: widget.profile),
      const MyQueueScreen(),
      const QueueHistoryScreen(),
      ProfileScreen(profile: widget.profile),
    ];
    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: AppBottomNav(
        currentIndex: _index,
        onTap: (value) => setState(() => _index = value),
        items: const [
          AppNavItem(Icons.home_rounded, 'Home'),
          AppNavItem(Icons.hourglass_bottom_rounded, 'My Queue'),
          AppNavItem(Icons.history_rounded, 'History'),
          AppNavItem(Icons.person_outline_rounded, 'Profile'),
        ],
      ),
    );
  }
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.profile});

  final AppProfile profile;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const AdminDashboardScreen(),
      const AdminBusinessScreen(),
      const NotificationPreviewScreen(),
      ProfileScreen(profile: widget.profile),
    ];
    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: AppBottomNav(
        currentIndex: _index,
        onTap: (value) => setState(() => _index = value),
        items: const [
          AppNavItem(Icons.dashboard_outlined, 'Dashboard'),
          AppNavItem(Icons.business_center_outlined, 'Bisnis'),
          AppNavItem(Icons.settings_outlined, 'Sistem'),
          AppNavItem(Icons.person_outline_rounded, 'Profil'),
        ],
      ),
    );
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    await ref
        .read(authControllerProvider.notifier)
        .signIn(_username.text, _password.text);
    if (!mounted) return;
    final error = ref.read(authControllerProvider).error;
    if (error != null) showError(context, readableError(error));
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(authControllerProvider);
    return AuthScaffold(
      child: AppCard(
        padding: const EdgeInsets.all(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Welcome Back', style: context.text.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Sign in to manage your time.',
              style: context.text.bodyLarge?.copyWith(color: AppColors.ink2),
            ),
            const SizedBox(height: 28),
            AppTextField(
              controller: _username,
              label: 'Email or Username',
              hint: 'e.g. alex_doe',
              icon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: 18),
            AppTextField(
              controller: _password,
              label: 'Password',
              hint: '••••••••',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscure,
              trailing: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            const SizedBox(height: 26),
            PrimaryButton(
              label: 'Log In',
              icon: Icons.arrow_forward_rounded,
              loading: action.isLoading,
              onPressed: _login,
            ),
            const SizedBox(height: 26),
            const Divider(),
            const SizedBox(height: 22),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                children: [
                  Text('New here? ', style: context.text.bodyLarge),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    ),
                    child: Text(
                      'Create Account',
                      style: context.text.bodyLarge?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_password.text != _confirm.text) {
      showError(context, 'Konfirmasi password belum sama.');
      return;
    }
    await ref
        .read(authControllerProvider.notifier)
        .register(_username.text, _password.text);
    if (!mounted) return;
    final error = ref.read(authControllerProvider).error;
    if (error != null) {
      showError(context, readableError(error));
    } else {
      Navigator.of(context).pop();
      showSnack(context, 'Akun dibuat. Silakan login.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(authControllerProvider);
    return AuthScaffold(
      showBack: true,
      child: AppCard(
        padding: const EdgeInsets.all(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Create Account', style: context.text.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Mulai ambil antrian tanpa harus datang dulu.',
              style: context.text.bodyLarge?.copyWith(color: AppColors.ink2),
            ),
            const SizedBox(height: 28),
            AppTextField(
              controller: _username,
              label: 'Username',
              hint: 'alex_doe',
              icon: Icons.person_add_alt_1_outlined,
            ),
            const SizedBox(height: 18),
            AppTextField(
              controller: _password,
              label: 'Password',
              hint: 'Minimal 6 karakter',
              icon: Icons.lock_outline_rounded,
              obscureText: true,
            ),
            const SizedBox(height: 18),
            AppTextField(
              controller: _confirm,
              label: 'Konfirmasi Password',
              hint: 'Ulangi password',
              icon: Icons.verified_user_outlined,
              obscureText: true,
            ),
            const SizedBox(height: 26),
            PrimaryButton(
              label: 'Create Account',
              icon: Icons.arrow_forward_rounded,
              loading: action.isLoading,
              onPressed: _register,
            ),
          ],
        ),
      ),
    );
  }
}

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child, this.showBack = false});

  final Widget child;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            if (showBack)
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
            ListView(
              padding: const EdgeInsets.fromLTRB(24, 78, 24, 24),
              children: [
                const BrandHeader(),
                const SizedBox(height: 38),
                child,
                const SizedBox(height: 42),
                Text(
                  'CORPORATE QUEUE MANAGEMENT SYSTEM',
                  textAlign: TextAlign.center,
                  style: context.text.labelLarge?.copyWith(
                    color: AppColors.muted,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.profile});

  final AppProfile profile;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _search = '';
  String _filter = 'open';

  @override
  Widget build(BuildContext context) {
    final businesses = ref.watch(businessesProvider);
    final myBusiness = ref.watch(myBusinessProvider).valueOrNull;
    return AppPage(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(businessesProvider);
          ref.invalidate(myBusinessProvider);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.person, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        children: [
                          Text(
                            'Hello, ${titleCase(widget.profile.username)}',
                            style: context.text.headlineSmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (myBusiness?.isApproved == true)
                            const StatusBadge(label: 'BUSINESS OWNER'),
                        ],
                      ),
                      Text(
                        'Your time is valuable',
                        style: context.text.titleMedium?.copyWith(
                          color: AppColors.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => showSnack(
                    context,
                    'Notifikasi FCM siap dipasang setelah Firebase dikonfigurasi.',
                  ),
                  icon: const Icon(Icons.notifications_none_rounded),
                ),
              ],
            ),
            const SizedBox(height: 26),
            SearchBox(
              hint: 'Search businesses...',
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilterChipPill(
                  label: 'Lokasi',
                  icon: Icons.location_on_outlined,
                  selected: false,
                  onTap: () {},
                ),
                for (final status in ['open', 'break', 'closed'])
                  FilterChipPill(
                    label: switch (status) {
                      'open' => 'Open',
                      'break' => 'Break',
                      _ => 'Closed',
                    },
                    selected: _filter == status,
                    onTap: () => setState(() => _filter = status),
                  ),
              ],
            ),
            const SizedBox(height: 30),
            const PromoCard(),
            const SizedBox(height: 34),
            SectionHeader(
              title: 'Nearby Establishments',
              action: 'See all',
              onTap: () => setState(() => _filter = 'open'),
            ),
            const SizedBox(height: 16),
            businesses.when(
              loading: () => const LoadingList(),
              error: (error, stackTrace) => EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Gagal memuat usaha',
                message: readableError(error),
              ),
              data: (items) {
                final filtered = items.where((business) {
                  final matchesStatus = business.status == _filter;
                  final query = _search.trim().toLowerCase();
                  final matchesSearch =
                      query.isEmpty ||
                      business.name.toLowerCase().contains(query) ||
                      business.location.toLowerCase().contains(query) ||
                      business.status.toLowerCase().contains(query);
                  return matchesStatus && matchesSearch;
                }).toList();
                if (filtered.isEmpty) {
                  return const EmptyState(
                    icon: Icons.store_mall_directory_outlined,
                    title: 'Belum ada usaha yang cocok',
                    message:
                        'Usaha yang disetujui admin akan muncul di sini secara realtime.',
                  );
                }
                return Column(
                  children: [
                    for (final business in filtered)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: BusinessListTile(
                          business: business,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  BusinessDetailScreen(business: business),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class BusinessDetailScreen extends ConsumerWidget {
  const BusinessDetailScreen({super.key, required this.business});

  final Business business;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(appActionProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
        child: PrimaryButton(
          label: business.isOpen ? 'Ambil Antrian' : business.statusLabel,
          icon: Icons.arrow_forward_rounded,
          loading: action.isLoading,
          onPressed: business.isOpen
              ? () async {
                  final result = await ref
                      .read(appActionProvider.notifier)
                      .takeQueue(business.id);
                  if (!context.mounted) return;
                  final error = ref.read(appActionProvider).error;
                  if (error != null) {
                    showError(context, readableError(error));
                    return;
                  }
                  if (result != null) {
                    showQueueSuccessSheet(context, result);
                  }
                }
              : null,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          children: [
            HeaderBar(
              title: 'Business Details',
              leading: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            const SizedBox(height: 28),
            Stack(
              children: [
                BusinessHeroImage(business: business, height: 260),
                Positioned(
                  top: 18,
                  right: 18,
                  child: StatusBadge(
                    label: business.statusLabel,
                    color: statusColor(business.status),
                    dot: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            Text(
              business.name,
              style: context.text.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              business.description,
              style: context.text.titleMedium?.copyWith(
                height: 1.35,
                color: AppColors.ink2,
              ),
            ),
            const SizedBox(height: 18),
            IconLine(
              icon: Icons.location_on_outlined,
              text: business.location,
              color: AppColors.primary,
            ),
            const SizedBox(height: 28),
            AppCard(
              padding: const EdgeInsets.all(26),
              child: Column(
                children: [
                  Text(
                    'CURRENT ACTIVE NUMBER',
                    style: context.text.labelLarge?.copyWith(
                      color: AppColors.ink2,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '${business.currentQueueNumber}',
                    style: context.text.displayLarge?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  IconLine(
                    icon: Icons.trending_up_rounded,
                    text: business.isOpen
                        ? 'Steady Flow'
                        : business.statusLabel,
                    color: business.isOpen ? AppColors.teal : AppColors.ink2,
                    centered: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    icon: Icons.schedule_rounded,
                    label: 'Est. Wait',
                    value: '${business.serviceDuration} mins',
                    caption: 'per customer',
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: MetricCard(
                    icon: Icons.event_seat_outlined,
                    label: 'Daily Quota',
                    value:
                        '${business.currentQueueNumber} / ${business.maxDailyQueue}',
                    progress: business.maxDailyQueue == 0
                        ? 0
                        : business.currentQueueNumber / business.maxDailyQueue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 34),
            Text(
              'ABOUT THIS LOCATION',
              style: context.text.labelLarge?.copyWith(
                letterSpacing: 4,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            const FeatureRow(
              icon: Icons.wifi_rounded,
              title: 'High Speed Wi-Fi',
              subtitle: 'Complimentary for all guests',
            ),
            const SizedBox(height: 14),
            const FeatureRow(
              icon: Icons.bolt_outlined,
              title: 'Power Outlets',
              subtitle: 'Available at every table',
            ),
          ],
        ),
      ),
    );
  }
}

class MyQueueScreen extends ConsumerWidget {
  const MyQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(activeQueueProvider);
    final action = ref.watch(appActionProvider);
    return AppPage(
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(activeQueueProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
          children: [
            const HeaderBar(title: 'My Queue'),
            const SizedBox(height: 44),
            queue.when(
              loading: () => const LoadingList(),
              error: (error, stackTrace) => EmptyState(
                icon: Icons.hourglass_disabled_rounded,
                title: 'Gagal memuat antrian',
                message: readableError(error),
              ),
              data: (ticket) {
                if (ticket == null) {
                  return const EmptyState(
                    icon: Icons.hourglass_empty_rounded,
                    title: 'Kamu belum memiliki antrian aktif',
                    message:
                        'Cari usaha yang sedang open, lalu ambil nomor antrian online.',
                  );
                }
                return Column(
                  children: [
                    ActiveQueueCard(ticket: ticket),
                    const SizedBox(height: 28),
                    InfoCallout(
                      icon: Icons.info_outline_rounded,
                      text:
                          'Mohon tiba di lokasi 10 menit sebelum nomor Anda dipanggil untuk menghindari pembatalan otomatis.',
                    ),
                    const SizedBox(height: 28),
                    DangerButton(
                      label: 'Batalkan Antrian',
                      loading: action.isLoading,
                      onPressed: () async {
                        await ref
                            .read(appActionProvider.notifier)
                            .cancelQueue(ticket.id);
                        if (!context.mounted) return;
                        final error = ref.read(appActionProvider).error;
                        if (error != null) {
                          showError(context, readableError(error));
                        } else {
                          showSnack(context, 'Antrian dibatalkan.');
                        }
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class QueueHistoryScreen extends ConsumerWidget {
  const QueueHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(queueHistoryProvider);
    return AppPage(
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(queueHistoryProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
          children: [
            const HeaderBar(title: 'History'),
            const SizedBox(height: 28),
            history.when(
              loading: () => const LoadingList(),
              error: (error, stackTrace) => EmptyState(
                icon: Icons.history_toggle_off_rounded,
                title: 'Riwayat belum bisa dimuat',
                message: readableError(error),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Belum ada riwayat',
                    message:
                        'Antrian selesai, batal, atau missed akan muncul di sini.',
                  );
                }
                return Column(
                  children: [
                    for (final ticket in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: AppCard(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            children: [
                              QueueNumberBox(number: ticket.queueNumber),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      ticket.business?.name ?? 'Usaha',
                                      style: context.text.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(formatDate(ticket.createdAt)),
                                  ],
                                ),
                              ),
                              StatusBadge(
                                label: titleCase(ticket.status),
                                color: queueStatusColor(ticket.status),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, required this.profile});

  final AppProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myBusiness = ref.watch(myBusinessProvider);
    final action = ref.watch(appActionProvider);
    final hasAdmin = ref.watch(hasAdminProvider);
    return AppPage(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
        children: [
          const HeaderBar(title: 'Profile'),
          const SizedBox(height: 30),
          AppCard(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.person, color: Colors.white, size: 34),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titleCase(profile.username),
                        style: context.text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        profile.isAdmin
                            ? 'Admin Sistem'
                            : 'Pengguna AntrianQAI',
                        style: context.text.bodyMedium?.copyWith(
                          color: AppColors.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusBadge(
                  label: profile.isAdmin ? 'ADMIN' : 'USER',
                  color: profile.isAdmin ? AppColors.primary : AppColors.teal,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          myBusiness.when(
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => const SizedBox.shrink(),
            data: (business) {
              if (profile.isAdmin) return const SizedBox.shrink();
              if (business == null) {
                return ProfileMenuTile(
                  icon: Icons.storefront_outlined,
                  title: 'Jadi Owner',
                  subtitle: 'Ajukan usaha untuk diverifikasi admin',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const BusinessRegistrationScreen(),
                    ),
                  ),
                );
              }
              return ProfileMenuTile(
                icon: Icons.dashboard_customize_outlined,
                title: 'Dashboard Owner',
                subtitle:
                    '${business.name} • ${titleCase(business.approvalStatus)}',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OwnerDashboardScreen(business: business),
                  ),
                ),
              );
            },
          ),
          ProfileMenuTile(
            icon: Icons.hourglass_bottom_rounded,
            title: 'Antrian Saya',
            subtitle: 'Lihat antrian aktif kamu',
            onTap: () =>
                showSnack(context, 'Buka tab My Queue di navigasi bawah.'),
          ),
          ProfileMenuTile(
            icon: Icons.bug_report_outlined,
            title: 'Lapor Bug',
            subtitle: 'Google Form belum dikonfigurasi',
            onTap: () => showSnack(
              context,
              'URL Google Form belum ada. Tombol siap disambungkan nanti.',
            ),
          ),
          hasAdmin.when(
            data: (exists) {
              if (exists || profile.isAdmin) {
                return const SizedBox.shrink();
              }

              return ProfileMenuTile(
                icon: Icons.admin_panel_settings_outlined,
                title: 'Jadikan Admin Pertama',
                subtitle: 'Hanya berhasil jika belum ada admin di database',
                loading: action.isLoading,
                onTap: () async {
                  await ref
                      .read(appActionProvider.notifier)
                      .claimInitialAdmin();

                  if (!context.mounted) return;

                  final error = ref.read(appActionProvider).error;

                  if (error != null) {
                    showError(context, readableError(error));
                  } else {
                    showSnack(context, 'Akun ini sekarang admin.');
                  }
                },
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          ProfileMenuTile(
            icon: Icons.logout_rounded,
            title: 'Logout',
            subtitle: 'Keluar dari sesi saat ini',
            danger: true,
            onTap: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}

class BusinessRegistrationScreen extends ConsumerStatefulWidget {
  const BusinessRegistrationScreen({super.key});

  @override
  ConsumerState<BusinessRegistrationScreen> createState() =>
      _BusinessRegistrationScreenState();
}

class _BusinessRegistrationScreenState
    extends ConsumerState<BusinessRegistrationScreen> {
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();
  final _logoUrl = TextEditingController();
  final _serviceDuration = TextEditingController(text: '10');
  final _maxDailyQueue = TextEditingController(text: '50');

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _description.dispose();
    _logoUrl.dispose();
    _serviceDuration.dispose();
    _maxDailyQueue.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    await ref
        .read(appActionProvider.notifier)
        .registerBusiness(
          name: _name.text,
          location: _location.text,
          description: _description.text,
          logoUrl: _logoUrl.text.trim().isEmpty ? null : _logoUrl.text.trim(),
          serviceDuration: int.tryParse(_serviceDuration.text) ?? 10,
          maxDailyQueue: int.tryParse(_maxDailyQueue.text) ?? 50,
        );
    if (!mounted) return;
    final error = ref.read(appActionProvider).error;
    if (error != null) {
      showError(context, readableError(error));
    } else {
      Navigator.of(context).pop();
      showSnack(
        context,
        'Pengajuan owner terkirim. Menunggu verifikasi admin.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(appActionProvider);
    return FormPage(
      title: 'Jadi Owner',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _name,
            label: 'Nama Usaha',
            hint: 'Klinik Pratama Sehat',
            icon: Icons.storefront_outlined,
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _logoUrl,
            label: 'Logo URL',
            hint: 'Opsional',
            icon: Icons.image_outlined,
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _location,
            label: 'Lokasi',
            hint: 'Jakarta Selatan',
            icon: Icons.location_on_outlined,
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _description,
            label: 'Deskripsi',
            hint: 'Deskripsikan layanan usaha',
            icon: Icons.description_outlined,
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _serviceDuration,
                  label: 'Estimasi Layanan',
                  hint: '10',
                  icon: Icons.schedule_rounded,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: AppTextField(
                  controller: _maxDailyQueue,
                  label: 'Kuota Harian',
                  hint: '50',
                  icon: Icons.confirmation_number_outlined,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          PrimaryButton(
            label: 'Kirim Pengajuan',
            icon: Icons.arrow_forward_rounded,
            loading: action.isLoading,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

class OwnerDashboardScreen extends ConsumerWidget {
  const OwnerDashboardScreen({super.key, required this.business});

  final Business business;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latestBusiness =
        ref.watch(myBusinessProvider).valueOrNull ?? business;
    final queues = ref.watch(ownerQueuesProvider(latestBusiness.id));
    final action = ref.watch(appActionProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
        child: PrimaryButton(
          label: 'PANGGIL ANTRIAN BERIKUTNYA',
          icon: Icons.record_voice_over_outlined,
          loading: action.isLoading,
          onPressed: () async {
            await ref
                .read(appActionProvider.notifier)
                .nextQueue(latestBusiness.id);
            if (!context.mounted) return;
            final error = ref.read(appActionProvider).error;
            if (error != null) {
              showError(context, readableError(error));
            } else {
              showSnack(context, 'Nomor antrian dinaikkan.');
            }
          },
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myBusinessProvider);
            ref.invalidate(ownerQueuesProvider(latestBusiness.id));
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            children: [
              HeaderBar(
                title: 'QueueFlow',
                leading: const CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primary,
                  child: Icon(
                    Icons.person_outline_rounded,
                    color: Colors.white,
                  ),
                ),
                trailing: IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.notifications_none_rounded),
                ),
              ),
              const SizedBox(height: 24),
              AppCard(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Status Bisnis',
                            style: context.text.titleMedium,
                          ),
                          const SizedBox(height: 10),
                          IconLine(
                            icon: Icons.circle,
                            text: latestBusiness.statusLabel,
                            color: statusColor(latestBusiness.status),
                          ),
                        ],
                      ),
                    ),
                    DropdownButton<String>(
                      value: latestBusiness.status,
                      borderRadius: BorderRadius.circular(18),
                      items: const [
                        DropdownMenuItem(value: 'open', child: Text('Open')),
                        DropdownMenuItem(value: 'break', child: Text('Break')),
                        DropdownMenuItem(
                          value: 'closed',
                          child: Text('Closed'),
                        ),
                      ],
                      onChanged: action.isLoading
                          ? null
                          : (value) {
                              if (value == null) return;
                              ref
                                  .read(appActionProvider.notifier)
                                  .setBusinessStatus(latestBusiness.id, value);
                            },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              queues.when(
                loading: () => const Row(
                  children: [
                    Expanded(
                      child: MetricCard(label: 'Antrian Hari Ini', value: '-'),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: MetricCard(label: 'Sedang Dilayani', value: '-'),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: MetricCard(label: 'Selesai', value: '-'),
                    ),
                  ],
                ),
                error: (error, stackTrace) => EmptyState(
                  icon: Icons.warning_amber_rounded,
                  title: 'Data owner gagal dimuat',
                  message: readableError(error),
                ),
                data: (items) => Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        label: 'Antrian Hari Ini',
                        value: '${items.length}',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MetricCard(
                        label: 'Sedang Dilayani',
                        value: '#${latestBusiness.currentQueueNumber}',
                        highlighted: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: MetricCard(label: 'Selesai', value: '-'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              SectionHeader(
                title: 'Antrian Berikutnya',
                action: 'Edit',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        EditBusinessScreen(business: latestBusiness),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              queues.when(
                loading: () => const LoadingList(),
                error: (error, stackTrace) => const SizedBox.shrink(),
                data: (items) {
                  if (items.isEmpty) {
                    return const EmptyState(
                      icon: Icons.people_outline_rounded,
                      title: 'Belum ada antrian',
                      message:
                          'Antrian masuk akan muncul di daftar berikutnya.',
                    );
                  }
                  return Column(
                    children: [
                      for (final ticket in items.take(5))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: QueuePersonTile(ticket: ticket),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              const EfficiencyCard(),
              const SizedBox(height: 86),
            ],
          ),
        ),
      ),
    );
  }
}

class EditBusinessScreen extends ConsumerStatefulWidget {
  const EditBusinessScreen({super.key, required this.business});

  final Business business;

  @override
  ConsumerState<EditBusinessScreen> createState() => _EditBusinessScreenState();
}

class _EditBusinessScreenState extends ConsumerState<EditBusinessScreen> {
  late final TextEditingController _logoUrl;
  late final TextEditingController _location;
  late final TextEditingController _description;
  late final TextEditingController _serviceDuration;
  late final TextEditingController _maxDailyQueue;

  @override
  void initState() {
    super.initState();
    _logoUrl = TextEditingController(text: widget.business.logoUrl ?? '');
    _location = TextEditingController(text: widget.business.location);
    _description = TextEditingController(text: widget.business.description);
    _serviceDuration = TextEditingController(
      text: '${widget.business.serviceDuration}',
    );
    _maxDailyQueue = TextEditingController(
      text: '${widget.business.maxDailyQueue}',
    );
  }

  @override
  void dispose() {
    _logoUrl.dispose();
    _location.dispose();
    _description.dispose();
    _serviceDuration.dispose();
    _maxDailyQueue.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    await ref
        .read(appActionProvider.notifier)
        .submitBusinessUpdate(widget.business.id, {
          'logo_url': _logoUrl.text.trim(),
          'location': _location.text.trim(),
          'description': _description.text.trim(),
          'service_duration': int.tryParse(_serviceDuration.text) ?? 10,
          'max_daily_queue': int.tryParse(_maxDailyQueue.text) ?? 50,
        });
    if (!mounted) return;
    final error = ref.read(appActionProvider).error;
    if (error != null) {
      showError(context, readableError(error));
    } else {
      Navigator.of(context).pop();
      showSnack(context, 'Request edit dikirim. Menunggu approval admin.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(appActionProvider);
    return FormPage(
      title: 'Edit Data Usaha',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _logoUrl,
            label: 'Logo URL',
            hint: 'https://...',
            icon: Icons.image_outlined,
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _location,
            label: 'Lokasi',
            hint: 'Alamat usaha',
            icon: Icons.location_on_outlined,
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _description,
            label: 'Deskripsi',
            hint: 'Deskripsi usaha',
            icon: Icons.description_outlined,
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _serviceDuration,
                  label: 'Durasi',
                  hint: '10',
                  icon: Icons.schedule_rounded,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: AppTextField(
                  controller: _maxDailyQueue,
                  label: 'Kuota',
                  hint: '50',
                  icon: Icons.confirmation_number_outlined,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          PrimaryButton(
            label: 'Ajukan Perubahan',
            icon: Icons.arrow_forward_rounded,
            loading: action.isLoading,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(adminStatsProvider);
    final pending = ref.watch(pendingBusinessesProvider);
    return AppPage(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(adminStatsProvider);
          ref.invalidate(pendingBusinessesProvider);
          ref.invalidate(pendingUpdateRequestsProvider);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          children: [
            HeaderBar(
              title: 'AntrianQAI Admin',
              trailing: IconButton(
                onPressed: () {},
                icon: const Icon(Icons.notifications_none_rounded),
              ),
            ),
            const SizedBox(height: 26),
            stats.when(
              loading: () => const LoadingList(),
              error: (error, stackTrace) => EmptyState(
                icon: Icons.analytics_outlined,
                title: 'Statistik gagal dimuat',
                message: readableError(error),
              ),
              data: (value) => Column(
                children: [
                  AdminStatCard(
                    label: 'TOTAL PENGGUNA',
                    value: formatCompact(value.users),
                    trend: '+12% Bulan ini',
                    icon: Icons.group_outlined,
                  ),
                  const SizedBox(height: 18),
                  AdminStatCard(
                    label: 'BISNIS AKTIF',
                    value: formatCompact(value.businesses),
                    trend: '+5 Bisnis baru',
                    icon: Icons.storefront_outlined,
                    outlined: true,
                  ),
                  const SizedBox(height: 18),
                  AdminStatCard(
                    label: 'ANTREAN LIVE',
                    value: formatCompact(value.activeQueues),
                    trend: 'Update realtime dari Supabase',
                    icon: Icons.hourglass_bottom_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SectionHeader(
              title: 'Persetujuan Bisnis',
              action: 'Filter',
              onTap: () {},
            ),
            const SizedBox(height: 16),
            pending.when(
              loading: () => const LoadingList(),
              error: (error, stackTrace) => EmptyState(
                icon: Icons.fact_check_outlined,
                title: 'Approval gagal dimuat',
                message: readableError(error),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'Tidak ada bisnis baru',
                    message: 'Pengajuan owner baru akan muncul di sini.',
                  );
                }
                return Column(
                  children: [
                    for (final business in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: AdminBusinessApprovalCard(business: business),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class AdminBusinessScreen extends ConsumerWidget {
  const AdminBusinessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businesses = ref.watch(businessesProvider);
    final updates = ref.watch(pendingUpdateRequestsProvider);
    return AppPage(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(businessesProvider);
          ref.invalidate(pendingUpdateRequestsProvider);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
          children: [
            const HeaderBar(title: 'Monitoring Usaha'),
            const SizedBox(height: 24),
            Text('Approval Edit Usaha', style: context.text.headlineSmall),
            const SizedBox(height: 14),
            updates.when(
              loading: () => const LoadingList(),
              error: (error, stackTrace) => EmptyState(
                icon: Icons.edit_note_rounded,
                title: 'Request edit gagal dimuat',
                message: readableError(error),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.edit_note_rounded,
                    title: 'Belum ada request edit',
                    message:
                        'Perubahan data owner akan menunggu approval di sini.',
                  );
                }
                return Column(
                  children: [
                    for (final request in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: UpdateRequestCard(request: request),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),
            Text('Seluruh Usaha', style: context.text.headlineSmall),
            const SizedBox(height: 14),
            businesses.when(
              loading: () => const LoadingList(),
              error: (error, stackTrace) => EmptyState(
                icon: Icons.storefront_outlined,
                title: 'Bisnis gagal dimuat',
                message: readableError(error),
              ),
              data: (items) => Column(
                children: [
                  for (final business in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: BusinessListTile(business: business, onTap: () {}),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationPreviewScreen extends StatelessWidget {
  const NotificationPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
        children: const [
          HeaderBar(title: 'Sistem Notifikasi'),
          SizedBox(height: 26),
          InfoCallout(
            icon: Icons.notifications_active_outlined,
            text:
                'FCM akan aktif setelah project Firebase Android/iOS ditambahkan. Database sudah menyiapkan fcm_tokens dan notifikasi near_turn.',
          ),
          SizedBox(height: 18),
          AppCard(
            padding: EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.graphic_eq_rounded,
                  color: AppColors.primary,
                  size: 42,
                ),
                SizedBox(height: 14),
                Text(
                  'Custom Notification Sound',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 8),
                Text(
                  'Trigger disiapkan ketika Nomor Saya - Nomor Saat Ini = 1. Integrasi push server-side bisa ditambahkan via Edge Function setelah Firebase key tersedia.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdminBusinessApprovalCard extends ConsumerWidget {
  const AdminBusinessApprovalCard({super.key, required this.business});

  final Business business;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(appActionProvider);
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BusinessAvatar(business: business, size: 74),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      business.name,
                      style: context.text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('Pemilik: ${shortId(business.ownerId)}'),
                    const SizedBox(height: 8),
                    Text(
                      business.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(
                        color: AppColors.ink2,
                      ),
                    ),
                  ],
                ),
              ),
              StatusBadge(label: titleCase(business.status)),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TealButton(
                  label: 'Setujui',
                  loading: action.isLoading,
                  onPressed: () => ref
                      .read(appActionProvider.notifier)
                      .approveBusiness(business.id),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: DangerButton(
                  label: 'Tolak',
                  compact: true,
                  loading: action.isLoading,
                  onPressed: () => ref
                      .read(appActionProvider.notifier)
                      .rejectBusiness(business.id),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class UpdateRequestCard extends ConsumerWidget {
  const UpdateRequestCard({super.key, required this.request});

  final BusinessUpdateRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(appActionProvider);
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            request.businessName,
            style: context.text.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(formatDate(request.createdAt)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final key in request.payload.keys)
                StatusBadge(label: key.replaceAll('_', ' ')),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TealButton(
                  label: 'Approve',
                  loading: action.isLoading,
                  onPressed: () => ref
                      .read(appActionProvider.notifier)
                      .approveUpdate(request.id),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: DangerButton(
                  label: 'Reject',
                  compact: true,
                  loading: action.isLoading,
                  onPressed: () => ref
                      .read(appActionProvider.notifier)
                      .rejectUpdate(request.id),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(child: child),
    );
  }
}

class FormPage extends StatelessWidget {
  const FormPage({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          children: [
            HeaderBar(
              title: title,
              leading: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            const SizedBox(height: 28),
            AppCard(padding: const EdgeInsets.all(22), child: child),
          ],
        ),
      ),
    );
  }
}

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const BrandMark(size: 96),
        const SizedBox(height: 28),
        Text(
          'AntrianQAI',
          style: context.text.displaySmall?.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Predictable, fast, and reliable',
          style: context.text.titleLarge?.copyWith(color: AppColors.ink2),
        ),
      ],
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 52});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.bar_chart_rounded,
          color: Colors.white,
          size: size * 0.46,
        ),
      ),
    );
  }
}

class HeaderBar extends StatelessWidget {
  const HeaderBar({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
  });

  final String title;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          SizedBox(width: 52, child: leading ?? const BrandMark(size: 34)),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: context.text.headlineSmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(width: 52, child: trailing),
        ],
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = Colors.white,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor ?? AppColors.outline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.trailing,
    this.maxLines = 1,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? trailing;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.text.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.ink2,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          obscureText: obscureText,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon),
            suffixIcon: trailing,
          ),
        ),
      ],
    );
  }
}

class SearchBox extends StatelessWidget {
  const SearchBox({super.key, required this.hint, required this.onChanged});

  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [Text(label), if (icon != null) Icon(icon, size: 26)],
              ),
      ),
    );
  }
}

class TealButton extends StatelessWidget {
  const TealButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: FilledButton(
        style: FilledButton.styleFrom(backgroundColor: AppColors.teal),
        onPressed: loading ? null : onPressed,
        child: Text(label),
      ),
    );
  }
}

class DangerButton extends StatelessWidget {
  const DangerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool loading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 54 : 64,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.red,
          side: const BorderSide(color: AppColors.red),
        ),
        onPressed: loading ? null : onPressed,
        icon: const Icon(Icons.cancel_outlined),
        label: Text(label),
      ),
    );
  }
}

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<AppNavItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: GestureDetector(
                    onTap: () => onTap(i),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 68,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: currentIndex == i
                            ? AppColors.primaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(34),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            items[i].icon,
                            color: currentIndex == i
                                ? Colors.white
                                : AppColors.ink2,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            items[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: currentIndex == i
                                  ? Colors.white
                                  : AppColors.ink2,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
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
    );
  }
}

class AppNavItem {
  const AppNavItem(this.icon, this.label);

  final IconData icon;
  final String label;
}

class FilterChipPill extends StatelessWidget {
  const FilterChipPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (icon != null)
              Icon(icon, color: selected ? Colors.white : AppColors.primary),
            Text(
              label,
              style: context.text.titleMedium?.copyWith(
                color: selected ? Colors.white : AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PromoCard extends StatelessWidget {
  const PromoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fastest Queues Nearby',
            style: context.text.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Wait times are currently 15% lower than average in your area.',
            style: context.text.titleMedium?.copyWith(
              color: Colors.white,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onTap,
  });

  final String title;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: context.text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ),
        if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
      ],
    );
  }
}

class BusinessListTile extends StatelessWidget {
  const BusinessListTile({
    super.key,
    required this.business,
    required this.onTap,
  });

  final Business business;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = business.status == 'closed';
    return GestureDetector(
      onTap: onTap,
      child: AppCard(
        padding: const EdgeInsets.all(18),
        color: disabled ? Colors.white.withValues(alpha: 0.78) : Colors.white,
        child: Row(
          children: [
            BusinessAvatar(business: business),
            const SizedBox(width: 16),
            Expanded(
              child: Opacity(
                opacity: disabled ? 0.55 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      business.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    IconLine(
                      icon: Icons.location_on_outlined,
                      text: business.location,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              children: [
                StatusBadge(
                  label: business.statusLabel,
                  color: statusColor(business.status),
                ),
                const SizedBox(height: 8),
                Text(
                  '${business.currentQueueNumber} / ${business.maxDailyQueue}',
                  style: context.text.titleMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'In line',
                  style: context.text.bodySmall?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class BusinessAvatar extends StatelessWidget {
  const BusinessAvatar({super.key, required this.business, this.size = 78});

  final Business business;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = business.logoUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: size,
        height: size,
        color: AppColors.surfaceContainer,
        child: url != null && url.trim().isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFDDEBFF), Color(0xFF607D8B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Icon(
        Icons.storefront_outlined,
        color: Colors.white,
        size: 34,
      ),
    );
  }
}

class BusinessHeroImage extends StatelessWidget {
  const BusinessHeroImage({
    super.key,
    required this.business,
    required this.height,
  });

  final Business business;
  final double height;

  @override
  Widget build(BuildContext context) {
    final url = business.logoUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: height,
        width: double.infinity,
        color: AppColors.surfaceContainer,
        child: url != null && url.trim().isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const _HeroFallback(),
              )
            : const _HeroFallback(),
      ),
    );
  }
}

class _HeroFallback extends StatelessWidget {
  const _HeroFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFEAF4FF), Color(0xFF9DB8C3), Color(0xFF64808C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.local_cafe_outlined, color: Colors.white, size: 74),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.color = AppColors.teal,
    this.dot = false,
  });

  final String label;
  final Color color;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (dot) Icon(Icons.circle, size: 9, color: color),
          Text(
            label,
            style: context.text.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class IconLine extends StatelessWidget {
  const IconLine({
    super.key,
    required this.icon,
    required this.text,
    this.color = AppColors.ink2,
    this.centered = false,
  });

  final IconData icon;
  final String text;
  final Color color;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
    if (centered) return Center(child: row);
    return row;
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.caption,
    this.progress,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final String? caption;
  final double? progress;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final foreground = highlighted ? Colors.white : AppColors.ink;
    return AppCard(
      color: highlighted ? AppColors.primaryContainer : Colors.white,
      borderColor: highlighted ? AppColors.primaryContainer : AppColors.outline,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: foreground),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  label,
                  style: context.text.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: context.text.headlineSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              style: context.text.bodySmall?.copyWith(
                color: highlighted
                    ? Colors.white.withValues(alpha: 0.8)
                    : AppColors.muted,
              ),
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress!.clamp(0, 1),
              minHeight: 7,
              borderRadius: BorderRadius.circular(99),
            ),
          ],
        ],
      ),
    );
  }
}

class FeatureRow extends StatelessWidget {
  const FeatureRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(subtitle, style: context.text.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ActiveQueueCard extends StatelessWidget {
  const ActiveQueueCard({super.key, required this.ticket});

  final QueueTicket ticket;

  @override
  Widget build(BuildContext context) {
    final business = ticket.business;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        business?.name ?? 'Usaha',
                        style: context.text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      IconLine(
                        icon: Icons.location_on_outlined,
                        text: business?.location ?? '-',
                      ),
                    ],
                  ),
                ),
                const StatusBadge(label: 'WAITING', color: AppColors.primary),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: QueueValueBox(
                        label: 'Your Number',
                        value: '${ticket.queueNumber}',
                        highlighted: true,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: QueueValueBox(
                        label: 'Current Now',
                        value: '${ticket.currentNow}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                const QueueProgress(),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: IconLine(
                    icon: Icons.schedule_rounded,
                    text: 'Est. Wait Time\n~${ticket.estimatedMinutes} mins',
                    color: AppColors.ink,
                  ),
                ),
                Container(width: 1, height: 46, color: AppColors.outline),
                Expanded(
                  child: IconLine(
                    icon: Icons.groups_2_outlined,
                    text: 'Remaining\n${ticket.remaining} people ahead',
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class QueueValueBox extends StatelessWidget {
  const QueueValueBox({
    super.key,
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.primary.withValues(alpha: 0.06)
            : AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted
              ? AppColors.primary.withValues(alpha: 0.22)
              : Colors.transparent,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: context.text.titleMedium?.copyWith(
              color: AppColors.ink2,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: context.text.displaySmall?.copyWith(
              color: highlighted ? AppColors.primary : AppColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class QueueProgress extends StatelessWidget {
  const QueueProgress({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const QueueStep(icon: Icons.check_rounded, active: true),
            Expanded(child: Container(height: 3, color: AppColors.primary)),
            const QueueStep(icon: Icons.hourglass_bottom_rounded, active: true),
            Expanded(child: Container(height: 3, color: AppColors.outline)),
            const QueueStep(icon: Icons.person_outline_rounded, active: false),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('CHECK-IN', style: context.text.labelMedium),
            Text(
              'WAITING',
              style: context.text.labelMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text('SERVICE', style: context.text.labelMedium),
          ],
        ),
      ],
    );
  }
}

class QueueStep extends StatelessWidget {
  const QueueStep({super.key, required this.icon, required this.active});

  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 22,
      backgroundColor: active ? AppColors.primary : AppColors.outline,
      child: Icon(icon, color: active ? Colors.white : AppColors.ink2),
    );
  }
}

class InfoCallout extends StatelessWidget {
  const InfoCallout({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.teal.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.teal.withValues(alpha: 0.42)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.teal, size: 30),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              text,
              style: context.text.titleMedium?.copyWith(
                color: AppColors.teal,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class QueueNumberBox extends StatelessWidget {
  const QueueNumberBox({super.key, required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'NO',
            style: context.text.labelMedium?.copyWith(
              color: AppColors.muted,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            '$number',
            style: context.text.headlineSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class QueuePersonTile extends StatelessWidget {
  const QueuePersonTile({super.key, required this.ticket});

  final QueueTicket ticket;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          QueueNumberBox(number: ticket.queueNumber),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pelanggan ${shortId(ticket.userId)}',
                  style: context.text.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text('Menunggu • ${ticket.estimatedMinutes} mnt'),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      ),
    );
  }
}

class EfficiencyCard extends StatelessWidget {
  const EfficiencyCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Efisiensi Hari Ini',
            style: context.text.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Kecepatan layanan rata-rata: 4.5 mnt/orang',
            style: context.text.titleMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 26),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final bar in [0.42, 0.65, 0.98, 0.8, 0.48, 0.58])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: FractionallySizedBox(
                        heightFactor: bar,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: bar == 0.8
                                ? AppColors.primaryContainer
                                : AppColors.teal,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdminStatCard extends StatelessWidget {
  const AdminStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.trend,
    required this.icon,
    this.outlined = false,
  });

  final String label;
  final String value;
  final String trend;
  final IconData icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: outlined ? AppColors.primary : AppColors.outline,
      padding: const EdgeInsets.all(26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: context.text.labelLarge?.copyWith(
                    color: AppColors.ink2,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  value,
                  style: context.text.displaySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                IconLine(
                  icon: Icons.trending_up_rounded,
                  text: trend,
                  color: AppColors.teal,
                ),
              ],
            ),
          ),
          Icon(icon, color: AppColors.primary, size: 34),
        ],
      ),
    );
  }
}

class ProfileMenuTile extends StatelessWidget {
  const ProfileMenuTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
    this.loading = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: loading ? null : onTap,
        child: AppCard(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: (danger ? AppColors.red : AppColors.primary)
                    .withValues(alpha: 0.1),
                child: Icon(
                  icon,
                  color: danger ? AppColors.red : AppColors.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: danger ? AppColors.red : AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: context.text.bodyMedium?.copyWith(
                        color: AppColors.ink2,
                      ),
                    ),
                  ],
                ),
              ),
              loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            child: Icon(icon, color: AppColors.primary, size: 34),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: context.text.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(color: AppColors.ink2),
          ),
        ],
      ),
    );
  }
}

class LoadingList extends StatelessWidget {
  const LoadingList({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              height: 92,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.outline),
              ),
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

class BrandedLoadingScreen extends StatelessWidget {
  const BrandedLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMark(size: 82),
            SizedBox(height: 22),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class ErrorScreen extends StatelessWidget {
  const ErrorScreen({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Ada masalah',
              message: message,
            ),
          ),
        ),
      ),
    );
  }
}

void showQueueSuccessSheet(BuildContext context, Map<String, dynamic> result) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    showDragHandle: true,
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 34,
              backgroundColor: AppColors.primary,
              child: Icon(
                Icons.confirmation_number_outlined,
                color: Colors.white,
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Nomor Antrian',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${result['queue_number']}',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    label: 'Antrian Saat Ini',
                    value: '${result['current_queue_number']}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MetricCard(
                    label: 'Estimasi',
                    value: '${result['estimated_minutes']} mnt',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: 'Lihat Antrian Saya',
              icon: Icons.arrow_forward_rounded,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    },
  );
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

void showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: AppColors.red),
  );
}

String usernameToEmail(String value) {
  final trimmed = value.trim().toLowerCase();
  if (trimmed.contains('@')) return trimmed;
  return '${normalizeUsername(trimmed)}@antrianqai.local';
}

String normalizeUsername(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_.]'), '');
}

DateTime? parseDate(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

String titleCase(String value) {
  if (value.isEmpty) return value;
  return value
      .split(RegExp(r'[_\s-]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
      .join(' ');
}

String readableError(Object error) {
  final text = error.toString();
  return text
      .replaceFirst('Exception: ', '')
      .replaceFirst('AuthException: ', '');
}

String formatDate(DateTime value) {
  return DateFormat('dd MMM yyyy • HH:mm').format(value.toLocal());
}

String formatCompact(int value) {
  if (value >= 1000) {
    final result = value / 1000;
    return '${result.toStringAsFixed(result >= 10 ? 0 : 1)}k';
  }
  return '$value';
}

String shortId(String id) {
  return id.length <= 8 ? id : id.substring(0, 8);
}

Color statusColor(String status) {
  return switch (status) {
    'open' => AppColors.teal,
    'break' => AppColors.orange,
    'closed' => AppColors.red,
    _ => AppColors.primary,
  };
}

Color queueStatusColor(String status) {
  return switch (status) {
    'completed' => AppColors.teal,
    'cancelled' => AppColors.red,
    'missed' => AppColors.orange,
    _ => AppColors.primary,
  };
}

extension ThemeX on BuildContext {
  TextTheme get text => Theme.of(this).textTheme;
}

class AppColors {
  const AppColors._();

  static const primary = Color(0xFF004AC6);
  static const primaryContainer = Color(0xFF2563EB);
  static const teal = Color(0xFF007A70);
  static const orange = Color(0xFFBC4800);
  static const red = Color(0xFFBA1A1A);
  static const background = Color(0xFFFAF8FF);
  static const surfaceContainer = Color(0xFFEDEDF9);
  static const ink = Color(0xFF191B23);
  static const ink2 = Color(0xFF434655);
  static const muted = Color(0xFF8D91A1);
  static const outline = Color(0xFFC3C6D7);
  static const darkCard = Color(0xFF171A22);
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryContainer,
        primary: AppColors.primary,
        secondary: AppColors.teal,
        surface: Colors.white,
        error: AppColors.red,
      ),
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Inter',
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
        fontFamily: 'Inter',
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFCFBFF),
        hintStyle: const TextStyle(color: AppColors.muted),
        prefixIconColor: AppColors.ink2,
        suffixIconColor: AppColors.ink2,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.primary,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
    );
  }
}
