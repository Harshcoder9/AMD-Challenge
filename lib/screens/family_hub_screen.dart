import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../services/firestore_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Family Nutrition Hub
// ─────────────────────────────────────────────────────────────────────────────

/// A single family-member profile.
class FamilyMember {
  final String id;
  String name;
  int age;
  String role; // 'adult' | 'kid' | 'teen'
  int calorieGoal;
  int proteinGoal;
  List<String> allergies;
  List<String> dietaryRestrictions;

  FamilyMember({
    required this.id,
    required this.name,
    required this.age,
    required this.role,
    required this.calorieGoal,
    required this.proteinGoal,
    required this.allergies,
    required this.dietaryRestrictions,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'age': age,
    'role': role,
    'calorieGoal': calorieGoal,
    'proteinGoal': proteinGoal,
    'allergies': allergies,
    'dietaryRestrictions': dietaryRestrictions,
  };

  factory FamilyMember.fromMap(Map<String, dynamic> m) => FamilyMember(
    id: m['id'] ?? '',
    name: m['name'] ?? '',
    age: m['age'] ?? 0,
    role: m['role'] ?? 'adult',
    calorieGoal: m['calorieGoal'] ?? 2000,
    proteinGoal: m['proteinGoal'] ?? 50,
    allergies: List<String>.from(m['allergies'] ?? []),
    dietaryRestrictions: List<String>.from(m['dietaryRestrictions'] ?? []),
  );

  // Defaults based on role/age
  static FamilyMember defaultForRole(String role, int age) {
    if (role == 'kid') {
      return FamilyMember(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: '',
        age: age,
        role: 'kid',
        calorieGoal: age <= 5 ? 1200 : (age <= 8 ? 1400 : 1600),
        proteinGoal: age <= 5 ? 20 : (age <= 8 ? 25 : 30),
        allergies: [],
        dietaryRestrictions: [],
      );
    } else if (role == 'teen') {
      return FamilyMember(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: '',
        age: age,
        role: 'teen',
        calorieGoal: 2000,
        proteinGoal: 60,
        allergies: [],
        dietaryRestrictions: [],
      );
    } else {
      return FamilyMember(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: '',
        age: age,
        role: 'adult',
        calorieGoal: 2000,
        proteinGoal: 80,
        allergies: [],
        dietaryRestrictions: [],
      );
    }
  }
}

// ── Main Screen ───────────────────────────────────────────────────────────────

class FamilyHubScreen extends StatefulWidget {
  final String apiKey;
  const FamilyHubScreen({super.key, required this.apiKey});

  @override
  State<FamilyHubScreen> createState() => _FamilyHubScreenState();
}

class _FamilyHubScreenState extends State<FamilyHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirestoreService _db = FirestoreService();

  List<FamilyMember> _members = [];
  bool _loadingMembers = true;

  // Shopping list state
  String _shoppingList = '';
  bool _generatingList = false;

