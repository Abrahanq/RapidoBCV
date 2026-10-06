import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'rates_service.dart';

// ============================================================================
// Histórico BCV: calendario con las tasas publicadas
// ============================================================================

/// Tasa elegida en el calendario y la del día hábil anterior (para la variación).
class HistorialSelection {
  final ExchangeRates rate;
  final ExchangeRates? previous;
  const HistorialSelection({required this.rate, this.previous});
}

/// Abre la hoja del histórico. Devuelve la tasa elegida si el usuario pulsa
/// "Usar esta tasa", o `null` si cierra la hoja.
Future<HistorialSelection?> showHistorialSheet(
  BuildContext context, {
  required RatesService service,
  required Color accent,
  Color? background,
  Color? card,
  Color? border,
  Color? text,
  Color? dim,
  DateTime? initialDate,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<HistorialSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: background ?? scheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _HistorialSheet(
      service: service,
      accent: accent,
      card: card ?? scheme.surfaceContainerHighest,
      border: border ?? scheme.outlineVariant,
      text: text ?? scheme.onSurface,
      dim: dim ?? scheme.onSurfaceVariant,
      initialDate: initialDate,
    ),
  );
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

String _fmtVes(double v) {
  final parts = v.toStringAsFixed(2).split('.');
  final digits = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return '$buf,${parts[1]}';
}

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class _HistorialSheet extends StatefulWidget {
  final RatesService service;
  final Color accent, card, border, text, dim;
  final DateTime? initialDate;

  const _HistorialSheet({
    required this.service,
    required this.accent,
    required this.card,
    required this.border,
    required this.text,
    required this.dim,
    this.initialDate,
  });

  @override
  State<_HistorialSheet> createState() => _HistorialSheetState();
}

class _HistorialSheetState extends State<_HistorialSheet> {
  late Future<List<ExchangeRates>> _future;
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    _future = widget.service.fetchHistory();
  }

  void _retry() => setState(() => _future = widget.service.fetchHistory());

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: widget.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Histórico BCV',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: widget.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Toca un día con tasa publicada',
            style: TextStyle(fontSize: 13, color: widget.dim),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: FutureBuilder<List<ExchangeRates>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 260,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError || !snap.hasData) return _buildError();
                return _buildContent(snap.data!);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return SizedBox(
      height: 220,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, color: widget.dim, size: 32),
          const SizedBox(height: 10),
          Text(
            'No se pudo cargar el histórico.',
            style: TextStyle(color: widget.dim),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _retry,
            child: Text('Reintentar', style: TextStyle(color: widget.accent)),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(List<ExchangeRates> history) {
    final byDay = <DateTime, int>{
      for (var i = 0; i < history.length; i++) _day(history[i].lastUpdate): i,
    };
    final first = _day(history.first.lastUpdate);
    final last = _day(history.last.lastUpdate);

    // El día inicial debe existir en el histórico o el calendario falla.
    var selected = _selected ?? widget.initialDate;
    if (selected == null || !byDay.containsKey(_day(selected))) {
      selected = last;
    }
    selected = _day(selected);

    final idx = byDay[selected]!;
    final rate = history[idx];
    final prev = idx > 0 ? history[idx - 1] : null;

    final theme = Theme.of(context);
    final onAccent =
        ThemeData.estimateBrightnessForColor(widget.accent) == Brightness.dark
        ? Colors.white
        : Colors.black;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Theme(
            data: theme.copyWith(
              colorScheme: theme.colorScheme.copyWith(
                primary: widget.accent,
                onPrimary: onAccent,
                onSurface: widget.text,
              ),
            ),
            child: CalendarDatePicker(
              initialDate: selected,
              firstDate: first,
              lastDate: last,
              selectableDayPredicate: (d) => byDay.containsKey(_day(d)),
              onDateChanged: (d) => setState(() => _selected = d),
            ),
          ),
          _buildRateCard(rate, prev),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: widget.accent,
              foregroundColor: onAccent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => Navigator.of(
              context,
            ).pop(HistorialSelection(rate: rate, previous: prev)),
            child: const Text(
              'Usar esta tasa en el conversor',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRateCard(ExchangeRates rate, ExchangeRates? prev) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.card,
        border: Border.all(color: widget.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TASA VIGENTE EL ${_fmtDate(rate.lastUpdate)}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: widget.accent,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _rateColumn(r'$ Dólar', rate.usdToVes, prev?.usdToVes),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _rateColumn('€ Euro', rate.eurToVes, prev?.eurToVes),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rateColumn(String label, double value, double? prev) {
    final change = prev != null && prev > 0
        ? (value - prev) / prev * 100
        : null;
    final isUp = (change ?? 0) >= 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final changeColor = isUp
        ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
        : (isDark ? const Color(0xFFFC6868) : const Color(0xFFDC2626));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: widget.dim)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            '${_fmtVes(value)} Bs',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: widget.text,
            ),
          ),
        ),
        if (change != null)
          Text(
            '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}% vs día anterior',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: changeColor,
            ),
          ),
      ],
    );
  }
}
