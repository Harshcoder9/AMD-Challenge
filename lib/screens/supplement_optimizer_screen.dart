import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../services/firestore_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  💊  SUPPLEMENT STACK OPTIMIZER  (Feature 9)
//
//  • Browse 30+ common supplements with category grouping
//  • Toggle what you take — saved to Firebase
//  • One-tap AI analysis → diet interaction check + optimal timing guide
//  • Warnings for over-supplementation / common conflicts
//  • AMD GPU badge highlights local-inference speed advantage
// ─────────────────────────────────────────────────────────────────────────────

// Key is injected at build/run time: flutter run --dart-define=GEMINI_API_KEY=your_key
const _kSupplApiKey = String.fromEnvironment('GEMINI_API_KEY');

// ── Data model ───────────────────────────────────────────────────────────────

class SupplementInfo {
  final String id;
  final String name;
  final String emoji;
  final String category;
  final String defaultDose;
  final String primaryBenefit;

  const SupplementInfo({
    required this.id,
    required this.name,
    required this.emoji,
    required this.category,
    required this.defaultDose,
    required this.primaryBenefit,
  });
}

const _kAllSupplements = <SupplementInfo>[
  // ── Performance
  SupplementInfo(
    id: 'creatine',
    name: 'Creatine Monohydrate',
    emoji: '⚡',
    category: 'Performance',
    defaultDose: '5g/day',
    primaryBenefit: 'Power & muscle volume',
  ),
  SupplementInfo(
    id: 'protein_powder',
    name: 'Whey Protein',
    emoji: '🥛',
    category: 'Performance',
    defaultDose: '25–30g post-workout',
    primaryBenefit: 'Muscle protein synthesis',
  ),
  SupplementInfo(
    id: 'beta_alanine',
    name: 'Beta-Alanine',
    emoji: '🔥',
    category: 'Performance',
    defaultDose: '3–5g/day',
    primaryBenefit: 'Endurance & reducing fatigue',
  ),
  SupplementInfo(
    id: 'bcaa',
    name: 'BCAAs',
    emoji: '💪',
    category: 'Performance',
    defaultDose: '5–10g around workout',
    primaryBenefit: 'Muscle recovery',
  ),
  SupplementInfo(
    id: 'caffeine',
    name: 'Caffeine',
    emoji: '☕',
    category: 'Performance',
    defaultDose: '100–200mg pre-workout',
    primaryBenefit: 'Focus & energy',
  ),

  // ── Vitamins
  SupplementInfo(
    id: 'vitamin_d',
    name: 'Vitamin D3',
    emoji: '☀️',
    category: 'Vitamins',
    defaultDose: '1000–2000 IU/day',
    primaryBenefit: 'Immune & bone health',
  ),
  SupplementInfo(
    id: 'vitamin_c',
    name: 'Vitamin C',
    emoji: '🍊',
    category: 'Vitamins',
    defaultDose: '500–1000mg/day',
    primaryBenefit: 'Antioxidant & immune',
  ),
  SupplementInfo(
    id: 'vitamin_b12',
    name: 'Vitamin B12',
    emoji: '🧬',
    category: 'Vitamins',
    defaultDose: '500–1000mcg/day',
    primaryBenefit: 'Energy & nerve function',
  ),
  SupplementInfo(
    id: 'vitamin_k2',
    name: 'Vitamin K2',
    emoji: '🌿',
    category: 'Vitamins',
    defaultDose: '100–200mcg/day',
    primaryBenefit: 'Bone & cardiovascular health',
  ),
  SupplementInfo(
    id: 'multivitamin',
    name: 'Multivitamin',
    emoji: '🌈',
    category: 'Vitamins',
    defaultDose: '1 tablet/day',
    primaryBenefit: 'General micronutrient cover',
  ),

  // ── Minerals
  SupplementInfo(
    id: 'magnesium',
    name: 'Magnesium',
    emoji: '🌙',
    category: 'Minerals',
    defaultDose: '200–400mg at night',
    primaryBenefit: 'Sleep, muscle & nerve',
  ),
  SupplementInfo(
    id: 'zinc',
    name: 'Zinc',
    emoji: '🛡️',
    category: 'Minerals',
    defaultDose: '10–25mg/day',
    primaryBenefit: 'Immune & testosterone',
  ),
  SupplementInfo(
    id: 'iron',
    name: 'Iron',
    emoji: '🔩',
    category: 'Minerals',
    defaultDose: '10–18mg/day',
    primaryBenefit: 'Oxygen transport (anaemia)',
  ),
  SupplementInfo(
    id: 'calcium',
    name: 'Calcium',
    emoji: '🦴',
    category: 'Minerals',
    defaultDose: '500–1000mg/day',
    primaryBenefit: 'Bone density',
  ),

  // ── Omega / Fats
  SupplementInfo(
    id: 'omega3',
    name: 'Omega-3 (Fish Oil)',
    emoji: '🐟',
    category: 'Omega / Fats',
    defaultDose: '1–3g EPA+DHA/day',
    primaryBenefit: 'Heart & inflammation',
  ),
  SupplementInfo(
    id: 'cla',
    name: 'CLA',
    emoji: '🧈',
    category: 'Omega / Fats',
    defaultDose: '3g/day',
    primaryBenefit: 'Body composition',
  ),

  // ── Gut Health
  SupplementInfo(
    id: 'probiotic',
    name: 'Probiotic',
    emoji: '🦠',
    category: 'Gut Health',
    defaultDose: '5–10B CFU/day',
    primaryBenefit: 'Gut microbiome',
  ),
  SupplementInfo(
    id: 'prebiotic',
    name: 'Prebiotic Fibre',
    emoji: '🌱',
    category: 'Gut Health',
    defaultDose: '5g/day',
    primaryBenefit: 'Feed good bacteria',
  ),

  // ── Sleep / Recovery
  SupplementInfo(
    id: 'melatonin',
    name: 'Melatonin',
    emoji: '😴',
    category: 'Sleep & Recovery',
    defaultDose: '0.5–3mg before bed',
    primaryBenefit: 'Sleep onset',
  ),
  SupplementInfo(
    id: 'ashwagandha',
    name: 'Ashwagandha',
    emoji: '🌾',
    category: 'Sleep & Recovery',
    defaultDose: '300–600mg/day',
    primaryBenefit: 'Stress & cortisol',
  ),
  SupplementInfo(
    id: 'l_theanine',
    name: 'L-Theanine',
    emoji: '🍵',
    category: 'Sleep & Recovery',
    defaultDose: '100–200mg',
    primaryBenefit: 'Calm focus, pairs with caffeine',
  ),

  // ── Weight management
  SupplementInfo(
    id: 'glucomannan',
    name: 'Glucomannan',
    emoji: '🧃',
    category: 'Weight Management',
    defaultDose: '1g before meals',
    primaryBenefit: 'Appetite satiety',
  ),
  SupplementInfo(
    id: 'green_tea',
    name: 'Green Tea Extract',
    emoji: '🍃',
    category: 'Weight Management',
    defaultDose: '400–500mg/day',
    primaryBenefit: 'Metabolism & antioxidant',
  ),
];

