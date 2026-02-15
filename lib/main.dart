import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Conversor Dólar BCV',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const ConversorPage(),
    );
  }
}

class ConversorPage extends StatefulWidget {
  const ConversorPage({super.key});

  @override
  State<ConversorPage> createState() => _ConversorPageState();
}

class _ConversorPageState extends State<ConversorPage> {
  double? tasaBcv;
  bool isLoading = true;
  String? error;
  final TextEditingController _dolarController = TextEditingController();
  final TextEditingController _bolivaresController = TextEditingController();
  double? resultadoBolivares;
  double? resultadoDolares;

  @override
  void initState() {
    super.initState();
    obtenerTasaBcv();
    
  }

  Future<void> obtenerTasaBcv() async {
    try {
      // Usando la API de DolarApi.com
      final response = await http.get(
        Uri.parse('https://ve.dolarapi.com/v1/dolares/oficial'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          tasaBcv = data['promedio'].toDouble();
          isLoading = false;
        });
      } else {
        throw Exception('Error al cargar la tasa');
      }
    } catch (e) {
      setState(() {
        error = 'No se pudo obtener la tasa del BCV';
        isLoading = false;
      });
    }
  }

  void calcularConversion() {
    if (_dolarController.text.isNotEmpty && tasaBcv != null) {
      final montoDolar = double.tryParse(_dolarController.text);
      if (montoDolar != null) {
        setState(() {
          resultadoBolivares = montoDolar * tasaBcv!;
          _bolivaresController.text = resultadoBolivares != null ? resultadoBolivares!.toStringAsFixed(2) : ''; // Formatear con 2 decimales();
        });
      }
    }
  }

  void calcularConversionInversa() {
    if (_bolivaresController.text.isNotEmpty && tasaBcv != null) {
      final montoBolivares = double.tryParse(_bolivaresController.text);
      if (montoBolivares != null) {
        setState(() {
          resultadoDolares = montoBolivares / tasaBcv!;
          _dolarController.text = resultadoDolares != null ? resultadoDolares!.toStringAsFixed(2) : '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversor Dólar BCV'),
        elevation: 2,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tarjeta con la tasa del BCV
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    const Text(
                      'Tasa Oficial BCV',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (isLoading)
                      const CircularProgressIndicator()
                    else if (error != null)
                      Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      )
                    else
                      Text(
                        '1 USD = ${tasaBcv!.toStringAsFixed(2)} Bs',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            
            // Calculadora de conversión
            const Text(
              'Calculadora de Conversión',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _dolarController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Dólares (USD)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
              ),
              onChanged: (_) => calcularConversion(),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _bolivaresController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Bolívares (Bs)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.money),
                // hintText: resultadoBolivares != null ? resultadoBolivares!.toStringAsFixed(2) : '',
              ),
              onChanged: (_) => calcularConversionInversa(),
            ),
            const SizedBox(height: 20),
            if (resultadoBolivares != null)
              // Card(
              //   color: Colors.blue.shade50,
              //   child: Padding(
              //     padding: const EdgeInsets.all(16.0),
              //     child: Column(
              //       children: [
              //         const Text(
              //           'Resultado en Bolívares',
              //           style: TextStyle(fontSize: 16),
              //         ),
              //         const SizedBox(height: 8),
              //         Text(
              //           'Bs ${resultadoBolivares!.toStringAsFixed(2)}',
              //           style: const TextStyle(
              //             fontSize: 32,
              //             fontWeight: FontWeight.bold,
              //             color: Colors.blue,
              //           ),
              //         ),
              //       ],
              //     ),
              //   ),
              // ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: obtenerTasaBcv,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar Tasa'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _dolarController.dispose();
    super.dispose();
  }
}
