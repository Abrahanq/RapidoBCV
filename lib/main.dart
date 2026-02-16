import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
      themeMode: ThemeMode.dark,
      home: const ConversorPage(),
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

class ConversorPage extends StatefulWidget {
  const ConversorPage({super.key});

  @override
  State<ConversorPage> createState() => _ConversorPageState();
}

class _ConversorPageState extends State<ConversorPage> {
  static const String _ratesCacheKey = 'exchange_rates_cache';
  bool _isUpdatingText = false;

  ExchangeRates? rates;
  bool isLoading = true;
  String? error;
  
  // Controllers para las conversiones
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  
  String fromCurrency = 'USD';

  @override
  void initState() {
    super.initState();
    obtenerTasasActuales();
  }

  double? _toDoubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.'));
    }
    return null;
  }

  Future<ExchangeRates> obtenerPrecios() async {
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

    Map<String, dynamic> precioData = data;
    if (data['precios'] is List && (data['precios'] as List).isNotEmpty) {
      precioData = ((data['precios'] as List).first as Map).cast<String, dynamic>();
    }

    final usd = _toDoubleOrNull(precioData['usd']);
    final eur = _toDoubleOrNull(precioData['eur']);

    if (usd == null || eur == null) {
      throw const FormatException('Faltan claves usd/eur en la respuesta');
    }

    final dateRaw = precioData['date'] ?? precioData['fecha'];
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(dateRaw as String);
    } catch (_) {
      parsedDate = DateTime.now();
    }

    double usdtPromedioBinance;
    try {
      usdtPromedioBinance = await _obtenerPromedioUsdtBinance();
    } catch (_) {
      usdtPromedioBinance = usd;
    }

    return ExchangeRates(
      usdToVes: usd,
      eurToVes: eur,
      usdtToVes: usdtPromedioBinance,
      lastUpdate: parsedDate,
    );
  }

  Future<double> _obtenerPrecioUsdtBinancePorTipo(String tradeType) async {
    final uri = Uri.parse(
      'https://p2p.binance.com/bapi/c2c/v2/friendly/c2c/adv/search',
    );

    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'page': 1,
            'rows': 1,
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

    final Map<String, dynamic> adv =
        (rows.first as Map<String, dynamic>)['adv'] as Map<String, dynamic>;
    final priceRaw = adv['price'];
    if (priceRaw == null) {
      throw const FormatException('Binance P2P sin precio en la oferta');
    }

    final price = _toDoubleOrNull(priceRaw);
    if (price == null) {
      throw const FormatException('Precio inválido en Binance P2P');
    }

    return price;
  }

  Future<double> _obtenerPromedioUsdtBinance() async {
    final prices = await Future.wait<double>([
      _obtenerPrecioUsdtBinancePorTipo('BUY'),
      _obtenerPrecioUsdtBinancePorTipo('SELL'),
    ]);

    return (prices[0] + prices[1]) / 2;
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

    if (!mounted) return;

    setState(() {
      error = cachedRates != null
          ? '$message Mostrando última tasa guardada.'
          : '$message No hay datos guardados en caché.';
      isLoading = false;
      rates =
          cachedRates ??
          ExchangeRates(
            usdToVes: 0.22,
            eurToVes: 7.33,
            usdtToVes: 0.22,
            lastUpdate: DateTime.now(),
          );
    });
  }

  Future<void> obtenerTasasActuales() async {
    try {
      setState(() {
        isLoading = true;
        error = null;
      });

      final fetchedRates = await obtenerPrecios();
      await _guardarTasasEnCache(fetchedRates);

      if (!mounted) return;

      setState(() {
        rates = fetchedRates;
        isLoading = false;
      });
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
    if (currency == 'USDT') return rates!.usdtToVes;
    return 1;
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

    final normalized = input.replaceAll(',', '.');
    final monto = double.tryParse(normalized);
    if (monto == null) {
      _setControllerText(targetController, '');
      return;
    }

    final sourceCurrency = desdeArriba ? fromCurrency : 'VES';
    final targetCurrency = desdeArriba ? 'VES' : fromCurrency;
    final resultado = _convertirMonto(monto, sourceCurrency, targetCurrency);

    _setControllerText(targetController, resultado.toStringAsFixed(2));
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
    _recalcularConversionActual();
  }

  void limpiarMontos() {
    setState(() {
      _fromController.clear();
      _toController.clear();
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

    final montoParaCopiar = monto.replaceAll('.', ',');

    await Clipboard.setData(ClipboardData(text: montoParaCopiar));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Monto copiado: $montoParaCopiar $currency')),
    );
  }

  String _formatearFechaAdquisicion(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RapidoBCV - Conversor'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tarjeta de tasas actuales
            Card(
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
                            onPressed: obtenerTasasActuales,
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
                              _buildRateCard(
                                context,
                                'USD',
                                '${rates!.usdToVes.toStringAsFixed(2)}',
                                () => _seleccionarMonedaDesdeTasa('USD'),
                              ),
                              const SizedBox(width: 10),
                              _buildRateCard(
                                context,
                                'EUR',
                                '${rates!.eurToVes.toStringAsFixed(2)}',
                                () => _seleccionarMonedaDesdeTasa('EUR'),
                              ),
                              const SizedBox(width: 10),
                              _buildRateCard(
                                context,
                                'USDT',
                                '${rates!.usdtToVes.toStringAsFixed(2)}',
                                () => _seleccionarMonedaDesdeTasa('USDT'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Fecha de adquisición: ${_formatearFechaAdquisicion(rates!.lastUpdate)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),

            // Conversor
            const Text(
              'Convertidor',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),

            // Campo de entrada
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _fromController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: '$fromCurrency',
                      // labelText: 'Dólares',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      prefixIcon: const Icon(Icons.attach_money),
                      suffixText: fromCurrency,
                      suffixIcon: IconButton(
                        onPressed: limpiarMontos,
                        icon: const Icon(Icons.clear),
                        tooltip: 'Limpiar montos',
                      ),
                    ),
                    onChanged: (_) => _actualizarCampoDestino(desdeArriba: true),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () =>
                      _copiarMontoAlPortapapeles(_fromController, fromCurrency),
                  tooltip: 'Copiar monto',
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            const SizedBox(height: 15),

            // Campo de salida
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _toController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'VES',
                      // labelText: 'Bolívares',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      prefixIcon: const Icon(Icons.attach_money),
                      suffixText: 'VES',
                      suffixIcon: IconButton(
                        onPressed: limpiarMontos,
                        icon: const Icon(Icons.clear),
                        tooltip: 'Limpiar montos',
                      ),
                    ),
                    onChanged: (_) => _actualizarCampoDestino(desdeArriba: false),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () =>
                      _copiarMontoAlPortapapeles(_toController, 'VES'),
                  tooltip: 'Copiar monto',
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            const SizedBox(height: 30),

            // Botón de actualizar
            ElevatedButton.icon(
              onPressed: obtenerTasasActuales,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar Tasas'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRateCard(
    BuildContext context,
    String currency,
    String rate,
    VoidCallback onTap,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text(
                currency,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '$rate Bs',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }
}