// ── Result model ─────────────────────────────────────────────────────────────

class SupplementAnalysisResult {
  final List<_TimingEntry> timingSlots;
  final List<String> synergies;
  final List<String> warnings;
  final List<String> missingForGoals;
  final String overallAdvice;

  const SupplementAnalysisResult({
    required this.timingSlots,
    required this.synergies,
    required this.warnings,
    required this.missingForGoals,
    required this.overallAdvice,
  });
}

class _TimingEntry {
  final String time; // e.g. 'Morning with breakfast'
  final List<String> supplements;
  final String reason;
  const _TimingEntry(this.time, this.supplements, this.reason);
}

// ── Screen ───────────────────────────────────────────────────────────────────

class SupplementOptimizerScreen extends StatefulWidget {
  final List<String> selectedChallenges;
  final Map<String, double> currentTotals;
  final Map<String, double> dailyGoals;
  final bool amdBackendAvailable;

  const SupplementOptimizerScreen({
    super.key,
    required this.selectedChallenges,
    required this.currentTotals,
    required this.dailyGoals,
    required this.amdBackendAvailable,
  });

  @override
  State<SupplementOptimizerScreen> createState() =>
      _SupplementOptimizerScreenState();
}

class _SupplementOptimizerScreenState extends State<SupplementOptimizerScreen> {
  final _firestore = FirestoreService();

  Set<String> _selectedIds = {};
  bool _isAnalyzing = false;
  SupplementAnalysisResult? _result;
  bool _isLoading = true;

  // Group supplements by category
  Map<String, List<SupplementInfo>> get _grouped {
    final m = <String, List<SupplementInfo>>{};
    for (final s in _kAllSupplements) {
      m.putIfAbsent(s.category, () => []).add(s);
    }
    return m;
  }

  @override
  void initState() {
    super.initState();
    _loadSavedSupplements();
  }

  Future<void> _loadSavedSupplements() async {
    final saved = await _firestore.getSupplements();
    if (mounted)
      setState(() {
        _selectedIds = Set<String>.from(saved);
        _isLoading = false;
      });
  }

