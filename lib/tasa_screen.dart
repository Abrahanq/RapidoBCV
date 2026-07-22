// ============================================================================
// tasa_screen.dart — Rediseño "Tasa." de RápidoBCV
// ============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'rates_service.dart';

// ============================================================================
// Design tokens
// ============================================================================

class _AccentPreset {
  final String name;
  final Color base;
  final Color deep;
  const _AccentPreset(this.name, this.base, this.deep);
}

const List<_AccentPreset> _kPresets = [
  _AccentPreset('Azul BCV', Color(0xFF2F6FED), Color(0xFF1D4ED8)),
  _AccentPreset('Esmeralda', Color(0xFF10B981), Color(0xFF059669)),
  _AccentPreset('Violeta', Color(0xFF7C5CFF), Color(0xFF6320C9)),
  _AccentPreset('Coral', Color(0xFFF97316), Color(0xFFEA580C)),
  _AccentPreset('Magenta', Color(0xFFEC4899), Color(0xFFDB2777)),
  _AccentPreset('Turquesa', Color(0xFF06B6D4), Color(0xFF0891B2)),
];

Color _darken(Color c, double f) => Color.fromARGB(
  (c.a * 255).round(),
  ((c.r * 255) * (1 - f)).round().clamp(0, 255),
  ((c.g * 255) * (1 - f)).round().clamp(0, 255),
  ((c.b * 255) * (1 - f)).round().clamp(0, 255),
);

bool _sameRgb(Color a, Color b) =>
    (a.r * 255).round() == (b.r * 255).round() &&
    (a.g * 255).round() == (b.g * 255).round() &&
    (a.b * 255).round() == (b.b * 255).round();

class _TC {
  final Color screen, text, dim, card, border, toggleBg;
  final Color ghostBorder, ghostText;
  final Color dateTrack, dateActive, dateActiveText;
  final BoxShadow? dateActiveShadow;
  final Color input, inputText, item, heroNum;
  final BoxShadow? cardShadow;
  final Color up, accent, accentDeep, accentText;
  final bool isDark;

  const _TC({
    required this.screen,
    required this.text,
    required this.dim,
    required this.card,
    required this.border,
    required this.toggleBg,
    required this.ghostBorder,
    required this.ghostText,
    required this.dateTrack,
    required this.dateActive,
    required this.dateActiveText,
    this.dateActiveShadow,
    required this.input,
    required this.inputText,
    required this.item,
    required this.heroNum,
    this.cardShadow,
    required this.up,
    required this.accent,
    required this.accentDeep,
    required this.accentText,
    required this.isDark,
  });
}

