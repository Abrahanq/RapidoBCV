import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

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

enum UsdtRateMode { buyAverage, sellAverage }

// ─── Service ──────────────────────────────────────────────────────────────────

class RatesService {
  static const _ratesCacheKey = 'exchange_rates_cache';
  static const _usdtRateCacheKey = 'usdt_rate_cache';
  static const _usdtBuyRateCacheKey = 'usdt_buy_rate_cache';
  static const _usdtSellRateCacheKey = 'usdt_sell_rate_cache';
  static const _usdtRateUpdatedAtCacheKey = 'usdt_rate_updated_at_cache';
  static const _usdtQuoteCacheVersionKey = 'usdt_quote_cache_version';
  static const _usdtQuoteCacheVersion = 2;
  static const _binanceP2pEndpoint =
      'https://p2p.binance.com/bapi/c2c/v2/friendly/c2c/adv/search';

  static double? _n(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.'));
    return null;
  }

  Future<List<ExchangeRates>> fetchPrices() async {
    final uri = Uri.parse('https://abrahanq.github.io/bcv-price/prices.json')
        .replace(queryParameters: {
      'v': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final records = <Map<String, dynamic>>[];
    final precios = data['precios'];

    if (precios is List && precios.isNotEmpty) {
      for (final item in precios) {
        if (item is! Map) continue;
        final d = item.cast<String, dynamic>();
        final usd = _n(d['usd']);
        final eur = _n(d['eur']);
        if (usd == null || eur == null) continue;
        final dateRaw = d['date'] ?? d['fecha'];
        DateTime date;
        try {
          date = DateTime.parse(dateRaw as String);
        } catch (_) {
          date = DateTime.now();
        }
        records.add({
          'usd': usd,
          'eur': eur,
          'usdt': _n(d['usdt']),
          'date': date,
        });
      }
    } else {
      final usd = _n(data['usd']);
      final eur = _n(data['eur']);
      if (usd != null && eur != null) {
        final dateRaw = data['date'] ?? data['fecha'];
        DateTime date;
        try {
          date = DateTime.parse(dateRaw as String);
        } catch (_) {
          date = DateTime.now();
        }
        records.add({
          'usd': usd,
          'eur': eur,
          'usdt': _n(data['usdt']),
          'date': date,
        });
      }
    }

    if (records.isEmpty) throw const FormatException('No valid rates found');

    final fallbackUsd = (records.last['usd'] as double?) ?? 0;
    final hasMissingUsdt = records.any((r) => r['usdt'] == null);
    final fallbackUsdt = hasMissingUsdt
        ? (await fetchUsdtQuoteWithCache(fallbackUsd)).averageToVes
        : fallbackUsd;

    return (records
          .map((r) => ExchangeRates(
                usdToVes: r['usd'] as double,
                eurToVes: r['eur'] as double,
                usdtToVes: (r['usdt'] as double?) ?? fallbackUsdt,
                lastUpdate: r['date'] as DateTime,
              ))
          .toList()
          ..sort((a, b) => a.lastUpdate.compareTo(b.lastUpdate)));
  }

  Future<UsdtBinanceQuote> fetchUsdtQuoteWithCache(double fallback) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedBuy = prefs.getDouble(_usdtBuyRateCacheKey);
    final cachedSell = prefs.getDouble(_usdtSellRateCacheKey);
    final cachedAt = prefs.getString(_usdtRateUpdatedAtCacheKey);
    final cachedVersion = prefs.getInt(_usdtQuoteCacheVersionKey) ?? 1;

    if (cachedBuy != null && cachedSell != null && cachedAt != null) {
      try {
        final updatedAt = DateTime.parse(cachedAt);
        if (DateTime.now().difference(updatedAt) < const Duration(hours: 1)) {
          final buy =
              cachedVersion >= _usdtQuoteCacheVersion ? cachedBuy : cachedSell;
          final sell =
              cachedVersion >= _usdtQuoteCacheVersion ? cachedSell : cachedBuy;
          return UsdtBinanceQuote(
              buyToVes: buy, sellToVes: sell, updatedAt: updatedAt);
        }
      } catch (_) {}
    }

    try {
      final fresh = await fetchUsdtFromBinance();
      final now = DateTime.now();
      await prefs.setDouble(_usdtBuyRateCacheKey, fresh.buyToVes);
      await prefs.setDouble(_usdtSellRateCacheKey, fresh.sellToVes);
      await prefs.setDouble(_usdtRateCacheKey, fresh.averageToVes);
      await prefs.setInt(_usdtQuoteCacheVersionKey, _usdtQuoteCacheVersion);
      await prefs.setString(_usdtRateUpdatedAtCacheKey, now.toIso8601String());
      return UsdtBinanceQuote(
          buyToVes: fresh.buyToVes, sellToVes: fresh.sellToVes, updatedAt: now);
    } catch (_) {
      if (cachedBuy != null && cachedSell != null && cachedAt != null) {
        try {
          final updatedAt = DateTime.parse(cachedAt);
          final buy =
              cachedVersion >= _usdtQuoteCacheVersion ? cachedBuy : cachedSell;
          final sell =
              cachedVersion >= _usdtQuoteCacheVersion ? cachedSell : cachedBuy;
          return UsdtBinanceQuote(
              buyToVes: buy, sellToVes: sell, updatedAt: updatedAt);
        } catch (_) {}
      }
      final avg = prefs.getDouble(_usdtRateCacheKey);
      return UsdtBinanceQuote(
          buyToVes: avg ?? fallback,
          sellToVes: avg ?? fallback,
          updatedAt: DateTime.now());
    }
  }

  Future<UsdtBinanceQuote> fetchUsdtFromBinance() async {
    final prices = await Future.wait([
      _fetchBinanceByType('SELL'),
      _fetchBinanceByType('BUY'),
    ]);
    return UsdtBinanceQuote(
        buyToVes: prices[0], sellToVes: prices[1], updatedAt: DateTime.now());
  }

  Future<double> _fetchBinanceByType(String tradeType) async {
    final uri = kIsWeb
        ? Uri.parse('https://corsproxy.io/?$_binanceP2pEndpoint')
        : Uri.parse(_binanceP2pEndpoint);
    final response = await http
        .post(uri,
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
            }))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final rows = body['data'] as List<dynamic>;
    if (rows.isEmpty) throw const FormatException('No data');
    final prices = <double>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final adv = row['adv'];
      if (adv is! Map<String, dynamic>) continue;
      final p = _n(adv['price']);
      if (p != null && p > 0) prices.add(p);
    }
    if (prices.isEmpty) throw const FormatException('No valid prices');
    return prices.fold<double>(0, (s, p) => s + p) / prices.length;
  }

  Future<void> cacheRates(ExchangeRates r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _ratesCacheKey,
        jsonEncode({
          'usd': r.usdToVes,
          'eur': r.eurToVes,
          'usdt': r.usdtToVes,
          'date': r.lastUpdate.toIso8601String(),
        }));
  }

  Future<ExchangeRates?> readCachedRates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_ratesCacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final d = jsonDecode(raw) as Map<String, dynamic>;
      final usd = _n(d['usd']);
      final eur = _n(d['eur']);
      final usdt = _n(d['usdt']) ?? usd;
      final dateRaw = d['date'];
      if (usd == null || eur == null || usdt == null || dateRaw is! String) {
        return null;
      }
      DateTime date;
      try {
        date = DateTime.parse(dateRaw);
      } catch (_) {
        date = DateTime.now();
      }
      return ExchangeRates(
          usdToVes: usd, eurToVes: eur, usdtToVes: usdt, lastUpdate: date);
    } catch (_) {
      return null;
    }
  }

  Future<void> updateHomeWidget(ExchangeRates r, DateTime? usdtUpdatedAt) async {
    try {
      final t = usdtUpdatedAt ?? DateTime.now();
      final day = t.day.toString().padLeft(2, '0');
      final month = t.month.toString().padLeft(2, '0');
      final hour = t.hour.toString().padLeft(2, '0');
      final minute = t.minute.toString().padLeft(2, '0');
      await HomeWidget.saveWidgetData<String>(
          'last_update', '$day/$month $hour:$minute');
      await HomeWidget.saveWidgetData<String>(
          'usd_value', r.usdToVes.toStringAsFixed(2));
      await HomeWidget.saveWidgetData<String>(
          'eur_value', r.eurToVes.toStringAsFixed(2));
      await HomeWidget.saveWidgetData<String>(
          'usdt_value', r.usdtToVes.toStringAsFixed(2));
      await HomeWidget.updateWidget(androidName: 'RapidobcvWidgetProvider');
    } catch (_) {}
  }

  int initialIndex(List<ExchangeRates> opts) {
    final now = DateTime.now();
    int idx = 0;
    for (int i = 0; i < opts.length; i++) {
      if (!opts[i].lastUpdate.isAfter(now)) idx = i;
    }
    return idx;
  }

  ExchangeRates rateForWidget(List<ExchangeRates> opts) {
    if (opts.isEmpty) throw const FormatException('No rates');
    final now = DateTime.now();
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return opts.last;
    }
    final today = DateTime(now.year, now.month, now.day);
    for (final r in opts) {
      if (r.lastUpdate.year == today.year &&
          r.lastUpdate.month == today.month &&
          r.lastUpdate.day == today.day) {
        return r;
      }
    }
    for (int i = opts.length - 1; i >= 0; i--) {
      if (!opts[i].lastUpdate.isAfter(now)) return opts[i];
    }
    return opts.last;
  }
}