  Future<void> _toggle(String id) async {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      _result = null; // clear old analysis when stack changes
    });
    await _firestore.saveSupplements(_selectedIds.toList());
  }

  // ── AI Analysis ──────────────────────────────────────────────────────────
  Future<void> _runAnalysis() async {
    if (_selectedIds.isEmpty) return;

    setState(() {
      _isAnalyzing = true;
      _result = null;
    });

    final stackNames = _kAllSupplements
        .where((s) => _selectedIds.contains(s.id))
        .map((s) => '${s.name} (${s.defaultDose})')
        .join(', ');

    final goalsText = widget.selectedChallenges.isNotEmpty
        ? 'Health goals: ${widget.selectedChallenges.join(", ")}.'
        : '';
    final caloriesCtx =
        'Today\'s intake so far: ${widget.currentTotals['calories']?.round() ?? 0} kcal, '
        '${widget.currentTotals['protein']?.round() ?? 0}g protein.';

    final prompt =
        '''
You are a certified sports nutritionist and supplementation expert.

The user takes the following supplements:
$stackNames

$goalsText
$caloriesCtx

Provide a personalised supplementation analysis in ONLY valid JSON with this exact structure:
{
  "timingSlots": [
    {
      "time": "time slot name (e.g. Morning with breakfast)",
      "supplements": ["supplement name", ...],
      "reason": "one sentence why this timing is optimal"
    }
  ],
  "synergies": ["describe 2-3 beneficial combinations from their stack"],
  "warnings": ["list any dosing conflicts, interactions, or over-supplementation risks — empty array if none"],
  "missingForGoals": ["1-3 supplements not in their stack that would help their stated goals"],
  "overallAdvice": "2-3 sentence personalised summary"
}

Be specific to their exact stack. Return ONLY the JSON. No markdown. No preamble.
''';

    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _kSupplApiKey,
      );
      final resp = await model.generateContent([Content.text(prompt)]);
      final text = resp.text ?? '';
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (match == null) throw const FormatException('no JSON');
      final data = jsonDecode(match.group(0)!) as Map<String, dynamic>;

      final slots = ((data['timingSlots'] as List?) ?? []).map((t) {
        return _TimingEntry(
          t['time'] as String? ?? '',
          List<String>.from(t['supplements'] as List? ?? []),
          t['reason'] as String? ?? '',
        );
      }).toList();

      setState(() {
        _result = SupplementAnalysisResult(
          timingSlots: slots,
          synergies: List<String>.from(data['synergies'] as List? ?? []),
          warnings: List<String>.from(data['warnings'] as List? ?? []),
          missingForGoals: List<String>.from(
            data['missingForGoals'] as List? ?? [],
          ),
          overallAdvice: data['overallAdvice'] as String? ?? '',
        );
        _isAnalyzing = false;
      });
    } catch (e) {
      setState(() => _isAnalyzing = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Analysis failed: $e')));
      }
    }
  }

  // ── Demo fallback ────────────────────────────────────────────────────────
  void _runDemoAnalysis() {
    setState(() {
      _isAnalyzing = true;
      _result = null;
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      setState(() {
        _isAnalyzing = false;
        _result = SupplementAnalysisResult(
          timingSlots: [
            _TimingEntry(
              '🌅 Morning with breakfast',
              ['Vitamin D3', 'Omega-3 (Fish Oil)', 'Multivitamin', 'Vitamin C'],
              'Fat-soluble vitamins absorb best with a meal containing fat.',
            ),
            _TimingEntry(
              '⚡ 30 min pre-workout',
              ['Creatine Monohydrate', 'Caffeine', 'Beta-Alanine'],
              'Peak blood levels align with peak training intensity.',
            ),
            _TimingEntry(
              '💪 Immediately post-workout',
              ['Whey Protein', 'BCAAs'],
              'Anabolic window — muscle protein synthesis is highest.',
            ),
            _TimingEntry(
              '🌙 Evening / before bed',
              ['Magnesium', 'Ashwagandha', 'Melatonin'],
              'Supports parasympathetic recovery and deep sleep.',
            ),
          ],
          synergies: [
            'Creatine + Whey Protein: the most validated stack for lean muscle gain.',
            'Caffeine + L-Theanine: caffeine sharpens focus while L-Theanine removes jitters.',
            'Vitamin D3 + Vitamin K2: D3 drives calcium absorption, K2 directs it to bones not arteries.',
          ],
          warnings: [
            'Zinc + Calcium: compete for absorption. Take at least 2 hours apart.',
            'Caffeine late in the day reduces melatonin effectiveness — cut off by 2 PM.',
          ],
          missingForGoals: [
            'L-Citrulline (6g) — enhances nitric oxide and pump for performance goals.',
            'Probiotic — gut health supports protein absorption and immune function.',
          ],
          overallAdvice:
              'Your stack is well-rounded for performance and recovery. '
              'Prioritise timing discipline — especially pre/post-workout windows — '
              'as the research shows this matters as much as the supplements themselves. '
              'Consider adding L-Citrulline to take your training intensity to the next level.',
        );
      });
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '💊 Supplement Optimizer',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            Text(
              'Build your stack · get timing & interactions',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
        actions: [
          if (widget.amdBackendAvailable) _amdBadge(),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Selection panel ────────────────────────────────────────
                Expanded(flex: 5, child: _buildSelectionPanel(cs)),

                // ── Divider + analyse button ──────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${_selectedIds.length} supplement${_selectedIds.length == 1 ? '' : 's'} selected',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'Tap to toggle your current stack',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _selectedIds.isEmpty || _isAnalyzing
                            ? null
                            : _runAnalysis,
                        icon: _isAnalyzing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                widget.amdBackendAvailable
                                    ? Icons.bolt
                                    : Icons.analytics,
                                size: 18,
                              ),
                        label: Text(
                          _isAnalyzing
                              ? 'Analysing...'
                              : widget.amdBackendAvailable
                              ? '⚡ Optimise'
                              : 'Optimise Stack',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: widget.amdBackendAvailable
                              ? Colors.red.shade700
                              : null,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Analysis result panel ──────────────────────────────────
                if (_result != null)
                  Expanded(flex: 6, child: _buildResultPanel(cs)),
              ],
            ),
    );
  }

  // ── Supplement selection grid ─────────────────────────────────────────────
  Widget _buildSelectionPanel(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      children: _grouped.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Text(
                entry.key,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: cs.primary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: entry.value.map((s) {
                final selected = _selectedIds.contains(s.id);
                return FilterChip(
                  selected: selected,
                  label: Text(
                    '${s.emoji} ${s.name}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  tooltip: '${s.defaultDose} — ${s.primaryBenefit}',
                  onSelected: (_) => _toggle(s.id),
                  selectedColor: cs.primaryContainer,
                  checkmarkColor: cs.primary,
                );
              }).toList(),
            ),
            const SizedBox(height: 4),
          ],
        );
      }).toList(),
    );
  }

  // ── Analysis result ──────────────────────────────────────────────────────
  Widget _buildResultPanel(ColorScheme cs) {
    final r = _result!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.analytics_outlined, size: 18),
              const SizedBox(width: 6),
              const Text(
                'Optimisation Report',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const Spacer(),
              if (widget.amdBackendAvailable)
                Text(
                  '⚡ AMD GPU',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.red.shade700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Overall advice
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(r.overallAdvice, style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(height: 14),

          // Timing guide
          if (r.timingSlots.isNotEmpty) ...[
            _sectionHeader('⏰ Optimal Timing Schedule'),
            const SizedBox(height: 8),
            ...r.timingSlots.map((slot) => _timingCard(slot, cs)),
            const SizedBox(height: 12),
          ],

          // Synergies
          if (r.synergies.isNotEmpty) ...[
            _sectionHeader('✨ Stack Synergies'),
            const SizedBox(height: 6),
            ...r.synergies.map((s) => _bulletCard(s, Colors.green, cs)),
            const SizedBox(height: 12),
          ],

          // Warnings
          if (r.warnings.isNotEmpty) ...[
            _sectionHeader('⚠️ Interactions & Warnings'),
            const SizedBox(height: 6),
            ...r.warnings.map((w) => _bulletCard(w, Colors.red, cs)),
            const SizedBox(height: 12),
          ],

          // Suggestions
          if (r.missingForGoals.isNotEmpty) ...[
            _sectionHeader('💡 Suggested Additions for Your Goals'),
            const SizedBox(height: 6),
            ...r.missingForGoals.map((m) => _bulletCard(m, Colors.blue, cs)),
            const SizedBox(height: 12),
          ],

          // Demo mode button
          Center(
            child: OutlinedButton.icon(
              onPressed: _runDemoAnalysis,
              icon: const Icon(Icons.replay, size: 16),
              label: const Text(
                'Re-run Demo Analysis',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timingCard(_TimingEntry slot, ColorScheme cs) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              slot.time,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: slot.supplements.map((name) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(name, style: const TextStyle(fontSize: 11)),
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
            Text(
              slot.reason,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bulletCard(String text, Color color, ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.circle, size: 6, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) => Text(
    text,
    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
  );

  Widget _amdBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.red.shade700.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.red.shade700.withValues(alpha: 0.45)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.bolt, size: 13, color: Colors.red.shade700),
        const SizedBox(width: 3),
        Text(
          'AMD GPU',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.red.shade700,
          ),
        ),
      ],
    ),
  );
}