_TC _colors(bool isDark, Color accent, Color accentDeep) {
  if (isDark) {
    return _TC(
      screen: const Color(0xFF0A0E12),
      text: const Color(0xFFEEF2F6),
      dim: const Color(0xFF8A94A6),
      card: const Color(0xFF111820),
      border: const Color(0xFF1B232C),
      toggleBg: const Color(0xFF141B22),
      ghostBorder: const Color(0xFF26313D),
      ghostText: const Color(0xFFCDD6E0),
      dateTrack: const Color(0xFF111820),
      dateActive: const Color(0xFF1C2530),
      dateActiveText: Colors.white,
      dateActiveShadow: null,
      input: const Color(0xFF0D141B),
      inputText: const Color(0xFFEEF2F6),
      item: const Color(0xFF131B23),
      heroNum: Colors.white,
      cardShadow: null,
      up: const Color(0xFF34D399),
      accent: accent,
      accentDeep: accentDeep,
      accentText: accent,
      isDark: true,
    );
  }
  return _TC(
    screen: const Color(0xFFF4F7F9),
    text: const Color(0xFF0F1720),
    dim: const Color(0xFF7C8698),
    card: Colors.white,
    border: const Color(0xFFE6EBEF),
    toggleBg: const Color(0xFFE9EDF1),
    ghostBorder: const Color(0xFFD5DCE3),
    ghostText: const Color(0xFF3A4553),
    dateTrack: const Color(0xFFE9EDF1),
    dateActive: Colors.white,
    dateActiveText: const Color(0xFF0F1720),
    dateActiveShadow: const BoxShadow(
      color: Color(0x14000000),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
    input: const Color(0xFFF4F7F9),
    inputText: const Color(0xFF0F1720),
    item: const Color(0xFFF6F8FA),
    heroNum: const Color(0xFF0F1720),
    cardShadow: const BoxShadow(
      color: Color(0x47142830),
      blurRadius: 34,
      spreadRadius: -22,
      offset: Offset(0, 14),
    ),
    up: const Color(0xFF059669),
    accent: accent,
    accentDeep: accentDeep,
    accentText: accentDeep,
    isDark: false,
  );
}

// ============================================================================
// Calculator item
// ============================================================================

class _CalcItem {
  final bool isUsd;
  final double usd;
  final double bs;
  const _CalcItem({required this.isUsd, required this.usd, required this.bs});
}

// ============================================================================
// TasaScreen
// ============================================================================

class TasaScreen extends StatefulWidget {
  final ValueChanged<bool> onToggleTheme;
  final VoidCallback onToggleUI;
  const TasaScreen({
    super.key,
    required this.onToggleTheme,
    required this.onToggleUI,
  });

  @override
  State<TasaScreen> createState() => _TasaScreenState();
}

class _TasaScreenState extends State<TasaScreen> {
  final _service = RatesService();

  // — Accent —
  Color _accent = const Color(0xFF2F6FED);
  Color _accentDeep = const Color(0xFF1D4ED8);
  static const String _accentKey = 'accent_color';

  // — Rate state —
  bool _isUpdatingText = false;
  DateTime? _usdtLastUpdatedAt;
  double? _usdtBuyRate;
  double? _usdtSellRate;
  UsdtRateMode _usdtRateMode = UsdtRateMode.buyAverage;
  bool _isLoadingUsdtQuote = false;

  List<ExchangeRates> _rateOptions = [];
  int _selectedRateIndex = 0;
  ExchangeRates? _rates;
  bool _isLoading = true;
  String? _error;

  // — Conversor —
  bool _convSrcIsTop = true;
  final TextEditingController _topCtrl = TextEditingController();
  final TextEditingController _botCtrl = TextEditingController();
  String _fromCurrency = 'USD';

  // — Calculator —
  final TextEditingController _calcUsdCtrl = TextEditingController();
  final TextEditingController _calcBsCtrl = TextEditingController();
  final List<_CalcItem> _items = [];

  // — Screenshot —
  final ScreenshotController _screenshotCtrl = ScreenshotController();

  // — Tutorial (first launch) —
  static const String _tutorialSeenKey = 'tutorial_seen_v1';
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _tutorialToggleKey = GlobalKey();
  final GlobalKey _tutorialColorKey = GlobalKey();
  bool _showTutorial = false;
  int _tutorialStep = 0;
  Rect? _spotlightRect;

  // ══════════════════════════════════════════════════════════════════════════
  // Lifecycle
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    unawaited(_init());
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartTutorial());
  }

  Future<void> _init() async {
    await _loadAccent();
    await _loadRatesInitial();
  }

  @override
  void dispose() {
    _topCtrl.dispose();
    _botCtrl.dispose();
    _calcUsdCtrl.dispose();
    _calcBsCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Tutorial (first launch)
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _maybeStartTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getBool(_tutorialSeenKey) ?? false) || !mounted) return;
    await _showTutorialStep(0);
  }

  Future<void> _showTutorialStep(int step) async {
    if (!mounted) return;
    setState(() {
      _showTutorial = true;
      _tutorialStep = step;
      _spotlightRect = null;
    });
    final key = step == 0 ? _tutorialToggleKey : _tutorialColorKey;
    final ctx = key.currentContext;
    if (ctx != null && step != 0) {
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.35,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
    _measureSpotlightWhenReady(key);
  }

  // Measures the target after layout, retrying across frames until the
  // measured rect is identical on two consecutive frames. A render box can
  // report `hasSize` before its parent (e.g. an Align) has settled into its
  // final offset, so a single successful read isn't enough to trust the
  // position — only agreement across frames is.
  void _measureSpotlightWhenReady(
    GlobalKey key, [
    int attempt = 0,
    Rect? previous,
  ]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showTutorial) return;
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      final rect = (box != null && box.hasSize && box.size.width > 0)
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      final stable = rect != null && rect == previous;
      if (stable || attempt >= 10) {
        if (rect != null) {
          setState(() {
            _spotlightRect = rect;
          });
        }
      } else {
        _measureSpotlightWhenReady(key, attempt + 1, rect);
      }
    });
  }

  void _nextTutorialStep() {
    if (_tutorialStep == 0) {
      unawaited(_showTutorialStep(1));
    } else {
      _finishTutorial();
    }
  }

  Future<void> _finishTutorial() async {
    setState(() {
      _showTutorial = false;
      _spotlightRect = null;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tutorialSeenKey, true);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Accent
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _loadAccent() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getInt(_accentKey);
    if (val != null && mounted) {
      final c = Color(val);
      setState(() {
        _accent = c;
        _accentDeep = _darken(c, 0.18);
      });
    }
  }

  void _setAccent(Color c) {
    setState(() {
      _accent = c;
      _accentDeep = _darken(c, 0.18);
    });
    SharedPreferences.getInstance().then(
      (p) => p.setInt(_accentKey, c.toARGB32()),
    );
  }

  void _openColorPicker() {
    Color temp = _accent;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Color personalizado'),
        content: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (ctx, setLocal) => ColorPicker(
              pickerColor: temp,
              onColorChanged: (c) => setLocal(() => temp = c),
              pickerAreaHeightPercent: 0.8,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              _setAccent(temp);
              Navigator.pop(context);
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // API / Rate logic
  // ══════════════════════════════════════════════════════════════════════════

  void _applyUsdtQuote(UsdtBinanceQuote q) {
    _usdtBuyRate = q.buyToVes;
    _usdtSellRate = q.sellToVes;
    _usdtLastUpdatedAt = q.updatedAt;
  }

  Future<void> _loadRatesInitial() async {
    final cached = await _service.readCachedRates();
    if (!mounted) return;
    if (cached != null) {
      setState(() {
        _rates = cached;
        _rateOptions = [cached];
        _selectedRateIndex = 0;
        _isLoading = false;
      });
      unawaited(_service.updateHomeWidget(cached, _usdtLastUpdatedAt));
    }
    await _fetchRates(showLoading: cached == null);
  }

  Future<void> _fetchRates({bool showLoading = true}) async {
    try {
      if (showLoading && mounted) {
        setState(() {
          _isLoading = true;
          _error = null;
        });
      }
      final fetched = await _service.fetchPrices();
      final idx = _service.initialIndex(fetched);
      await _service.cacheRates(fetched[idx]);
      if (!mounted) return;
      setState(() {
        _rateOptions = fetched;
        _selectedRateIndex = idx;
        _rates = fetched[idx];
        _isLoading = false;
        _error = null;
      });
      unawaited(
        _service.updateHomeWidget(
          _service.rateForWidget(fetched),
          _usdtLastUpdatedAt,
        ),
      );
      _recalculate();
    } on TimeoutException {
      await _handleFetchError('Tiempo de espera agotado.');
    } on http.ClientException {
      await _handleFetchError('Sin conexión o error de red.');
    } on FormatException {
      await _handleFetchError('Respuesta inválida.');
    } catch (_) {
      await _handleFetchError('No se pudieron obtener las tasas.');
    }
  }

  Future<void> _onRefresh() async {
    await _fetchRates(showLoading: false);
    if (_fromCurrency == 'USDT') {
      await _loadUsdtForView(force: true);
    }
  }

  Future<void> _handleFetchError(String msg) async {
    final cached = await _service.readCachedRates();
    if (!mounted) return;
    final fallback =
        cached ??
        ExchangeRates(
          usdToVes: 0,
          eurToVes: 0,
          usdtToVes: 0,
          lastUpdate: DateTime.now(),
        );
    setState(() {
      _error = cached != null ? '$msg Mostrando última tasa guardada.' : msg;
      _isLoading = false;
      _rates = fallback;
      _rateOptions = [fallback];
      _selectedRateIndex = 0;
    });
    if (cached != null) {
      unawaited(_service.updateHomeWidget(cached, _usdtLastUpdatedAt));
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Conversor logic
  // ══════════════════════════════════════════════════════════════════════════

  double _rateInVes(String currency) {
    if (_rates == null || currency == 'VES') return 1;
    if (currency == 'USD') return _rates!.usdToVes;
    if (currency == 'EUR') return _rates!.eurToVes;
    if (currency == 'USDT') {
      if (_usdtBuyRate != null && _usdtSellRate != null) {
        return _usdtRateMode == UsdtRateMode.buyAverage
            ? _usdtBuyRate!
            : _usdtSellRate!;
      }
      return _rates!.usdtToVes;
    }
    return 1;
  }

  double? _parse(String s, {required bool isVes}) {
    var n = s.trim().replaceAll(' ', '');
    if (n.isEmpty) return null;
    if (isVes) {
      if (n.contains(',')) {
        n = n.replaceAll('.', '').replaceAll(',', '.');
      } else if ('.'.allMatches(n).length > 1) {
        n = n.replaceAll('.', '');
      }
    } else {
      if (n.contains(',') && n.contains('.')) {
        n = n.replaceAll('.', '').replaceAll(',', '.');
      } else {
        n = n.replaceAll(',', '.');
      }
    }
    return double.tryParse(n);
  }

  void _setCtrl(TextEditingController ctrl, String v) {
    _isUpdatingText = true;
    ctrl.text = v;
    ctrl.selection = TextSelection.collapsed(offset: v.length);
    _isUpdatingText = false;
  }

  void _recalculate() {
    if (_isUpdatingText) return;
    if (_convSrcIsTop) {
      _updateBottom();
    } else {
      _updateTop();
    }
  }

  void _updateBottom() {
    if (_rates == null) {
      _setCtrl(_botCtrl, '');
      return;
    }
    final input = _topCtrl.text.trim();
    if (input.isEmpty) {
      _setCtrl(_botCtrl, '');
      return;
    }
    final amount = _parse(input, isVes: false);
    if (amount == null) {
      _setCtrl(_botCtrl, '');
      return;
    }
    _setCtrl(_botCtrl, _fmtVes(amount * _rateInVes(_fromCurrency)));
  }

  void _updateTop() {
    if (_rates == null) {
      _setCtrl(_topCtrl, '');
      return;
    }
    final input = _botCtrl.text.trim();
    if (input.isEmpty) {
      _setCtrl(_topCtrl, '');
      return;
    }
    final amount = _parse(input, isVes: true);
    if (amount == null) {
      _setCtrl(_topCtrl, '');
      return;
    }
    final rate = _rateInVes(_fromCurrency);
    _setCtrl(_topCtrl, rate > 0 ? (amount / rate).toStringAsFixed(2) : '');
  }

  void _selectCurrency(String currency) {
    setState(() {
      _fromCurrency = currency;
    });
    if (currency == 'USDT') unawaited(_loadUsdtForView());
    _recalculate();
  }

  void _changeUsdtMode(UsdtRateMode mode) {
    if (_usdtRateMode == mode) return;
    setState(() {
      _usdtRateMode = mode;
    });
    _recalculate();
  }

  Future<void> _copyField(TextEditingController ctrl, String currency) async {
    final monto = ctrl.text.trim();
    if (monto.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay monto para copiar.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: monto));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Monto copiado: $monto $currency')));
  }

  void _clearConv() {
    _setCtrl(_topCtrl, '');
    _setCtrl(_botCtrl, '');
  }

  Future<void> _loadUsdtForView({bool force = false}) async {
    if (_isLoadingUsdtQuote) return;
    if (!force && _usdtBuyRate != null && _usdtSellRate != null) return;
    final fallback = _rates?.usdtToVes ?? _rates?.usdToVes ?? 0;
    setState(() {
      _isLoadingUsdtQuote = true;
    });
    try {
      final q = force
          ? await _service.fetchUsdtFromBinance()
          : await _service.fetchUsdtQuoteWithCache(fallback);
      if (!mounted) return;
      setState(() {
        _applyUsdtQuote(q);
        _isLoadingUsdtQuote = false;
      });
      _recalculate();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingUsdtQuote = false;
      });
    }
  }

  void _selectRate(int index) {
    if (index < 0 || index >= _rateOptions.length) return;
    setState(() {
      _selectedRateIndex = index;
      _rates = _rateOptions[index];
    });
    _recalculate();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Calculator logic
  // ══════════════════════════════════════════════════════════════════════════

  void _addUsd() {
    final x = _parse(_calcUsdCtrl.text, isVes: false);
    if (x == null || x <= 0) return;
    setState(() {
      _items.add(
        _CalcItem(isUsd: true, usd: x, bs: x * (_rates?.usdToVes ?? 0)),
      );
      _calcUsdCtrl.clear();
    });
  }

  void _addBs() {
    final y = _parse(_calcBsCtrl.text, isVes: true);
    if (y == null || y <= 0) return;
    final rate = _rates?.usdToVes ?? 0;
    setState(() {
      _items.add(_CalcItem(isUsd: false, usd: rate > 0 ? y / rate : 0, bs: y));
      _calcBsCtrl.clear();
    });
  }

  void _removeItem(int i) => setState(() => _items.removeAt(i));
  void _clearAll() => setState(() => _items.clear());

  double get _totalUsd => _items.fold(0, (s, it) => s + it.usd);
  double get _totalBs => _items.fold(0, (s, it) => s + it.bs);

  // ══════════════════════════════════════════════════════════════════════════
  // Share
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _share() async {
    final topText = _topCtrl.text.trim();
    final botText = _botCtrl.text.trim();
    final ratio = (MediaQuery.of(context).devicePixelRatio * 2).clamp(2.0, 4.0);
    try {
      final bytes = await _screenshotCtrl.capture(
        pixelRatio: ratio,
        delay: const Duration(milliseconds: 80),
      );
      if (bytes == null || bytes.isEmpty) return;
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/rapidobcv_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text:
              'Monto en $_fromCurrency: ${topText.isEmpty ? '-' : topText}\n'
              'Monto en VES: ${botText.isEmpty ? '-' : botText}',
          subject: 'RápidoBCV',
        ),
      );
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Formatting helpers
  // ══════════════════════════════════════════════════════════════════════════

  String _addThousands(String n) {
    final neg = n.startsWith('-');
    final digits = neg ? n.substring(1) : n;
    final chars = digits.split('').reversed.toList();
    final out = <String>[];
    for (var i = 0; i < chars.length; i++) {
      out.add(chars[i]);
      if ((i + 1) % 3 == 0 && i + 1 < chars.length) out.add('.');
    }
    final f = out.reversed.join();
    return neg ? '-$f' : f;
  }

  String _fmtVes(double v) {
    final fixed = v.toStringAsFixed(2);
    final parts = fixed.split('.');
    return '${_addThousands(parts[0])},${parts.length > 1 ? parts[1] : '00'}';
  }

  String _shortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  double get _currentRate {
    if (_rates == null) return 0;
    return _rateInVes(_fromCurrency);
  }

  double? _rateChange() {
    if (_fromCurrency == 'USDT') return null;
    if (_rateOptions.length < 2) return null;
    final first = _fromCurrency == 'EUR'
        ? _rateOptions.first.eurToVes
        : _rateOptions.first.usdToVes;
    final last = _fromCurrency == 'EUR'
        ? _rateOptions.last.eurToVes
        : _rateOptions.last.usdToVes;
    if (first == 0) return null;
    return (last - first) / first * 100;
  }

  String? get _trendText {
    final change = _rateChange();
    if (change == null) return null;
    return '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%';
  }

  bool get _trendUp => (_rateChange() ?? 0) >= 0;

  String _heroLabel() {
    switch (_fromCurrency) {
      case 'EUR':
        return 'Euro oficial · BCV';
      case 'USDT':
        return 'USDT · Binance P2P';
      default:
        return 'Dólar oficial · BCV';
    }
  }

  String _currencySymbol(String c) {
    switch (c) {
      case 'EUR':
        return '€';
      case 'USDT':
        return '₮';
      default:
        return r'$';
    }
  }

  String _dateLabel(int idx) {
    if (_rateOptions.isEmpty) return '';
    if (_rateOptions.length == 2) {
      return '${idx == 0 ? 'Ayer' : 'Hoy'} ${_shortDate(_rateOptions[idx].lastUpdate)}';
    }
    return _shortDate(_rateOptions[idx].lastUpdate);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Build
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = _colors(isDark, _accent, _accentDeep);

    return Scaffold(
      backgroundColor: c.screen,
      body: Stack(
        children: [
          SafeArea(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              color: c.accent,
              backgroundColor: c.card,
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Screenshot(
                      controller: _screenshotCtrl,
                      child: ColoredBox(
                        color: c.screen,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildHeader(c, isDark),
                            _buildCurrencyCards(c),
                            _buildHero(c),
                            if (_fromCurrency == 'USDT' &&
                                _usdtBuyRate != null &&
                                _usdtSellRate != null)
                              _buildUsdtModeSelector(c)
                            else if (_rateOptions.length >= 2)
                              _buildDateSelector(c),
                            _buildConversor(c),
                            _buildActions(c),
                          ],
                        ),
                      ),
                    ),
                    _buildCalculator(c, isDark),
                    _buildColorPicker(c),
                    const SizedBox(height: 26),
                  ],
                ),
              ),
            ),
          ),
          if (_showTutorial) _buildTutorialOverlay(c),
        ],
      ),
    );
  }

  // ─── Tutorial overlay ─────────────────────────────────────────────────────

  Widget _buildTutorialOverlay(_TC c) {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rect = _spotlightRect;

    final String title;
    final String body;
    if (_tutorialStep == 0) {
      title = 'Cambia de vista';
      body =
          'Toca este botón para alternar entre la vista nueva y la vista clásica cuando quieras.';
    } else {
      title = 'Color de la app';
      body =
          'Aquí abajo puedes elegir el color de acento y personalizar la app a tu gusto.';
    }

    // Place the card on the opposite side of the spotlight so it never overlaps.
    final bool cardBelow = rect == null || rect.center.dy < size.height / 2;
    final double topInset = MediaQuery.of(context).padding.top;
    // Keep the card clear of the highlighted element (and of the status bar /
    // header when the spotlight is near the top of the screen).
    double? cardTop;
    double? cardBottom;
    if (cardBelow) {
      final double desired = rect == null
          ? size.height * 0.28
          : rect.bottom + 28;
      final double minTop = topInset + 96;
      cardTop = desired < minTop ? minTop : desired;
    } else {
      cardBottom = size.height - rect.top + 28;
    }

    Widget card = Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1D22) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.accentText.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF14161A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: isDark ? Colors.white70 : const Color(0xFF4A4F57),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                'Paso ${_tutorialStep + 1} de 2',
                style: TextStyle(fontSize: 12, color: c.dim),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _finishTutorial,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Text(
                    'Saltar',
                    style: TextStyle(fontSize: 14, color: c.dim),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _nextTutorialStep,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: c.accentText,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _tutorialStep == 0 ? 'Siguiente' : '¡Entendido!',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return Positioned.fill(
      child: GestureDetector(
        onTap: _nextTutorialStep,
        child: Stack(
          children: [
            // Dimmed backdrop with a cut-out spotlight around the target.
            Positioned.fill(
              child: CustomPaint(
                painter: _SpotlightPainter(
                  hole: rect,
                  scrim: Colors.black.withValues(alpha: 0.72),
                  borderColor: c.accentText,
                ),
              ),
            ),
            // Info card, kept clear of the spotlight.
            Positioned(
              left: 0,
              right: 0,
              top: cardTop,
              bottom: cardBottom,
              child: card,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(_TC c, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 4),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.center,
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'Rápido',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: c.text,
                      letterSpacing: -0.5,
                    ),
                  ),
                  TextSpan(
                    text: 'BCV',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: c.accentText,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: widget.onToggleUI,
                  child: Container(
                    key: _tutorialToggleKey,
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.toggleBg,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(Icons.swap_horiz, color: c.dim, size: 18),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => widget.onToggleTheme(isDark),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.toggleBg,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      isDark
                          ? Icons.wb_sunny_outlined
                          : Icons.dark_mode_outlined,
                      color: c.dim,
                      size: 18,
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

  // ─── Currency cards ───────────────────────────────────────────────────────

  Widget _buildCurrencyCards(_TC c) {
    final usdRate = _rates != null ? _fmtVes(_rates!.usdToVes) : '---';
    final eurRate = _rates != null ? _fmtVes(_rates!.eurToVes) : '---';
    final usdtRate = _rates != null ? _fmtVes(_rateInVes('USDT')) : '---';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          _CurrencyCard(
            currency: 'USD',
            rate: usdRate,
            isSelected: _fromCurrency == 'USD',
            onTap: () => _selectCurrency('USD'),
            accent: _accent,
            accentDeep: _accentDeep,
            c: c,
          ),
          const SizedBox(width: 8),
          _CurrencyCard(
            currency: 'EUR',
            rate: eurRate,
            isSelected: _fromCurrency == 'EUR',
            onTap: () => _selectCurrency('EUR'),
            accent: _accent,
            accentDeep: _accentDeep,
            c: c,
          ),
          const SizedBox(width: 8),
          _CurrencyCard(
            currency: 'USDT',
            rate: usdtRate,
            isSelected: _fromCurrency == 'USDT',
            onTap: () => _selectCurrency('USDT'),
            accent: _accent,
            accentDeep: _accentDeep,
            c: c,
          ),
        ],
      ),
    );
  }

  // ─── Hero ─────────────────────────────────────────────────────────────────

  Widget _buildHero(_TC c) {
    final rateStr = _isLoading && _rates == null
        ? '---'
        : _fmtVes(_currentRate);
    final trend = _trendText;
    final isUp = _trendUp;
    final downColor = c.isDark
        ? const Color(0xFFFC6868)
        : const Color(0xFFDC2626);
    final trendColor = isUp ? c.up : downColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _heroLabel().toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: c.accentText,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                rateStr,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 58,
                  fontWeight: FontWeight.w700,
                  color: c.heroNum,
                  letterSpacing: -2,
                  height: 0.9,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Bs',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: c.accentText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (trend != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: trendColor.withValues(alpha: c.isDark ? 0.14 : 0.13),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isUp ? Icons.trending_up : Icons.trending_down,
                        size: 12,
                        color: trendColor,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        trend,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: trendColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                _rates != null
                    ? 'actualizado ${_fmtTime(_rates!.lastUpdate)} · ${_shortDate(_rates!.lastUpdate)}'
                    : _isLoading
                    ? 'actualizando…'
                    : 'sin conexión',
                style: TextStyle(fontSize: 13, color: c.dim),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 11, color: Colors.orange),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Date selector ────────────────────────────────────────────────────────

  Widget _buildDateSelector(_TC c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: c.dateTrack,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: List.generate(_rateOptions.length, (i) {
            final isActive = _selectedRateIndex == i;
            final shadow = isActive && c.dateActiveShadow != null
                ? [c.dateActiveShadow!]
                : null;
            return Expanded(
              child: GestureDetector(
                onTap: () => _selectRate(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isActive ? c.dateActive : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: shadow,
                  ),
                  child: Text(
                    _dateLabel(i),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                      color: isActive ? c.dateActiveText : c.dim,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ─── USDT mode selector ───────────────────────────────────────────────────

  Widget _buildUsdtModeSelector(_TC c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: c.dateTrack,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            _buildUsdtTab(c, UsdtRateMode.buyAverage, 'Venta', _usdtBuyRate!),
            _buildUsdtTab(
              c,
              UsdtRateMode.sellAverage,
              'Compra',
              _usdtSellRate!,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsdtTab(_TC c, UsdtRateMode mode, String label, double rate) {
    final isActive = _usdtRateMode == mode;
    final shadow = isActive && c.dateActiveShadow != null
        ? [c.dateActiveShadow!]
        : null;
    return Expanded(
      child: GestureDetector(
        onTap: () => _changeUsdtMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isActive ? c.dateActive : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: shadow,
          ),
          child: Column(
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isActive ? c.dateActiveText : c.dim,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                _fmtVes(rate),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                  color: isActive ? c.dateActiveText : c.dim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Conversor card ───────────────────────────────────────────────────────

  Widget _fieldIconBtn(IconData icon, VoidCallback onTap, _TC c) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Icon(icon, size: 20, color: c.dim),
      ),
    );
  }

  Widget _buildConversor(_TC c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(20),
          boxShadow: c.cardShadow != null ? [c.cardShadow!] : null,
        ),
        child: Stack(
          children: [
            // Fields
            Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [
                  // Top: currency
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'TENGO · $_fromCurrency',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                  color: c.dim,
                                ),
                              ),
                            ),
                            _fieldIconBtn(
                              Icons.copy_rounded,
                              () => _copyField(_topCtrl, _fromCurrency),
                              c,
                            ),
                            const SizedBox(width: 2),
                            _fieldIconBtn(Icons.clear, _clearConv, c),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              _currencySymbol(_fromCurrency),
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: c.dim,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: _topCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  color: c.heroNum,
                                ),
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                  hintText: '0,00',
                                  hintStyle: GoogleFonts.spaceGrotesk(
                                    color: c.dim,
                                    fontSize: 26,
                                  ),
                                ),
                                onChanged: (_) {
                                  if (!_isUpdatingText) {
                                    setState(() {
                                      _convSrcIsTop = true;
                                    });
                                    _updateBottom();
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Divider
                  Container(
                    height: 1,
                    color: c.border,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  // Bottom: Bs
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'RECIBO · VES',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                  color: c.dim,
                                ),
                              ),
                            ),
                            _fieldIconBtn(
                              Icons.copy_rounded,
                              () => _copyField(_botCtrl, 'VES'),
                              c,
                            ),
                            const SizedBox(width: 2),
                            _fieldIconBtn(Icons.clear, _clearConv, c),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              'Bs',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: c.dim,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: _botCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  color: c.accentText,
                                ),
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                  hintText: '0,00',
                                  hintStyle: GoogleFonts.spaceGrotesk(
                                    color: c.dim,
                                    fontSize: 26,
                                  ),
                                ),
                                onChanged: (_) {
                                  if (!_isUpdatingText) {
                                    setState(() {
                                      _convSrcIsTop = false;
                                    });
                                    _updateTop();
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
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

  // ─── Actions ──────────────────────────────────────────────────────────────

  Widget _buildActions(_TC c) {
    final softStrong = _accent.withValues(alpha: 0.6);
    final btnShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    final btnHeight = const Size.fromHeight(48);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _fetchRates(),
              icon: Icon(Icons.refresh, size: 15, color: c.ghostText),
              label: Text('Actualizar', style: TextStyle(color: c.ghostText)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: c.ghostBorder),
                minimumSize: btnHeight,
                shape: btnShape,
                textStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.share, size: 15),
              label: const Text('Compartir'),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                minimumSize: btnHeight,
                shape: btnShape,
                shadowColor: softStrong,
                elevation: 8,
                textStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Calculator ───────────────────────────────────────────────────────────

  Widget _buildCalculator(_TC c, bool isDark) {
    final softStrong = _accent.withValues(alpha: 0.6);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(22),
          boxShadow: c.cardShadow != null ? [c.cardShadow!] : null,
        ),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Calculadora de compras',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: c.text,
                  ),
                ),
                if (_items.isNotEmpty)
                  TextButton.icon(
                    onPressed: _clearAll,
                    icon: Icon(Icons.delete_outline, size: 13, color: c.dim),
                    label: Text(
                      'Limpiar',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: c.dim,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Summary gradient card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_accent, _accentDeep],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: softStrong,
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                    spreadRadius: -12,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EQUIVALENTE TOTAL',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _fmtVes(_totalBs),
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Bs',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(
                    color: Colors.white.withValues(alpha: 0.2),
                    thickness: 1,
                    height: 1,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Acumulado',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      Text(
                        '\$ ${_fmtVes(_totalUsd)}',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Tasa usada (BCV USD)',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      Text(
                        '${_fmtVes(_rates?.usdToVes ?? 0)} Bs',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // USD input row
            _CalcInputRow(
              controller: _calcUsdCtrl,
              prefix: r'$',
              hint: 'Monto en USD',
              onSubmit: _addUsd,
              buttonLabel: 'USD',
              buttonBg: _accent,
              buttonFg: Colors.white,
              buttonElevation: 0,
              inputBg: c.input,
              inputBorder: c.border,
              inputTextColor: c.inputText,
              dimColor: c.dim,
            ),
            const SizedBox(height: 8),

            // Bs input row
            _CalcInputRow(
              controller: _calcBsCtrl,
              prefix: 'Bs',
              prefixStyle: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
              hint: 'Monto en Bs',
              onSubmit: _addBs,
              buttonLabel: 'Bs',
              buttonBg: _accent,
              buttonFg: Colors.white,
              // buttonBg: _accent.withValues(alpha: isDark ? 0.18 : 0.12),
              // buttonFg: c.accentText,
              buttonElevation: 0,
              inputBg: c.input,
              inputBorder: c.border,
              inputTextColor: c.inputText,
              dimColor: c.dim,
            ),
            const SizedBox(height: 14),

            // Items list or empty state
            if (_items.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Column(
                  children: [
                    Text(
                      'Aún no hay montos agregados.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: c.dim),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Suma compras y ve el total acumulado.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: c.dim.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: _items.asMap().entries.map((entry) {
                  final i = entry.key;
                  final it = entry.value;
                  final badgeBg = it.isUsd
                      ? _accent.withValues(alpha: isDark ? 0.22 : 0.14)
                      : (isDark
                            ? const Color(0xFF1C2530)
                            : const Color(0xFFEEF1F4));
                  final badgeText = it.isUsd ? c.accentText : c.dim;
                  final main = it.isUsd
                      ? '\$ ${_fmtVes(it.usd)}'
                      : '${_fmtVes(it.bs)} Bs';
                  final sub = it.isUsd
                      ? '${_fmtVes(it.bs)} Bs'
                      : '\$ ${_fmtVes(it.usd)}';

                  return Container(
                    margin: EdgeInsets.only(
                      bottom: i < _items.length - 1 ? 8 : 0,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: c.item,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              it.isUsd ? r'$' : 'Bs',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: badgeText,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                main,
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: c.text,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                '≈ $sub',
                                style: TextStyle(fontSize: 12, color: c.dim),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _removeItem(i),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(Icons.close, size: 15, color: c.dim),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Color picker ─────────────────────────────────────────────────────────

  Widget _buildColorPicker(_TC c) {
    final isCustom = !_kPresets.any((p) => _sameRgb(p.base, _accent));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        key: _tutorialColorKey,
        decoration: BoxDecoration(
          color: c.card,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(22),
          boxShadow: c.cardShadow != null ? [c.cardShadow!] : null,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Color de la app',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: c.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Elige el acento; se aplica a toda la interfaz.',
              style: TextStyle(fontSize: 12, color: c.dim),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ..._kPresets.map((p) {
                  final selected = _sameRgb(p.base, _accent);
                  return GestureDetector(
                    onTap: () => _setAccent(p.base),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: p.base,
                        shape: BoxShape.circle,
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: c.screen,
                                  blurRadius: 0,
                                  spreadRadius: 2,
                                ),
                                BoxShadow(
                                  color: p.base,
                                  blurRadius: 0,
                                  spreadRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  );
                }),
                // Custom rainbow swatch
                GestureDetector(
                  onTap: _openColorPicker,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const SweepGradient(
                        colors: [
                          Color(0xFFF97316),
                          Color(0xFFEC4899),
                          Color(0xFF7C5CFF),
                          Color(0xFF2F6FED),
                          Color(0xFF06B6D4),
                          Color(0xFF10B981),
                          Color(0xFFF97316),
                        ],
                      ),
                      boxShadow: isCustom
                          ? [
                              BoxShadow(
                                color: c.screen,
                                blurRadius: 0,
                                spreadRadius: 2,
                              ),
                              BoxShadow(
                                color: _accent,
                                blurRadius: 0,
                                spreadRadius: 4,
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: c.card,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '+',
                            style: TextStyle(
                              color: c.text,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
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

// ============================================================================
// Currency card (sub-widget)
// ============================================================================

class _CurrencyCard extends StatelessWidget {
  final String currency;
  final String rate;
  final bool isSelected;
  final VoidCallback onTap;
  final Color accent;
  final Color accentDeep;
  final _TC c;

  const _CurrencyCard({
    required this.currency,
    required this.rate,
    required this.isSelected,
    required this.onTap,
    required this.accent,
    required this.accentDeep,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    final softStrong = accent.withValues(alpha: 0.6);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [accent, accentDeep],
                    transform: GradientRotation(160 * math.pi / 180),
                  )
                : null,
            color: isSelected ? null : c.card,
            border: isSelected ? null : Border.all(color: c.border),
            borderRadius: BorderRadius.circular(16),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: softStrong,
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                      spreadRadius: -8,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currency,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.85)
                      : c.dim,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                rate,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? Colors.white : c.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Calculator input row (sub-widget)
// ============================================================================

class _CalcInputRow extends StatelessWidget {
  final TextEditingController controller;
  final String prefix;
  final TextStyle? prefixStyle;
  final String hint;
  final VoidCallback onSubmit;
  final String buttonLabel;
  final Color buttonBg;
  final Color buttonFg;
  final double buttonElevation;
  final Color inputBg;
  final Color inputBorder;
  final Color inputTextColor;
  final Color dimColor;

  const _CalcInputRow({
    required this.controller,
    required this.prefix,
    this.prefixStyle,
    required this.hint,
    required this.onSubmit,
    required this.buttonLabel,
    required this.buttonBg,
    required this.buttonFg,
    required this.buttonElevation,
    required this.inputBg,
    required this.inputBorder,
    required this.inputTextColor,
    required this.dimColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: inputBg,
              border: Border.all(color: inputBorder),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                Text(
                  prefix,
                  style:
                      prefixStyle ??
                      GoogleFonts.spaceGrotesk(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: dimColor,
                      ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: inputTextColor,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: hint,
                      hintStyle: TextStyle(color: dimColor, fontSize: 15),
                    ),
                    onSubmitted: (_) => onSubmit(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: onSubmit,
            icon: Icon(Icons.add, size: 15, color: buttonFg),
            label: Text(buttonLabel, style: TextStyle(color: buttonFg)),
            style: ElevatedButton.styleFrom(
              backgroundColor: buttonBg,
              shadowColor: Colors.transparent,
              elevation: buttonElevation,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
              textStyle: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 15),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Tutorial spotlight painter ────────────────────────────────────────────────
class _SpotlightPainter extends CustomPainter {
  final Rect? hole;
  final Color scrim;
  final Color borderColor;
  const _SpotlightPainter({
    required this.hole,
    required this.scrim,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = scrim;
    final full = Path()..addRect(Offset.zero & size);
    if (hole == null) {
      canvas.drawPath(full, paint);
      return;
    }
    final inflated = hole!.inflate(8);
    final rrect = RRect.fromRectAndRadius(inflated, const Radius.circular(16));
    final holePath = Path()..addRRect(rrect);
    final scrimPath = Path.combine(PathOperation.difference, full, holePath);
    canvas.drawPath(scrimPath, paint);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) =>
      old.hole != hole || old.scrim != scrim || old.borderColor != borderColor;
}
