import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const String _themeIsDarkKey = 'theme_is_dark';
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    unawaited(_loadThemeMode());
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool(_themeIsDarkKey);
    if (!mounted || isDark == null) return;

    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  Future<void> _toggleTheme(bool isCurrentlyDark) async {
    final nextMode =
        isCurrentlyDark ? ThemeMode.light : ThemeMode.dark;

    setState(() {
      _themeMode = nextMode;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themeIsDarkKey, nextMode == ThemeMode.dark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RapidoBCV - Conversor de Divisas',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      home: ConversorPage(
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

// Modelo para las tasas de cambio
class ExchangeRates {
  final double usdToVes;
  final double eurToVes;
  final double usdtToVes;
  final DateTime lastUpdate;

  ExchangeRates({
    required this.usdToVes,
    required this.eurToVes,
    required this.usdtToVes,
    required this.lastUpdate,
  });
}

class UsdtBinanceQuote {
  final double buyToVes;
  final double sellToVes;
  final DateTime updatedAt;

  const UsdtBinanceQuote({
    required this.buyToVes,
    required this.sellToVes,
    required this.updatedAt,
  });

  double get averageToVes => (buyToVes + sellToVes) / 2;
}

enum UsdtRateMode {
  buyAverage,
  sellAverage,
}

class ConversorPage extends StatefulWidget {
  final ValueChanged<bool> onToggleTheme;

  const ConversorPage({
    super.key,
    required this.onToggleTheme,
  });

  @override
  State<ConversorPage> createState() => _ConversorPageState();
}

class _ConversorPageState extends State<ConversorPage> {
  static const String _ratesCacheKey = 'exchange_rates_cache';
  static const String _usdtRateCacheKey = 'usdt_rate_cache';
  static const String _usdtBuyRateCacheKey = 'usdt_buy_rate_cache';
  static const String _usdtSellRateCacheKey = 'usdt_sell_rate_cache';
  static const String _usdtRateUpdatedAtCacheKey = 'usdt_rate_updated_at_cache';
  static const String _usdtQuoteCacheVersionKey = 'usdt_quote_cache_version';
  static const int _usdtQuoteCacheVersion = 2;
  static const String _binanceP2pEndpoint =
      'https://p2p.binance.com/bapi/c2c/v2/friendly/c2c/adv/search';
  bool _isUpdatingText = false;
  DateTime? _usdtLastUpdatedAt;
  DateTime? _usdtQuoteUpdatedAt;
  double? _usdtBuyRate;
  double? _usdtSellRate;
  UsdtRateMode _usdtRateMode = UsdtRateMode.buyAverage;
  String? _usdtQuoteError;
  bool _isLoadingUsdtQuote = false;
  final ScreenshotController _screenshotController = ScreenshotController();

  List<ExchangeRates> rateOptions = [];
  List<String> _rateLabelsCache = const [];
  String? _acquisitionTextCache;
  int selectedRateIndex = 0;
  ExchangeRates? rates;
  bool isLoading = true;
  String? error;
  
  // Controllers para las conversiones
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _calculatorUsdController = TextEditingController();
  final TextEditingController _calculatorVesController = TextEditingController();

  final List<_CalculatorEntry> _calculatorEntries = <_CalculatorEntry>[];
  
  String fromCurrency = 'USD';

  @override
  void initState() {
    super.initState();
    unawaited(_cargarInicialRapido());
  }

  Future<void> _cargarInicialRapido() async {
    final cachedRates = await _leerTasasDesdeCache();

    if (!mounted) return;

    if (cachedRates != null) {
      setState(() {
        rates = cachedRates;
        rateOptions = [cachedRates];
        selectedRateIndex = 0;
        isLoading = false;
        error = null;
        _actualizarTextosDerivados();
      });
      unawaited(_actualizarHomeWidget(cachedRates));
    }

    await obtenerTasasActuales(mostrarCarga: cachedRates == null);
  }

  double? _toDoubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.'));
    }
    return null;
  }

  Future<List<ExchangeRates>> obtenerPrecios() async {
    final uri = Uri.parse(
      'https://abrahanq.github.io/bcv-price/prices.json',
    ).replace(
      queryParameters: {
        'v': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );

    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: no se pudo cargar precios');
    }

    final Map<String, dynamic> data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    final List<Map<String, dynamic>> bcvRecords = [];
    final precios = data['precios'];

    if (precios is List && precios.isNotEmpty) {
      for (final item in precios) {
        if (item is! Map) continue;
        final precioData = item.cast<String, dynamic>();
        final usd = _toDoubleOrNull(precioData['usd']);
        final eur = _toDoubleOrNull(precioData['eur']);
        if (usd == null || eur == null) continue;

        final dateRaw = precioData['date'] ?? precioData['fecha'];
        DateTime parsedDate;
        try {
          parsedDate = DateTime.parse(dateRaw as String);
        } catch (_) {
          parsedDate = DateTime.now();
        }

        bcvRecords.add({
          'usd': usd,
          'eur': eur,
          'usdt': _toDoubleOrNull(precioData['usdt']),
          'date': parsedDate,
        });
      }
    } else {
      final usd = _toDoubleOrNull(data['usd']);
      final eur = _toDoubleOrNull(data['eur']);
      if (usd != null && eur != null) {
        final dateRaw = data['date'] ?? data['fecha'];
        DateTime parsedDate;
        try {
          parsedDate = DateTime.parse(dateRaw as String);
        } catch (_) {
          parsedDate = DateTime.now();
        }

        bcvRecords.add({
          'usd': usd,
          'eur': eur,
          'usdt': _toDoubleOrNull(data['usdt']),
          'date': parsedDate,
        });
      }
    }

    final List<ExchangeRates> parsedRates = [];
    if (bcvRecords.isNotEmpty) {
      final fallbackUsd = (bcvRecords.last['usd'] as double?) ?? 0;
      final hasMissingUsdt = bcvRecords.any((record) => record['usdt'] == null);
      final fallbackUsdt =
          hasMissingUsdt
              ? await _obtenerUsdtConCacheHorario(fallbackUsd)
              : fallbackUsd;

      for (final record in bcvRecords) {
        parsedRates.add(
          ExchangeRates(
            usdToVes: record['usd'] as double,
            eurToVes: record['eur'] as double,
            usdtToVes: (record['usdt'] as double?) ?? fallbackUsdt,
            lastUpdate: record['date'] as DateTime,
          ),
        );
      }
    }

    if (parsedRates.isEmpty) {
      throw const FormatException('No se encontraron tasas válidas en la respuesta');
    }

    parsedRates.sort((a, b) => a.lastUpdate.compareTo(b.lastUpdate));
    return parsedRates;
  }

  Future<double> _obtenerUsdtConCacheHorario(double fallbackUsd) async {
    final quote = await _obtenerCotizacionUsdtConCacheHorario(fallbackUsd);
    _actualizarCotizacionUsdtEnMemoria(quote);
    return quote.averageToVes;
  }

  void _actualizarCotizacionUsdtEnMemoria(UsdtBinanceQuote quote) {
    _usdtBuyRate = quote.buyToVes;
    _usdtSellRate = quote.sellToVes;
    _usdtQuoteUpdatedAt = quote.updatedAt;
    _usdtLastUpdatedAt = quote.updatedAt;
  }

  Future<UsdtBinanceQuote> _obtenerCotizacionUsdtConCacheHorario(
    double fallbackRate,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedUsdt = prefs.getDouble(_usdtRateCacheKey);
    final cachedBuy = prefs.getDouble(_usdtBuyRateCacheKey);
    final cachedSell = prefs.getDouble(_usdtSellRateCacheKey);
    final cachedVersion = prefs.getInt(_usdtQuoteCacheVersionKey) ?? 1;
    final cachedUpdatedAt = prefs.getString(_usdtRateUpdatedAtCacheKey);

    if (cachedBuy != null && cachedSell != null && cachedUpdatedAt != null) {
      try {
        final updatedAt = DateTime.parse(cachedUpdatedAt);
        final age = DateTime.now().difference(updatedAt);
        if (age < const Duration(hours: 1)) {
          final buyValue =
              cachedVersion >= _usdtQuoteCacheVersion ? cachedBuy : cachedSell;
          final sellValue =
              cachedVersion >= _usdtQuoteCacheVersion ? cachedSell : cachedBuy;
          return UsdtBinanceQuote(
            buyToVes: buyValue,
            sellToVes: sellValue,
            updatedAt: updatedAt,
          );
        }
      } catch (_) {}
    }

    try {
      final freshQuote = await _obtenerCotizacionUsdtBinance();
      final now = DateTime.now();
      await prefs.setDouble(_usdtRateCacheKey, freshQuote.averageToVes);
      await prefs.setDouble(_usdtBuyRateCacheKey, freshQuote.buyToVes);
      await prefs.setDouble(_usdtSellRateCacheKey, freshQuote.sellToVes);
      await prefs.setInt(_usdtQuoteCacheVersionKey, _usdtQuoteCacheVersion);
      await prefs.setString(
        _usdtRateUpdatedAtCacheKey,
        now.toIso8601String(),
      );
      return UsdtBinanceQuote(
        buyToVes: freshQuote.buyToVes,
        sellToVes: freshQuote.sellToVes,
        updatedAt: now,
      );
    } catch (_) {
      if (cachedUpdatedAt != null) {
        try {
          final updatedAt = DateTime.parse(cachedUpdatedAt);
          if (cachedBuy != null && cachedSell != null) {
            final buyValue =
                cachedVersion >= _usdtQuoteCacheVersion ? cachedBuy : cachedSell;
            final sellValue =
                cachedVersion >= _usdtQuoteCacheVersion ? cachedSell : cachedBuy;
            return UsdtBinanceQuote(
              buyToVes: buyValue,
              sellToVes: sellValue,
              updatedAt: updatedAt,
            );
          }
          if (cachedUsdt != null) {
            return UsdtBinanceQuote(
              buyToVes: cachedUsdt,
              sellToVes: cachedUsdt,
              updatedAt: updatedAt,
            );
          }
        } catch (_) {}
      }
      return UsdtBinanceQuote(
        buyToVes: cachedUsdt ?? fallbackRate,
        sellToVes: cachedUsdt ?? fallbackRate,
        updatedAt: DateTime.now(),
      );
    }
  }

  Future<UsdtBinanceQuote> _obtenerCotizacionUsdtBinance() async {
    final prices = await Future.wait<double>([
      _obtenerPromedioUsdtBinancePorTipo('SELL'),
      _obtenerPromedioUsdtBinancePorTipo('BUY'),
    ]);

    return UsdtBinanceQuote(
      buyToVes: prices[0],
      sellToVes: prices[1],
      updatedAt: DateTime.now(),
    );
  }

  int _obtenerIndiceInicial(List<ExchangeRates> options) {
    final now = DateTime.now();
    int index = 0;
    for (int i = 0; i < options.length; i++) {
      if (!options[i].lastUpdate.isAfter(now)) {
        index = i;
      }
    }
    return index;
  }

  bool _esMismaFecha(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  ExchangeRates _obtenerTasaParaWidget(List<ExchangeRates> options) {
    if (options.isEmpty) {
      throw const FormatException('No hay tasas disponibles para el widget');
    }

    final now = DateTime.now();
    final hoy = DateTime(now.year, now.month, now.day);
    final isWeekend =
        now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;

    // En fin de semana se usa la tasa mas reciente que devuelve el JSON.
    if (isWeekend) {
      return options.last;
    }

    ExchangeRates? tasaDeHoy;
    for (final rate in options) {
      if (_esMismaFecha(rate.lastUpdate, hoy)) {
        tasaDeHoy = rate;
      }
    }

    if (tasaDeHoy != null) {
      return tasaDeHoy;
    }

    // Si no hay registro exacto de hoy, usa el mas reciente no futuro.
    for (int i = options.length - 1; i >= 0; i--) {
      if (!options[i].lastUpdate.isAfter(now)) {
        return options[i];
      }
    }

    // Ultimo fallback: el registro mas reciente del JSON.
    return options.last;
  }

  Future<double> _obtenerPromedioUsdtBinancePorTipo(String tradeType) async {
    final uri =
        kIsWeb
            ? Uri.parse('https://corsproxy.io/?$_binanceP2pEndpoint')
            : Uri.parse(_binanceP2pEndpoint);

    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'page': 1,
            'rows': 20,
            'payTypes': <String>[],
            'asset': 'USDT',
            'tradeType': tradeType,
            'fiat': 'VES',
            'publisherType': 'merchant',
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: fallo consulta Binance P2P');
    }

    final Map<String, dynamic> body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final rowsDynamic = body['data'];
    if (rowsDynamic is! List<dynamic>) {
      throw const FormatException('Binance P2P sin lista de datos');
    }

    final List<dynamic> rows = rowsDynamic;
    if (rows.isEmpty) {
      throw const FormatException('Binance P2P sin datos para USDT/VES');
    }

    final prices = <double>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final advDynamic = row['adv'];
      if (advDynamic is! Map<String, dynamic>) continue;
      final price = _toDoubleOrNull(advDynamic['price']);
      if (price != null && price > 0) {
        prices.add(price);
      }
    }

    if (prices.isEmpty) {
      throw const FormatException('Binance P2P sin precios válidos');
    }

    final total = prices.fold<double>(0, (sum, price) => sum + price);
    return total / prices.length;
  }

  Future<void> _cargarCotizacionUsdtParaVista({
    bool forceRefresh = false,
  }) async {
    if (_isLoadingUsdtQuote) return;
    if (!forceRefresh && _usdtBuyRate != null && _usdtSellRate != null) return;

    final fallbackRate = rates?.usdtToVes ?? rates?.usdToVes ?? 0;

    setState(() {
      _isLoadingUsdtQuote = true;
      _usdtQuoteError = null;
    });

    try {
      final quote = forceRefresh
          ? await _obtenerCotizacionUsdtBinance()
          : await _obtenerCotizacionUsdtConCacheHorario(fallbackRate);

      if (!mounted) return;
      setState(() {
        _actualizarCotizacionUsdtEnMemoria(quote);
        _isLoadingUsdtQuote = false;
        _usdtQuoteError = null;
      });
      _recalcularConversionActual();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingUsdtQuote = false;
        _usdtQuoteError = 'No se pudo actualizar compra/venta de Binance.';
      });
    }
  }

  Future<void> _guardarTasasEnCache(ExchangeRates exchangeRates) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'usd': exchangeRates.usdToVes,
      'eur': exchangeRates.eurToVes,
      'usdt': exchangeRates.usdtToVes,
      'date': exchangeRates.lastUpdate.toIso8601String(),
    });
    await prefs.setString(_ratesCacheKey, payload);
  }

  Future<ExchangeRates?> _leerTasasDesdeCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedValue = prefs.getString(_ratesCacheKey);

    if (cachedValue == null || cachedValue.isEmpty) {
      return null;
    }

    final Map<String, dynamic> data =
        jsonDecode(cachedValue) as Map<String, dynamic>;

    final usd = _toDoubleOrNull(data['usd']);
    final eur = _toDoubleOrNull(data['eur']);
    final usdt = _toDoubleOrNull(data['usdt']) ?? usd;
    final dateRaw = data['date'];

    if (usd == null || eur == null || usdt == null || dateRaw is! String) {
      return null;
    }

    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(dateRaw);
    } catch (_) {
      parsedDate = DateTime.now();
    }

    return ExchangeRates(
      usdToVes: usd,
      eurToVes: eur,
      usdtToVes: usdt,
      lastUpdate: parsedDate,
    );
  }

  Future<void> _manejarErrorConCache(String message) async {
    final cachedRates = await _leerTasasDesdeCache();
    final fallbackRates =
        cachedRates ??
        ExchangeRates(
          usdToVes: 0.22,
          eurToVes: 7.33,
          usdtToVes: 0.22,
          lastUpdate: DateTime.now(),
        );

    if (!mounted) return;

    setState(() {
      error = cachedRates != null
          ? '$message Mostrando última tasa guardada.'
          : '$message No hay datos guardados en caché.';
      isLoading = false;
      rates = fallbackRates;
      rateOptions = [rates!];
      selectedRateIndex = 0;
      _actualizarTextosDerivados();
    });
    await _actualizarHomeWidget(fallbackRates);
  }

  Future<void> obtenerTasasActuales({bool mostrarCarga = true}) async {
    try {
      if (mostrarCarga) {
        setState(() {
          isLoading = true;
          error = null;
        });
      }

      final fetchedRates = await obtenerPrecios();
      final initialIndex = _obtenerIndiceInicial(fetchedRates);
      final selectedRates = fetchedRates[initialIndex];
      final widgetRates = _obtenerTasaParaWidget(fetchedRates);
      await _guardarTasasEnCache(selectedRates);

      if (!mounted) return;

      setState(() {
        rateOptions = fetchedRates;
        selectedRateIndex = initialIndex;
        rates = selectedRates;
        isLoading = false;
        _actualizarTextosDerivados();
      });
      await _actualizarHomeWidget(widgetRates);
    } on TimeoutException {
      await _manejarErrorConCache('Tiempo de espera agotado al consultar precios.');
    } on http.ClientException {
      await _manejarErrorConCache(
        'Sin conexión o error de red al consultar precios.',
      );
    } on FormatException {
      await _manejarErrorConCache('Respuesta JSON inválida.');
    } catch (e) {
      await _manejarErrorConCache(
        'No se pudieron obtener las tasas. Intenta de nuevo.',
      );
    }
  }

  double _convertirMonto(double monto, String source, String target) {
    if (rates == null || source == target) {
      return monto;
    }

    final sourceRate = _obtenerTasaEnVes(source);
    final targetRate = _obtenerTasaEnVes(target);
    return (monto * sourceRate) / targetRate;
  }

  double _obtenerTasaEnVes(String currency) {
    if (currency == 'VES') return 1;
    if (currency == 'USD') return rates!.usdToVes;
    if (currency == 'EUR') return rates!.eurToVes;
    if (currency == 'USDT') {
      if (_usdtBuyRate != null && _usdtSellRate != null) {
        switch (_usdtRateMode) {
          case UsdtRateMode.buyAverage:
            return _usdtBuyRate!;
          case UsdtRateMode.sellAverage:
            return _usdtSellRate!;
        }
      }
      return rates!.usdtToVes;
    }
    return 1;
  }

  void _cambiarModoTasaUsdt(UsdtRateMode mode) {
    if (_usdtRateMode == mode) return;
    setState(() {
      _usdtRateMode = mode;
    });
    _recalcularConversionActual();
  }

  double? _parseMonto(String input, {required bool isVes}) {
    var normalized = input.trim().replaceAll(' ', '');
    if (normalized.isEmpty) return null;

    if (isVes) {
      if (normalized.contains(',')) {
        normalized = normalized.replaceAll('.', '');
        normalized = normalized.replaceAll(',', '.');
      } else {
        final dotCount = '.'.allMatches(normalized).length;
        if (dotCount > 1) {
          normalized = normalized.replaceAll('.', '');
        }
      }
    } else {
      if (normalized.contains(',') && normalized.contains('.')) {
        normalized = normalized.replaceAll('.', '');
        normalized = normalized.replaceAll(',', '.');
      } else {
        normalized = normalized.replaceAll(',', '.');
      }
    }

    return double.tryParse(normalized);
  }

  String _agregarSeparadoresMiles(String number) {
    final isNegative = number.startsWith('-');
    final digits = isNegative ? number.substring(1) : number;
    final chars = digits.split('').reversed.toList();
    final out = <String>[];

    for (var i = 0; i < chars.length; i++) {
      out.add(chars[i]);
      if ((i + 1) % 3 == 0 && i + 1 < chars.length) {
        out.add('.');
      }
    }

    final formatted = out.reversed.join();
    return isNegative ? '-$formatted' : formatted;
  }

  String _formatearMontoVes(double value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final intPart = _agregarSeparadoresMiles(parts[0]);
    final decPart = parts.length > 1 ? parts[1] : '00';
    return '$intPart,$decPart';
  }

  void _setControllerText(TextEditingController controller, String value) {
    _isUpdatingText = true;
    controller.text = value;
    controller.selection = TextSelection.collapsed(offset: value.length);
    _isUpdatingText = false;
  }

  void _actualizarCampoDestino({required bool desdeArriba}) {
    if (_isUpdatingText) return;

    final sourceController = desdeArriba ? _fromController : _toController;
    final targetController = desdeArriba ? _toController : _fromController;

    if (rates == null) {
      _setControllerText(targetController, '');
      return;
    }

    final input = sourceController.text.trim();
    if (input.isEmpty) {
      _setControllerText(targetController, '');
      return;
    }

    final sourceCurrency = desdeArriba ? fromCurrency : 'VES';
    final targetCurrency = desdeArriba ? 'VES' : fromCurrency;

    final monto = _parseMonto(input, isVes: sourceCurrency == 'VES');
    if (monto == null) {
      _setControllerText(targetController, '');
      return;
    }

    final resultado = _convertirMonto(monto, sourceCurrency, targetCurrency);
    final formatted =
        targetCurrency == 'VES'
            ? _formatearMontoVes(resultado)
            : resultado.toStringAsFixed(2);

    _setControllerText(targetController, formatted);
  }

  void _recalcularConversionActual() {
    if (_fromController.text.trim().isNotEmpty) {
      _actualizarCampoDestino(desdeArriba: true);
    } else {
      if (_toController.text.trim().isNotEmpty) {
        _actualizarCampoDestino(desdeArriba: false);
      } else {
        _setControllerText(_toController, '');
      }
    }
  }

  void _seleccionarMonedaDesdeTasa(String currency) {
    setState(() {
      fromCurrency = currency;
    });

    if (currency == 'USDT') {
      unawaited(_cargarCotizacionUsdtParaVista());
    }

    _recalcularConversionActual();
  }

  void _seleccionarRegistroTasa(int index) {
    if (index < 0 || index >= rateOptions.length) return;

    final selected = rateOptions[index];
    setState(() {
      selectedRateIndex = index;
      rates = selected;
      _actualizarTextosDerivados();
    });
    _recalcularConversionActual();
  }

  void limpiarMontos() {
    setState(() {
      _fromController.clear();
      _toController.clear();
    });
  }

  double get _calculatorTotalUsd {
    final usdRate = rates?.usdToVes ?? 0;
    return _calculatorEntries.fold<double>(0, (previousValue, entry) {
      if (entry.currency == 'USD') {
        return previousValue + entry.amount;
      }

      if (usdRate <= 0) {
        return previousValue;
      }

      return previousValue + (entry.amount / usdRate);
    });
  }

  double get _calculatorTotalVes {
    final usdRate = rates?.usdToVes ?? 0;
    return _calculatorEntries.fold<double>(0, (previousValue, entry) {
      if (entry.currency == 'VES') {
        return previousValue + entry.amount;
      }

      return previousValue + (entry.amount * usdRate);
    });
  }

  void _agregarMontoCalculadoraUsd() {
    final input = _calculatorUsdController.text.trim();
    final monto = _parseMonto(input, isVes: false);

    if (monto == null || monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa un monto válido mayor a cero en USD.'),
        ),
      );
      return;
    }

    setState(() {
      _calculatorEntries.add(
        _CalculatorEntry(currency: 'USD', amount: monto),
      );
      _calculatorUsdController.clear();
    });
  }

  void _agregarMontoCalculadoraVes() {
    final input = _calculatorVesController.text.trim();
    final monto = _parseMonto(input, isVes: true);

    if (monto == null || monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa un monto válido mayor a cero en Bs.'),
        ),
      );
      return;
    }

    setState(() {
      _calculatorEntries.add(
        _CalculatorEntry(currency: 'VES', amount: monto),
      );
      _calculatorVesController.clear();
    });
  }

  void _deshacerUltimoMontoCalculadora() {
    if (_calculatorEntries.isEmpty) return;

    setState(() {
      _calculatorEntries.removeLast();
    });
  }

  void _limpiarCalculadora() {
    if (_calculatorEntries.isEmpty &&
        _calculatorUsdController.text.isEmpty &&
        _calculatorVesController.text.isEmpty) {
      return;
    }

    setState(() {
      _calculatorEntries.clear();
      _calculatorUsdController.clear();
      _calculatorVesController.clear();
    });
  }

  void _eliminarMontoCalculadora(int index) {
    if (index < 0 || index >= _calculatorEntries.length) return;

    setState(() {
      _calculatorEntries.removeAt(index);
    });
  }

  Future<void> _copiarMontoAlPortapapeles(
    TextEditingController controller,
    String currency,
  ) async {
    final monto = controller.text.trim();
    if (monto.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay monto para copiar.')),
      );
      return;
    }

    String montoParaCopiar;
    if (currency == 'VES') {
      final parsed = _parseMonto(monto, isVes: true);
      montoParaCopiar =
          parsed != null
              ? parsed.toStringAsFixed(2).replaceAll('.', ',')
              : monto.replaceAll('.', ',');
    } else {
      montoParaCopiar = monto.replaceAll('.', ',');
    }

    await Clipboard.setData(ClipboardData(text: montoParaCopiar));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Monto copiado: $montoParaCopiar $currency')),
    );
  }

  Future<void> _compartirCapturaApp() async {
    final montoOrigen = _fromController.text.trim();
    final montoVes = _toController.text.trim();
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final capturePixelRatio =
        (devicePixelRatio * 2).clamp(2.0, 4.0).toDouble();

    final shareText =
        'Monto en $fromCurrency: ${montoOrigen.isEmpty ? '-' : montoOrigen}\n'
        'Monto en VES: ${montoVes.isEmpty ? '-' : montoVes}';

    try {
      final bytes = await _screenshotController.capture(
        pixelRatio: capturePixelRatio,
        delay: const Duration(milliseconds: 80),
      );

      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo generar la captura.')),
        );
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final fileName = 'rapidobcv_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'image/png')],
          text: shareText,
          subject: 'RápidoBCV',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo compartir: ${e.runtimeType}')),
      );
    }
  }

  String _formatearFechaAdquisicion(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  String _formatearHora(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _actualizarHomeWidget(ExchangeRates exchangeRates) async {
    try {
      final usdtUpdatedAt = _usdtLastUpdatedAt ?? DateTime.now();
      await HomeWidget.saveWidgetData<String>(
        'last_update',
        '${_formatearFechaCorta(usdtUpdatedAt)} ${_formatearHora(usdtUpdatedAt)}',
      );
      await HomeWidget.saveWidgetData<String>(
        'usd_value',
        exchangeRates.usdToVes.toStringAsFixed(2),
      );
      await HomeWidget.saveWidgetData<String>(
        'eur_value',
        exchangeRates.eurToVes.toStringAsFixed(2),
      );
      await HomeWidget.saveWidgetData<String>(
        'usdt_value',
        exchangeRates.usdtToVes.toStringAsFixed(2),
      );
      await HomeWidget.updateWidget(androidName: 'RapidobcvWidgetProvider');
    } catch (_) {}
  }

  String _formatearFechaCorta(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    return '$day/$month';
  }

  String _labelRegistro(int index) {
    if (index < 0 || index >= rateOptions.length) return 'Sin fecha';

    if (rateOptions.length == 2) {
      final base = index == 0 ? 'Tasa del' : 'Tasa del';
      return '$base ${_formatearFechaCorta(rateOptions[index].lastUpdate)}';
    }

    return _formatearFechaCorta(rateOptions[index].lastUpdate);
  }

  void _actualizarTextosDerivados() {
    _rateLabelsCache = List<String>.generate(
      rateOptions.length,
      (index) => _labelRegistro(index),
    );

    DateTime? fechaAdquisicionVisible;
    if (rates != null) {
      final baseDate = rates!.lastUpdate;
      final usdtTime = _usdtLastUpdatedAt;

      fechaAdquisicionVisible =
          usdtTime == null
              ? baseDate
              : DateTime(
                baseDate.year,
                baseDate.month,
                baseDate.day,
                usdtTime.hour,
                usdtTime.minute,
              );
    }

    _acquisitionTextCache =
        fechaAdquisicionVisible == null
            ? null
            : 'Fecha de adquisición: ${_formatearFechaAdquisicion(fechaAdquisicionVisible)}';
  }

  Icon _iconoMoneda(String currency) {
    if (currency == 'EUR') return const Icon(Icons.euro);
    if (currency == 'USDT') return const Icon(Icons.currency_exchange);
    return const Icon(Icons.attach_money);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RápidoBCV'),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => widget.onToggleTheme(isDarkMode),
            tooltip: isDarkMode
                ? 'Cambiar a modo claro'
                : 'Cambiar a modo oscuro',
            icon: Icon(
              isDarkMode ? Icons.light_mode : Icons.dark_mode,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Screenshot(
              controller: _screenshotController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RatesPanel(
                    isLoading: isLoading,
                    error: error,
                    rates: rates,
                    selectedCurrency: fromCurrency,
                    selectedRateIndex: selectedRateIndex,
                    rateLabels: _rateLabelsCache,
                    onRetry: () => obtenerTasasActuales(),
                    onSelectCurrency: _seleccionarMonedaDesdeTasa,
                    onSelectRateIndex: _seleccionarRegistroTasa,
                    acquisitionText: _acquisitionTextCache,
                    usdtBuyRate: _usdtBuyRate,
                    usdtSellRate: _usdtSellRate,
                    usdtQuoteUpdatedAt: _usdtQuoteUpdatedAt,
                    isLoadingUsdtQuote: _isLoadingUsdtQuote,
                    usdtQuoteError: _usdtQuoteError,
                    selectedUsdtRateMode: _usdtRateMode,
                    onRefreshUsdtQuote: () =>
                        _cargarCotizacionUsdtParaVista(forceRefresh: true),
                    onSelectUsdtRateMode: _cambiarModoTasaUsdt,
                  ),
                  const SizedBox(height: 30),
                  _ConverterPanel(
                    fromController: _fromController,
                    toController: _toController,
                    fromCurrency: fromCurrency,
                    fromCurrencyIcon: _iconoMoneda(fromCurrency),
                    onClear: limpiarMontos,
                    onFromChanged: () =>
                        _actualizarCampoDestino(desdeArriba: true),
                    onToChanged: () =>
                        _actualizarCampoDestino(desdeArriba: false),
                    onCopyFrom: () =>
                        _copiarMontoAlPortapapeles(_fromController, fromCurrency),
                    onCopyTo: () =>
                        _copiarMontoAlPortapapeles(_toController, 'VES'),
                    onRefreshRates: () => obtenerTasasActuales(),
                    onShareCapture: _compartirCapturaApp,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _UsdCalculatorPanel(
              usdInputController: _calculatorUsdController,
              vesInputController: _calculatorVesController,
              entries: _calculatorEntries,
              totalUsdText: _calculatorTotalUsd.toStringAsFixed(2),
              totalVesText: _formatearMontoVes(_calculatorTotalVes),
              usdRateText:
                  rates == null ? '-' : rates!.usdToVes.toStringAsFixed(2),
              onAddUsd: _agregarMontoCalculadoraUsd,
              onAddVes: _agregarMontoCalculadoraVes,
              onUndoLast: _deshacerUltimoMontoCalculadora,
              onClear: _limpiarCalculadora,
              onRemoveEntry: _eliminarMontoCalculadora,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _calculatorUsdController.dispose();
    _calculatorVesController.dispose();
    super.dispose();
  }
}

class _RatesPanel extends StatelessWidget {
  const _RatesPanel({
    required this.isLoading,
    required this.error,
    required this.rates,
    required this.selectedCurrency,
    required this.selectedRateIndex,
    required this.rateLabels,
    required this.onRetry,
    required this.onSelectCurrency,
    required this.onSelectRateIndex,
    required this.acquisitionText,
    required this.usdtBuyRate,
    required this.usdtSellRate,
    required this.usdtQuoteUpdatedAt,
    required this.isLoadingUsdtQuote,
    required this.usdtQuoteError,
    required this.selectedUsdtRateMode,
    required this.onRefreshUsdtQuote,
    required this.onSelectUsdtRateMode,
  });

  final bool isLoading;
  final String? error;
  final ExchangeRates? rates;
  final String selectedCurrency;
  final int selectedRateIndex;
  final List<String> rateLabels;
  final VoidCallback onRetry;
  final ValueChanged<String> onSelectCurrency;
  final ValueChanged<int> onSelectRateIndex;
  final String? acquisitionText;
  final double? usdtBuyRate;
  final double? usdtSellRate;
  final DateTime? usdtQuoteUpdatedAt;
  final bool isLoadingUsdtQuote;
  final String? usdtQuoteError;
  final UsdtRateMode selectedUsdtRateMode;
  final VoidCallback onRefreshUsdtQuote;
  final ValueChanged<UsdtRateMode> onSelectUsdtRateMode;

  @override
  Widget build(BuildContext context) {
    final selectedUsdtRate = usdtBuyRate != null && usdtSellRate != null
      ? (selectedUsdtRateMode == UsdtRateMode.buyAverage
        ? usdtBuyRate!
        : usdtSellRate!)
      : rates?.usdtToVes;

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Text(
              'Tasas Actuales',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            if (isLoading)
              const CircularProgressIndicator()
            else if (error != null && rates == null)
              Column(
                children: [
                  Text(
                    error!,
                    style: const TextStyle(color: Colors.orange),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Intentar de nuevo'),
                  ),
                ],
              )
            else if (rates != null)
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _RateTile(
                        currency: 'USD',
                        rate: rates!.usdToVes.toStringAsFixed(2),
                        isSelected: selectedCurrency == 'USD',
                        onTap: () => onSelectCurrency('USD'),
                      ),
                      const SizedBox(width: 10),
                      _RateTile(
                        currency: 'EUR',
                        rate: rates!.eurToVes.toStringAsFixed(2),
                        isSelected: selectedCurrency == 'EUR',
                        onTap: () => onSelectCurrency('EUR'),
                      ),
                      const SizedBox(width: 10),
                      _RateTile(
                        currency: 'USDT',
                        rate: (selectedUsdtRate ?? rates!.usdtToVes)
                            .toStringAsFixed(2),
                        isSelected: selectedCurrency == 'USDT',
                        onTap: () => onSelectCurrency('USDT'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    acquisitionText ?? 'Fecha de adquisición: -',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (selectedCurrency == 'USDT') ...[
                    const SizedBox(height: 12),
                    SegmentedButton<UsdtRateMode>(
                      segments: const <ButtonSegment<UsdtRateMode>>[
                        ButtonSegment<UsdtRateMode>(
                          value: UsdtRateMode.buyAverage,
                          label: Text('Compra'),
                        ),
                        ButtonSegment<UsdtRateMode>(
                          value: UsdtRateMode.sellAverage,
                          label: Text('Venta'),
                        ),
                      ],
                      selected: <UsdtRateMode>{selectedUsdtRateMode},
                      onSelectionChanged: (Set<UsdtRateMode> selection) {
                        if (selection.isNotEmpty) {
                          onSelectUsdtRateMode(selection.first);
                        }
                      },
                    ),
                  ] else if (rateLabels.length > 1) ...[
                    const SizedBox(height: 12),
                    SegmentedButton<int>(
                      segments: List<ButtonSegment<int>>.generate(
                        rateLabels.length,
                        (index) => ButtonSegment<int>(
                          value: index,
                          label: Text(rateLabels[index]),
                        ),
                      ),
                      selected: <int>{selectedRateIndex},
                      onSelectionChanged: (Set<int> selection) {
                        if (selection.isNotEmpty) {
                          onSelectRateIndex(selection.first);
                        }
                      },
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _RateTile extends StatelessWidget {
  const _RateTile({
    required this.currency,
    required this.rate,
    required this.isSelected,
    required this.onTap,
  });

  final String currency;
  final String rate;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:
                isSelected
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  isSelected
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
              width: isSelected ? 1.8 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                currency,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color:
                      isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '$rate Bs',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color:
                      isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConverterPanel extends StatelessWidget {
  const _ConverterPanel({
    required this.fromController,
    required this.toController,
    required this.fromCurrency,
    required this.fromCurrencyIcon,
    required this.onClear,
    required this.onFromChanged,
    required this.onToChanged,
    required this.onCopyFrom,
    required this.onCopyTo,
    required this.onRefreshRates,
    required this.onShareCapture,
  });

  final TextEditingController fromController;
  final TextEditingController toController;
  final String fromCurrency;
  final Icon fromCurrencyIcon;
  final VoidCallback onClear;
  final VoidCallback onFromChanged;
  final VoidCallback onToChanged;
  final VoidCallback onCopyFrom;
  final VoidCallback onCopyTo;
  final VoidCallback onRefreshRates;
  final VoidCallback onShareCapture;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: fromController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: fromCurrency,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: fromCurrencyIcon,
                  suffixText: fromCurrency,
                  suffixIcon: IconButton(
                    onPressed: onClear,
                    icon: const Icon(Icons.clear),
                    tooltip: 'Limpiar montos',
                  ),
                ),
                onChanged: (_) => onFromChanged(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onCopyFrom,
              tooltip: 'Copiar monto',
              icon: const Icon(Icons.copy),
            ),
          ],
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: toController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'VES',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.payments),
                  suffixText: 'VES',
                  suffixIcon: IconButton(
                    onPressed: onClear,
                    icon: const Icon(Icons.clear),
                    tooltip: 'Limpiar montos',
                  ),
                ),
                onChanged: (_) => onToChanged(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onCopyTo,
              tooltip: 'Copiar monto',
              icon: const Icon(Icons.copy),
            ),
          ],
        ),
        const SizedBox(height: 30),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onRefreshRates,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar Tasas'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onShareCapture,
                icon: const Icon(Icons.share),
                label: const Text('Compartir'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _UsdCalculatorPanel extends StatelessWidget {
  const _UsdCalculatorPanel({
    required this.usdInputController,
    required this.vesInputController,
    required this.entries,
    required this.totalUsdText,
    required this.totalVesText,
    required this.usdRateText,
    required this.onAddUsd,
    required this.onAddVes,
    required this.onUndoLast,
    required this.onClear,
    required this.onRemoveEntry,
  });

  final TextEditingController usdInputController;
  final TextEditingController vesInputController;
  final List<_CalculatorEntry> entries;
  final String totalUsdText;
  final String totalVesText;
  final String usdRateText;
  final VoidCallback onAddUsd;
  final VoidCallback onAddVes;
  final VoidCallback onUndoLast;
  final VoidCallback onClear;
  final ValueChanged<int> onRemoveEntry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Calculadora de compras',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text(
                    'Equivalente: $totalVesText Bs',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total acumulado: $totalUsdText USD',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tasa usada (BCV USD): $usdRateText Bs',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: usdInputController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: false,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Monto en USD',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      prefixIcon: const Icon(Icons.attach_money),
                      suffixText: 'USD',
                    ),
                    onSubmitted: (_) => onAddUsd(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: onAddUsd,
                  icon: const Icon(Icons.add),
                  label: const Text('Sumar USD'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: vesInputController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: false,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Monto en Bs',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      prefixIcon: const Icon(Icons.payments),
                      suffixText: 'VES',
                    ),
                    onSubmitted: (_) => onAddVes(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: onAddVes,
                  icon: const Icon(Icons.add),
                  label: const Text('Sumar Bs'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Text(
                'Aún no hay montos agregados.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    entries
                        .asMap()
                        .entries
                        .map(
                          (entry) => Chip(
                            label: Text(
                              '${entry.value.amount.toStringAsFixed(2)} ${entry.value.currency}',
                            ),
                            onDeleted: () => onRemoveEntry(entry.key),
                            deleteIcon: const Icon(Icons.close),
                          ),
                        )
                        .toList(),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onUndoLast,
                    icon: const Icon(Icons.undo),
                    label: const Text('Deshacer último'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Limpiar'),
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

class _CalculatorEntry {
  const _CalculatorEntry({
    required this.currency,
    required this.amount,
  });

  final String currency;
  final double amount;
}