  // Kid meals state
  List<Map<String, String>> _kidMeals = [];
  bool _generatingKidMeals = false;
  final TextEditingController _hiddenVeggieController = TextEditingController();
  String _hiddenVeggieResult = '';
  bool _detectingVeggies = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadMembers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _hiddenVeggieController.dispose();
    super.dispose();
  }

  // ── Firestore helpers ─────────────────────────────────────────────────────

  Future<void> _loadMembers() async {
    setState(() => _loadingMembers = true);
    final rawList = await _db.getFamilyMembers();
    final members = rawList.map(FamilyMember.fromMap).toList();
    setState(() {
      _members = members;
      _loadingMembers = false;
    });
    // Also load cached shopping list
    final cached = await _db.getFamilyShoppingList();
    if (cached.isNotEmpty) setState(() => _shoppingList = cached);
  }

  Future<void> _saveMember(FamilyMember m) async {
    await _db.saveFamilyMember(m.toMap());
    await _loadMembers();
  }

  Future<void> _deleteMember(String id) async {
    await _db.deleteFamilyMember(id);
    await _loadMembers();
  }

  // ── AI helpers ────────────────────────────────────────────────────────────

  String _buildFamilyContext() {
    if (_members.isEmpty) return 'No family members added yet.';
    final sb = StringBuffer();
    for (final m in _members) {
      sb.write(
        '- ${m.name} (${m.role}, age ${m.age}): '
        'calories goal ${m.calorieGoal} kcal/day, '
        'protein goal ${m.proteinGoal}g/day',
      );
      if (m.allergies.isNotEmpty)
        sb.write(', allergies: ${m.allergies.join(', ')}');
      if (m.dietaryRestrictions.isNotEmpty)
        sb.write(', restrictions: ${m.dietaryRestrictions.join(', ')}');
      sb.writeln('.');
    }
    return sb.toString();
  }

  Future<void> _generateShoppingList() async {
    if (_members.isEmpty) {
      _showSnack('Add at least one family member first.');
      return;
    }
    setState(() {
      _generatingList = true;
      _shoppingList = '';
    });

    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: widget.apiKey,
      );
      final prompt =
          'You are a family nutrition expert. Based on the following family profiles, '
          'generate ONE optimised weekly grocery shopping list that satisfies every '
          'member\'s nutritional needs, respects all allergies and dietary restrictions, '
          'and minimises waste. Group items under clear categories: '
          'Proteins, Vegetables, Fruits, Grains/Carbs, Dairy/Alternatives, Pantry, Snacks for Kids. '
          'Add a short tip after each item showing which family member benefits most.\n\n'
          'Family profiles:\n${_buildFamilyContext()}\n\n'
          'Format the response clearly with emoji category headers.';

      final response = await model.generateContent([Content.text(prompt)]);
      final result = response.text ?? 'Could not generate list.';

      await _db.saveFamilyShoppingList(result);
      setState(() => _shoppingList = result);
    } catch (e) {
      _showSnack('Error generating list: $e');
    } finally {
      setState(() => _generatingList = false);
    }
  }

  Future<void> _generateKidMeals() async {
    final kids = _members
        .where((m) => m.role == 'kid' || m.role == 'teen')
        .toList();
    if (kids.isEmpty) {
      _showSnack('Add at least one kid/teen member first.');
      return;
    }
    setState(() {
      _generatingKidMeals = true;
      _kidMeals = [];
    });

    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: widget.apiKey,
      );
      final kidContext = kids
          .map(
            (k) =>
                '${k.name} (age ${k.age}, allergies: ${k.allergies.isEmpty ? 'none' : k.allergies.join(', ')})',
          )
          .join('; ');

      final prompt =
          'You are a child nutrition and culinary expert. '
          'Generate 6 fun, kid-friendly meal/snack ideas for these children: $kidContext. '
          'For EACH meal, use this EXACT JSON-like format separated by ---:\n'
          'NAME: <meal name>\n'
          'EMOJI: <1 emoji>\n'
          'DESCRIPTION: <1-sentence fun description for kids>\n'
          'HIDDEN_VEGGIES: <comma-separated list of sneakily added veggies, or "none">\n'
          'NUTRITION: <quick 1-line summary e.g. 320 kcal, 12g protein>\n'
          '---\n'
          'Make meals colourful, fun, and age-appropriate. '
          'Always sneak in at least one vegetable wherever possible.';

      final response = await model.generateContent([Content.text(prompt)]);
      final raw = response.text ?? '';

      // Parse the structured response
      final meals = <Map<String, String>>[];
      for (final block in raw.split('---')) {
        final lines = block.trim().split('\n');
        final meal = <String, String>{};
        for (final line in lines) {
          final colonIdx = line.indexOf(':');
          if (colonIdx == -1) continue;
          final key = line.substring(0, colonIdx).trim().toUpperCase();
          final value = line.substring(colonIdx + 1).trim();
          meal[key] = value;
        }
        if (meal.containsKey('NAME') && meal['NAME']!.isNotEmpty) {
          meals.add(meal);
        }
      }
      setState(() => _kidMeals = meals);
    } catch (e) {
      _showSnack('Error generating kid meals: $e');
    } finally {
      setState(() => _generatingKidMeals = false);
    }
  }

  Future<void> _detectHiddenVeggies() async {
    final dishName = _hiddenVeggieController.text.trim();
    if (dishName.isEmpty) return;
    setState(() {
      _detectingVeggies = true;
      _hiddenVeggieResult = '';
    });
    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: widget.apiKey,
      );
      final prompt =
          'A parent wants to sneak vegetables into the dish: "$dishName". '
          'Suggest 4–5 vegetables that can be hidden in this dish without kids noticing the taste/texture. '
          'For each veggie, explain HOW to hide it (blend, grate, puree, etc.), '
          'what nutritional benefit it adds, and a fun name to call it so kids find it exciting. '
          'Keep your response concise and practical.';
      final response = await model.generateContent([Content.text(prompt)]);
      setState(() => _hiddenVeggieResult = response.text ?? 'No result.');
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      setState(() => _detectingVeggies = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '👨‍👩‍👧 Family Nutrition Hub',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.people), text: 'Members'),
            Tab(icon: Icon(Icons.shopping_cart), text: 'Shopping'),
            Tab(icon: Icon(Icons.child_care), text: 'Kid Meals'),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              heroTag: 'add_member',
              onPressed: _showAddMemberDialog,
              icon: const Icon(Icons.person_add),
              label: const Text('Add Member'),
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMembersTab(cs),
          _buildShoppingTab(cs),
          _buildKidMealsTab(cs),
        ],
      ),
    );
  }

  // ── Tab 1: Family Members ─────────────────────────────────────────────────

  Widget _buildMembersTab(ColorScheme cs) {
    if (_loadingMembers) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_members.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.family_restroom,
              size: 72,
              color: cs.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No family members yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "Add Member" to get started',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _showAddMemberDialog,
              icon: const Icon(Icons.person_add),
              label: const Text('Add First Member'),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Summary row
        _buildFamilySummaryBanner(cs),
        const SizedBox(height: 12),
        ...(_members.map((m) => _buildMemberCard(m, cs))),
      ],
    );
  }

  Widget _buildFamilySummaryBanner(ColorScheme cs) {
    final totalCalories = _members.fold<int>(0, (s, m) => s + m.calorieGoal);
    final kids = _members.where((m) => m.role == 'kid').length;
    final teens = _members.where((m) => m.role == 'teen').length;
    final adults = _members.where((m) => m.role == 'adult').length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.secondaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Family of ${_members.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (adults > 0) '$adults adult${adults > 1 ? 's' : ''}',
                    if (teens > 0) '$teens teen${teens > 1 ? 's' : ''}',
                    if (kids > 0) '$kids kid${kids > 1 ? 's' : ''}',
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$totalCalories kcal/day',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              Text(
                'combined daily goal',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMemberCard(FamilyMember m, ColorScheme cs) {
    final roleColor = m.role == 'kid'
        ? Colors.orange
        : m.role == 'teen'
        ? Colors.purple
        : cs.primary;
    final roleEmoji = m.role == 'kid'
        ? '🧒'
        : m.role == 'teen'
        ? '🧑'
        : '👤';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: roleColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: roleColor.withValues(alpha: 0.4),
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  m.name.isNotEmpty ? m.name[0].toUpperCase() : roleEmoji,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: roleColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        m.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: roleColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${roleEmoji} ${m.role[0].toUpperCase()}${m.role.substring(1)} · age ${m.age}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: roleColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      _miniStat('🔥', '${m.calorieGoal} kcal'),
                      const SizedBox(width: 10),
                      _miniStat('💪', '${m.proteinGoal}g protein'),
                    ],
                  ),
                  if (m.allergies.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 13,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'Allergies: ${m.allergies.join(', ')}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (m.dietaryRestrictions.isNotEmpty)
                    Text(
                      'Diet: ${m.dietaryRestrictions.join(', ')}',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
            ),
            // Actions
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Edit',
                  onPressed: () => _showEditMemberDialog(m),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Colors.red,
                  ),
                  tooltip: 'Remove',
                  onPressed: () => _confirmDelete(m),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String emoji, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 3),
        Text(text, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  // ── Tab 2: Shopping List ──────────────────────────────────────────────────

  Widget _buildShoppingTab(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('🛒', style: TextStyle(fontSize: 28)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'AI Smart Shopping List',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Optimised for all ${_members.length} family member${_members.length == 1 ? '' : 's'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _generatingList ? null : _generateShoppingList,
                  icon: _generatingList
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(
                    _generatingList
                        ? 'Generating...'
                        : 'Generate Smart Shopping List',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_shoppingList.isNotEmpty) ...[
            Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 16,
                  color: Colors.green,
                ),
                const SizedBox(width: 6),
                Text(
                  'Your family shopping list',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('Copy', style: TextStyle(fontSize: 12)),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _shoppingList));
                    _showSnack('Shopping list copied to clipboard!');
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cs.outline.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: SelectableText(
                _shoppingList,
                style: const TextStyle(fontSize: 13.5, height: 1.6),
              ),
            ),
          ] else if (!_generatingList)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Column(
                  children: [
                    Icon(
                      Icons.shopping_bag_outlined,
                      size: 64,
                      color: cs.onSurface.withValues(alpha: 0.25),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No shopping list yet',
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Add family members then tap\n"Generate Smart Shopping List"',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Tab 3: Kid Meals ──────────────────────────────────────────────────────

  Widget _buildKidMealsTab(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Kid meal generator card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.orange.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text('🍽️', style: TextStyle(fontSize: 26)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Kid-Friendly Meal Ideas',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            'Fun meals with hidden veggies!',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                  ),
                  onPressed: _generatingKidMeals ? null : _generateKidMeals,
                  icon: _generatingKidMeals
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.restaurant_menu),
                  label: Text(
                    _generatingKidMeals
                        ? 'Thinking of meals...'
                        : 'Generate Kid Meal Ideas',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Kid meal cards
          if (_kidMeals.isNotEmpty) ...[
            Text(
              '🌟 Meal Ideas',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._kidMeals.map((meal) => _buildKidMealCard(meal, cs)),
            const SizedBox(height: 20),
          ],

          // Hidden Veggie Detector
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.green.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text('🥦', style: TextStyle(fontSize: 26)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hidden Veggie Detector',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            'Enter any dish — find how to sneak in veggies!',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _hiddenVeggieController,
                        decoration: const InputDecoration(
                          hintText: 'e.g. mac and cheese, pasta, pancakes...',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _detectHiddenVeggies(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                      ),
                      onPressed: _detectingVeggies
                          ? null
                          : _detectHiddenVeggies,
                      child: _detectingVeggies
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.search),
                    ),
                  ],
                ),
                if (_hiddenVeggieResult.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  SelectableText(
                    _hiddenVeggieResult,
                    style: const TextStyle(fontSize: 13, height: 1.55),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKidMealCard(Map<String, String> meal, ColorScheme cs) {
    final hasHiddenVeggies =
        (meal['HIDDEN_VEGGIES'] ?? 'none').toLowerCase() != 'none' &&
        (meal['HIDDEN_VEGGIES'] ?? '').isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  meal['EMOJI'] ?? '🍽️',
                  style: const TextStyle(fontSize: 28),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meal['NAME'] ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      if ((meal['NUTRITION'] ?? '').isNotEmpty)
                        Text(
                          meal['NUTRITION']!,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if ((meal['DESCRIPTION'] ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(meal['DESCRIPTION']!, style: const TextStyle(fontSize: 13)),
            ],
            if (hasHiddenVeggies) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.visibility_off,
                      size: 14,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Hidden Veggie: ${meal['HIDDEN_VEGGIES']}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _showAddMemberDialog() {
    _showMemberDialog(null);
  }

  void _showEditMemberDialog(FamilyMember existing) {
    _showMemberDialog(existing);
  }

  void _showMemberDialog(FamilyMember? existing) {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: isEdit ? existing.name : '');
    final ageCtrl = TextEditingController(
      text: isEdit ? existing.age.toString() : '',
    );
    final calorieCtrl = TextEditingController(
      text: isEdit ? existing.calorieGoal.toString() : '',
    );
    final proteinCtrl = TextEditingController(
      text: isEdit ? existing.proteinGoal.toString() : '',
    );
    final allergiesCtrl = TextEditingController(
      text: isEdit ? existing.allergies.join(', ') : '',
    );
    final dietCtrl = TextEditingController(
      text: isEdit ? existing.dietaryRestrictions.join(', ') : '',
    );
    String selectedRole = isEdit ? existing.role : 'adult';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEdit ? '✏️ Edit Member' : '👤 Add Family Member'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ageCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Age *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.cake),
                        ),
                        onChanged: (v) {
                          final age = int.tryParse(v);
                          if (age != null && !isEdit) {
                            // Auto-suggest role
                            setDialogState(() {
                              if (age < 13)
                                selectedRole = 'kid';
                              else if (age < 18)
                                selectedRole = 'teen';
                              else
                                selectedRole = 'adult';
                              // Auto fill calorie/protein defaults
                              final def = FamilyMember.defaultForRole(
                                selectedRole,
                                age,
                              );
                              calorieCtrl.text = def.calorieGoal.toString();
                              proteinCtrl.text = def.proteinGoal.toString();
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Role picker
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(ctx).colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedRole,
                          items: const [
                            DropdownMenuItem(
                              value: 'kid',
                              child: Text('🧒 Kid'),
                            ),
                            DropdownMenuItem(
                              value: 'teen',
                              child: Text('🧑 Teen'),
                            ),
                            DropdownMenuItem(
                              value: 'adult',
                              child: Text('👤 Adult'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null)
                              setDialogState(() {
                                selectedRole = v;
                                final age = int.tryParse(ageCtrl.text) ?? 25;
                                final def = FamilyMember.defaultForRole(v, age);
                                calorieCtrl.text = def.calorieGoal.toString();
                                proteinCtrl.text = def.proteinGoal.toString();
                              });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: calorieCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '🔥 Calorie goal',
                          border: OutlineInputBorder(),
                          suffixText: 'kcal',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: proteinCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '💪 Protein goal',
                          border: OutlineInputBorder(),
                          suffixText: 'g',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: allergiesCtrl,
                  decoration: const InputDecoration(
                    labelText: '⚠️ Allergies (comma separated)',
                    hintText: 'e.g. nuts, dairy, gluten',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dietCtrl,
                  decoration: const InputDecoration(
                    labelText: '🥗 Dietary restrictions (comma separated)',
                    hintText: 'e.g. vegetarian, halal, low-sugar',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final age = int.tryParse(ageCtrl.text) ?? 0;
                if (name.isEmpty || age == 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Name and age are required')),
                  );
                  return;
                }
                final member = FamilyMember(
                  id: isEdit
                      ? existing.id
                      : DateTime.now().millisecondsSinceEpoch.toString(),
                  name: name,
                  age: age,
                  role: selectedRole,
                  calorieGoal: int.tryParse(calorieCtrl.text) ?? 2000,
                  proteinGoal: int.tryParse(proteinCtrl.text) ?? 50,
                  allergies: allergiesCtrl.text
                      .split(',')
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toList(),
                  dietaryRestrictions: dietCtrl.text
                      .split(',')
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toList(),
                );
                Navigator.pop(ctx);
                await _saveMember(member);
              },
              child: Text(isEdit ? 'Save' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(FamilyMember m) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove ${m.name} from your family hub?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteMember(m.id);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}
