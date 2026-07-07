import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'splitting_algorithm.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const FairSplitApp());
}

class FairSplitApp extends StatelessWidget {
  const FairSplitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fair Split',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF326385),
          surface: const Color(0xFFF9F9F9),
        ),
        textTheme: GoogleFonts.interTextTheme(),
      ),
      home: const MainCanvas(),
    );
  }
}

// Global App State
class AppState extends ChangeNotifier {
  // Config state
  String apiKey = '';
  
  // Current Active Split State
  String receiptId = '';
  Receipt receipt = Receipt(subtotal: 0, serviceChargeAmount: 0, taxRate: 0.15, taxAmount: 0, total: 0);
  String merchantName = '';
  String? imagePath;
  List<LineItem> lineItems = [];
  List<Participant> activeParticipants = [];
  List<ReceiptUnit> units = [];
  
  // History / Persistent Storage
  List<Participant> recentParticipants = [];
  List<Map<String, dynamic>> recentSplits = [];

  AppState() {
    _loadFromPrefs();
  }

  // Load persistent configurations and history
  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load API Key
    apiKey = prefs.getString('gemini_api_key') ?? '';
    
    // If not in preferences, try reading from assets/env.json
    if (apiKey.isEmpty) {
      try {
        final jsonStr = await rootBundle.loadString('assets/env.json');
        final data = jsonDecode(jsonStr);
        apiKey = data['GEMINI_API_KEY'] ?? '';
        if (apiKey.isNotEmpty) {
          await prefs.setString('gemini_api_key', apiKey);
        }
      } catch (_) {
        // Asset file missing or invalid (this is fine, user will be prompted)
      }
    }
    
    // Load Recent Participants
    final participantsJson = prefs.getString('recent_participants');
    if (participantsJson != null) {
      final List<dynamic> decoded = jsonDecode(participantsJson);
      recentParticipants = decoded.map((p) => Participant.fromJson(p)).toList();
    }
    
    // Load Recent Splits
    final splitsJson = prefs.getString('recent_splits');
    if (splitsJson != null) {
      recentSplits = List<Map<String, dynamic>>.from(jsonDecode(splitsJson));
    }
    
    notifyListeners();
  }

  // Save configurations and history
  Future<void> _saveRecentParticipants() async {
    final prefs = await SharedPreferences.getInstance();
    final data = recentParticipants.map((p) => p.toJson()).toList();
    await prefs.setString('recent_participants', jsonEncode(data));
  }

  Future<void> _saveRecentSplits() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('recent_splits', jsonEncode(recentSplits));
  }

  Future<void> saveApiKey(String key) async {
    apiKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', key);
    notifyListeners();
  }

  // Actions
  void setReceiptDetails({
    String? name,
    double? subtotal,
    double? serviceCharge,
    double? taxRate,
    double? taxAmount,
    double? total,
  }) {
    if (name != null) merchantName = name;
    receipt = Receipt(
      subtotal: subtotal ?? receipt.subtotal,
      serviceChargeAmount: serviceCharge ?? receipt.serviceChargeAmount,
      taxRate: taxRate ?? receipt.taxRate,
      taxAmount: taxAmount ?? receipt.taxAmount,
      total: total ?? receipt.total,
    );
    notifyListeners();
  }

  void setLineItems(List<LineItem> items) {
    lineItems = items;
    _recalculateTotalsFromItems();
  }

  void addLineItem(String description, int quantity, double unitPrice) {
    final newItem = LineItem(
      id: Random().nextInt(100000).toString(),
      description: description,
      quantity: quantity,
      unitPrice: unitPrice,
      amount: quantity * unitPrice,
    );
    lineItems.add(newItem);
    _recalculateTotalsFromItems();
  }

  void updateLineItem(String id, String description, int quantity, double unitPrice) {
    final index = lineItems.indexWhere((item) => item.id == id);
    if (index > -1) {
      lineItems[index] = LineItem(
        id: id,
        description: description,
        quantity: quantity,
        unitPrice: unitPrice,
        amount: quantity * unitPrice,
      );
      _recalculateTotalsFromItems();
    }
  }

  void deleteLineItem(String id) {
    lineItems.removeWhere((item) => item.id == id);
    _recalculateTotalsFromItems();
  }

  void _recalculateTotalsFromItems() {
    final double subtotal = lineItems.fold(0.0, (sum, item) => sum + item.amount);
    final double serviceCharge = (subtotal * 0.1).roundToPlaces(2);
    final double taxAmount = ((subtotal + serviceCharge) * receipt.taxRate).roundToPlaces(2);
    final double total = subtotal + serviceCharge + taxAmount;

    receipt = Receipt(
      subtotal: subtotal,
      serviceChargeAmount: serviceCharge,
      taxRate: receipt.taxRate,
      taxAmount: taxAmount,
      total: total,
    );
    notifyListeners();
  }

  // Participants Actions
  void addActiveParticipant(String firstName, String? lastName) {
    final id = Random().nextInt(100000).toString();
    final p = Participant(id: id, firstName: firstName, lastName: lastName);
    activeParticipants.add(p);
    
    // Add or update recent
    final existsIdx = recentParticipants.indexWhere(
        (rp) => rp.firstName.toLowerCase() == firstName.toLowerCase() && 
                rp.lastName?.toLowerCase() == lastName?.toLowerCase());
                
    if (existsIdx > -1) {
      // Move to top of list
      final existing = recentParticipants.removeAt(existsIdx);
      recentParticipants.insert(0, existing);
    } else {
      recentParticipants.insert(0, p);
    }
    
    _saveRecentParticipants();
    notifyListeners();
  }

  void toggleRecentParticipant(Participant rp) {
    final isActive = activeParticipants.any((ap) => ap.id == rp.id);
    if (isActive) {
      // Remove from active
      activeParticipants.removeWhere((ap) => ap.id == rp.id);
      
      // Clean up assignments
      for (var i = 0; i < units.length; i++) {
        final assignments = units[i].assignments.where((a) => a.participantId != rp.id).toList();
        // Recalculate equal shares
        final updated = assignments.map((a) => UnitAssignment(
          participantId: a.participantId,
          share: assignments.isNotEmpty ? 1.0 / assignments.length : 0.0
        )).toList();
        
        units[i] = ReceiptUnit(
          id: units[i].id,
          description: units[i].description,
          unitPrice: units[i].unitPrice,
          assignments: updated
        );
      }
    } else {
      // Add to active
      activeParticipants.add(rp);
      
      // Re-order recent to make this most recent
      recentParticipants.removeWhere((p) => p.id == rp.id);
      recentParticipants.insert(0, rp);
      _saveRecentParticipants();
    }
    notifyListeners();
  }

  void removeActiveParticipant(String id) {
    activeParticipants.removeWhere((ap) => ap.id == id);
    
    // Clean up assignments
    for (var i = 0; i < units.length; i++) {
      final assignments = units[i].assignments.where((a) => a.participantId != id).toList();
      final updated = assignments.map((a) => UnitAssignment(
        participantId: a.participantId,
        share: assignments.isNotEmpty ? 1.0 / assignments.length : 0.0
      )).toList();
      
      units[i] = ReceiptUnit(
        id: units[i].id,
        description: units[i].description,
        unitPrice: units[i].unitPrice,
        assignments: updated
      );
    }
    notifyListeners();
  }

  // Assignments Actions
  void initializeUnits() {
    final List<ReceiptUnit> generated = [];
    for (final item in lineItems) {
      final qty = item.quantity;
      if (qty <= 1) {
        // preserve existing if matching ID exists
        final existing = units.firstWhere((u) => u.id == item.id, orElse: () => ReceiptUnit(id: '', description: '', unitPrice: 0, assignments: []));
        generated.add(ReceiptUnit(
          id: item.id,
          description: item.description,
          unitPrice: item.unitPrice,
          assignments: existing.id.isNotEmpty ? existing.assignments : [],
        ));
      } else {
        for (int i = 0; i < qty; i++) {
          final unitId = '${item.id}_unit_$i';
          final existing = units.firstWhere((u) => u.id == unitId, orElse: () => ReceiptUnit(id: '', description: '', unitPrice: 0, assignments: []));
          generated.add(ReceiptUnit(
            id: unitId,
            description: '${item.description} (${i + 1}/$qty)',
            unitPrice: item.unitPrice,
            assignments: existing.id.isNotEmpty ? existing.assignments : [],
          ));
        }
      }
    }
    units = generated;
    notifyListeners();
  }

  void assignUnitParticipant(String unitId, String participantId) {
    final idx = units.indexWhere((u) => u.id == unitId);
    if (idx > -1) {
      final unit = units[idx];
      final isAssigned = unit.assignments.any((a) => a.participantId == participantId);
      List<UnitAssignment> assignments = [];

      if (isAssigned) {
        assignments = unit.assignments.where((a) => a.participantId != participantId).toList();
      } else {
        assignments = [...unit.assignments, UnitAssignment(participantId: participantId, share: 0.0)];
      }

      // Recalculate equal shares
      final updated = assignments.map((a) => UnitAssignment(
        participantId: a.participantId,
        share: assignments.isNotEmpty ? 1.0 / assignments.length : 0.0
      )).toList();

      units[idx] = ReceiptUnit(
        id: unit.id,
        description: unit.description,
        unitPrice: unit.unitPrice,
        assignments: updated,
      );
      notifyListeners();
    }
  }

  void setUnitCustomShares(String unitId, List<UnitAssignment> customShares) {
    final idx = units.indexWhere((u) => u.id == unitId);
    if (idx > -1) {
      units[idx] = ReceiptUnit(
        id: units[idx].id,
        description: units[idx].description,
        unitPrice: units[idx].unitPrice,
        assignments: customShares,
      );
      notifyListeners();
    }
  }

  void saveCurrentSplit() {
    final results = computeSplit(receipt, activeParticipants, units);
    
    final resultsData = results.map((res) {
      final p = activeParticipants.firstWhere((ap) => ap.id == res.participantId);
      final name = p.lastName != null ? '${p.firstName} ${p.lastName}' : p.firstName;
      return {
        ...res.toJson(),
        'participantName': name,
      };
    }).toList();

    final newSplit = {
      'id': receiptId.isNotEmpty ? receiptId : Random().nextInt(100000).toString(),
      'merchantName': merchantName.isNotEmpty ? merchantName : 'Unnamed Split',
      'date': '${_getMonthName(DateTime.now().month)} ${DateTime.now().day}, ${DateTime.now().year}',
      'total': receipt.total.ceil(),
      'participantsCount': activeParticipants.length,
      'results': resultsData,
    };

    recentSplits.insert(0, newSplit);
    _saveRecentSplits();
    notifyListeners();
  }

  void resetCurrentSplit() {
    receiptId = '';
    receipt = Receipt(subtotal: 0, serviceChargeAmount: 0, taxRate: 0.15, taxAmount: 0, total: 0);
    merchantName = '';
    imagePath = null;
    lineItems = [];
    activeParticipants = [];
    units = [];
    notifyListeners();
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }
}

extension DoubleRounding on double {
  double roundToPlaces(int places) {
    double mod = pow(10.0, places).toDouble();
    return ((this * mod).round().toDouble() / mod);
  }
}

class LineItem {
  final String id;
  final String description;
  final int quantity;
  final double unitPrice;
  final double amount;

  LineItem({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.amount,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'amount': amount,
      };

  factory LineItem.fromJson(Map<String, dynamic> json) => LineItem(
        id: json['id'] as String,
        description: json['description'] as String,
        quantity: json['quantity'] as int,
        unitPrice: (json['unitPrice'] as num).toDouble(),
        amount: (json['amount'] as num).toDouble(),
      );
}

// Global state handle
final appState = AppState();

// Core Navigation and layout component
class MainCanvas extends StatefulWidget {
  const MainCanvas({super.key});

  @override
  State<MainCanvas> createState() => _MainCanvasState();
}

class _MainCanvasState extends State<MainCanvas> {
  String _activeScreen = 'home'; // home, capture, review, participants, assign, summary
  bool _loading = false;
  String? _errorMsg;

  // Active Assignment Index (for item-by-item selection)
  int _activeUnitIndex = 0;
  // Expanded card on Summary Screen
  String? _expandedParticipantId;

  // Controllers for text inputs
  final _apiKeyController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    appState.addListener(_onStateChange);
  }

  @override
  void dispose() {
    appState.removeListener(_onStateChange);
    _apiKeyController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  // Launch camera snapshot
  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    try {
      final XFile? file = await picker.pickImage(source: source);
      if (file == null) {
        setState(() {
          _loading = false;
        });
        return;
      }

      appState.imagePath = file.path;

      // Check if API key is entered
      if (appState.apiKey.trim().isEmpty) {
        setState(() {
          _loading = false;
        });
        _showApiKeyDialog(message: "A Gemini API Key is required to scan receipts automatically. Please enter your key below.");
        return;
      }

      await _parseReceiptOCR(file.path);
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMsg = "An error occurred while picking/capturing the image: $e";
      });
    }
  }

  // Parse receipt using local google_generative_ai library
  Future<void> _parseReceiptOCR(String path) async {
    setState(() {
      _loading = true;
    });

    try {
      final file = File(path);
      final bytes = await file.readAsBytes();

      // Configure Gemini Model Client
      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: appState.apiKey,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
        ),
      );

      const systemPrompt = '''
You are a receipt parsing assistant. You extract structured data from Ethiopian ERCA fiscal receipts. These receipts follow standard layout conventions: line items, followed by SUBTOTAL, then Service Chrg (Service Charge), then TXBL1 (Taxable Base), then TAX1 15% (VAT), and finally TOTAL.
Examine the image carefully and output a JSON object containing the parsed information.
Your response MUST be a single valid JSON object matching this schema:
{
  "merchantName": "string",
  "subtotal": double,
  "serviceChargeAmount": double,
  "taxRate": double,
  "taxAmount": double,
  "total": double,
  "lineItems": [
    {
      "description": "string",
      "quantity": double,
      "unitPrice": double,
      "amount": double
    }
  ]
}
Instructions:
1. Extract the merchant/restaurant name if visible.
2. For each line item, extract the description, quantity, unitPrice (unit price), and amount. If quantity or unit price is missing, calculate it (amount = quantity * unitPrice).
3. If an item is unreadable, return null or skip it. Do not invent line items.
4. Extract the exact subtotal, service charge amount (printed as Service Chrg), taxRate (usually 0.15), taxAmount (printed as TAX1 15%), and total.
''';

      final content = [
        Content.multi([
          TextPart("Parse this receipt according to the instructions system instructions: \n$systemPrompt"),
          DataPart('image/jpeg', bytes),
        ])
      ];

      final response = await model.generateContent(content);
      final responseText = response.text;
      
      if (responseText == null) {
        throw Exception("Failed to get response from Gemini Vision API.");
      }

      final Map<String, dynamic> data = jsonDecode(responseText);

      // Validate and parse raw properties
      final double subtotal = (data['subtotal'] as num?)?.toDouble() ?? 0.0;
      final double serviceCharge = (data['serviceChargeAmount'] as num?)?.toDouble() ?? 0.0;
      final double taxRate = (data['taxRate'] as num?)?.toDouble() ?? 0.15;
      final double taxAmount = (data['taxAmount'] as num?)?.toDouble() ?? 0.0;
      final double total = (data['total'] as num?)?.toDouble() ?? 0.0;
      
      appState.setReceiptDetails(
        name: data['merchantName'] as String? ?? 'ERCA Receipt',
        subtotal: subtotal,
        serviceCharge: serviceCharge,
        taxRate: taxRate,
        taxAmount: taxAmount,
        total: total,
      );

      final List<dynamic> itemsJson = data['lineItems'] as List<dynamic>? ?? [];
      final List<LineItem> parsedItems = [];
      for (final item in itemsJson) {
        final description = item['description'] as String? ?? 'Unparsed Item';
        final qty = (item['quantity'] as num?)?.toInt() ?? 1;
        final price = (item['unitPrice'] as num?)?.toDouble() ?? 0.0;
        parsedItems.add(LineItem(
          id: Random().nextInt(100000).toString(),
          description: description,
          quantity: qty,
          unitPrice: price,
          amount: qty * price,
        ));
      }

      appState.setLineItems(parsedItems);
      setState(() {
        _loading = false;
        _activeScreen = 'review';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMsg = "Couldn't read this receipt clearly. Please verify your API Key, retake the photo, or enter items manually.\n\nDetails: $e";
      });
    }
  }

  // Load mock test receipt
  void _loadMockReceipt() {
    appState.resetCurrentSplit();
    appState.setReceiptDetails(
      name: 'Maleda Restaurant',
      subtotal: 2227.69,
      serviceCharge: 82.40,
      taxRate: 0.15,
      taxAmount: 346.51,
      total: 2656.60,
    );
    appState.setLineItems([
      LineItem(id: 'item_1', description: 'Macchiato', quantity: 2, unitPrice: 45.00, amount: 90.00),
      LineItem(id: 'item_2', description: 'Fasting Firfir', quantity: 1, unitPrice: 150.00, amount: 150.00),
      LineItem(id: 'item_3', description: 'Shiro Tegabino', quantity: 3, unitPrice: 180.00, amount: 540.00),
      LineItem(id: 'item_4', description: 'Bottled Water (L)', quantity: 2, unitPrice: 30.00, amount: 60.00),
      LineItem(id: 'item_5', description: 'Margherita Pizza Large', quantity: 1, unitPrice: 1387.69, amount: 1387.69),
    ]);
    setState(() {
      _errorMsg = null;
      _activeScreen = 'review';
    });
  }

  void _skipToManual() {
    appState.resetCurrentSplit();
    appState.setReceiptDetails(
      name: 'Manual Receipt',
      subtotal: 0.0,
      serviceCharge: 0.0,
      taxRate: 0.15,
      taxAmount: 0.0,
      total: 0.0,
    );
    setState(() {
      _errorMsg = null;
      _activeScreen = 'review';
    });
  }

  // API Key entry dialog box
  void _showApiKeyDialog({String? message}) {
    _apiKeyController.text = appState.apiKey;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Gemini API Key Settings', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message != null) ...[
                Text(message, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 12),
              ],
              const Text('Enter API Key (saved locally on your phone):', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _apiKeyController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'AIzaSy...',
                  filled: true,
                  fillColor: const Color(0xFFF2F2F7),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                appState.saveApiKey(_apiKeyController.text.trim());
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Save'),
            )
          ],
        );
      },
    );
  }

  // Item editor dialog
  void _showItemEditDialog(LineItem item) {
    final descCtrl = TextEditingController(text: item.description);
    final qtyCtrl = TextEditingController(text: item.quantity.toString());
    final priceCtrl = TextEditingController(text: item.unitPrice.toString());

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Edit Item', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Description', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 4),
                TextField(
                  controller: descCtrl,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF2F2F7),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Quantity', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: qtyCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFFF2F2F7),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Price (ETB)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: priceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFFF2F2F7),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                appState.deleteLineItem(item.id);
                Navigator.pop(context);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                final qty = int.tryParse(qtyCtrl.text) ?? 1;
                final price = double.tryParse(priceCtrl.text) ?? 0.0;
                appState.updateLineItem(item.id, descCtrl.text, qty, price);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Save'),
            )
          ],
        );
      },
    );
  }

  // Adding Item Dialog
  void _showAddItemDialog() {
    final descCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Add Missing Item', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Description', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 4),
                TextField(
                  controller: descCtrl,
                  decoration: InputDecoration(
                    hintText: 'e.g. Shiro Tegabino',
                    filled: true,
                    fillColor: const Color(0xFFF2F2F7),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Quantity', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: qtyCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFFF2F2F7),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Unit Price (ETB)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: priceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              hintText: '180.00',
                              filled: true,
                              fillColor: const Color(0xFFF2F2F7),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                if (descCtrl.text.trim().isEmpty) return;
                final qty = int.tryParse(qtyCtrl.text) ?? 1;
                final price = double.tryParse(priceCtrl.text) ?? 0.0;
                appState.addLineItem(descCtrl.text.trim(), qty, price);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Add'),
            )
          ],
        );
      },
    );
  }

  // Dialog box for Service charge and Tax rates
  void _showFeesEditDialog(String type) {
    final double initialVal = type == 'service' ? appState.receipt.serviceChargeAmount : appState.receipt.taxRate;
    final valCtrl = TextEditingController(text: initialVal.toString());

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            type == 'service' ? 'Edit Service Charge' : 'Edit VAT Rate',
            style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                type == 'service' ? 'Absolute Amount (ETB)' : 'Tax Rate (fraction: e.g. 0.15 for 15%)',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: valCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF2F2F7),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                final double val = double.tryParse(valCtrl.text) ?? 0.0;
                if (type == 'service') {
                  final newTax = ((appState.receipt.subtotal + val) * appState.receipt.taxRate).roundToPlaces(2);
                  final newTotal = appState.receipt.subtotal + val + newTax;
                  appState.setReceiptDetails(
                    serviceCharge: val,
                    taxAmount: newTax,
                    total: newTotal,
                  );
                } else {
                  final newTax = ((appState.receipt.subtotal + appState.receipt.serviceChargeAmount) * val).roundToPlaces(2);
                  final newTotal = appState.receipt.subtotal + appState.receipt.serviceChargeAmount + newTax;
                  appState.setReceiptDetails(
                    taxRate: val,
                    taxAmount: newTax,
                    total: newTotal,
                  );
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Save'),
            )
          ],
        );
      },
    );
  }

  // Proportional weight allocation dialog
  void _showCustomSharesDialog(ReceiptUnit unit) {
    // We hold weights in text controllers
    final Map<String, TextEditingController> ctrls = {};
    for (final assignment in unit.assignments) {
      final currentWeight = assignment.share > 0 ? (assignment.share * 100).round() : 0;
      ctrls[assignment.participantId] = TextEditingController(text: currentWeight.toString());
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Custom Split Weights', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  'Adjust weight values to split ${unit.description} (${unit.unitPrice.toStringAsFixed(2)} ETB) proportionally.',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ...appState.activeParticipants
                    .where((p) => unit.assignments.any((a) => a.participantId == p.id))
                    .map((p) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(p.firstName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Row(
                          children: [
                            SizedBox(
                              width: 80,
                              height: 40,
                              child: TextField(
                                controller: ctrls[p.id],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: const Color(0xFFF2F2F7),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text('pts', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        )
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                double sumWeights = 0;
                final List<MapEntry<String, double>> weightVals = [];
                
                for (final assignment in unit.assignments) {
                  final double w = double.tryParse(ctrls[assignment.participantId]?.text ?? '1') ?? 1.0;
                  weightVals.add(MapEntry(assignment.participantId, w));
                  sumWeights += w;
                }

                if (sumWeights <= 0) {
                  alert('Sum of weights must be greater than 0.');
                  return;
                }

                final List<UnitAssignment> shares = weightVals.map((entry) {
                  return UnitAssignment(
                    participantId: entry.key,
                    share: entry.value / sumWeights,
                  );
                }).toList();

                appState.setUnitCustomShares(unit.id, shares);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Apply'),
            )
          ],
        );
      },
    );
  }

  void alert(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // Formatted copy summaries
  String _getShareText() {
    final splitResults = computeSplit(appState.receipt, appState.activeParticipants, appState.units);
    final targetTotal = appState.receipt.total.ceil();
    
    String text = "🧾 *Fair Split Breakdown — ${appState.merchantName}*\n";
    text += "📅 Date: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}\n";
    text += "💰 Total Bill: $targetTotal ETB (reconciled)\n";
    text += "---------------------------\n";
    
    for (final res in splitResults) {
      final p = appState.activeParticipants.firstWhere((ap) => ap.id == res.participantId);
      final name = p.lastName != null ? '${p.firstName} ${p.lastName}' : p.firstName;
      
      final pUnits = appState.units.where((u) => u.assignments.any((a) => a.participantId == res.participantId));
      final itemsText = pUnits.map((u) {
        final assign = u.assignments.firstWhere((a) => a.participantId == res.participantId);
        final sharePct = assign.share < 1.0 ? ' (${(assign.share * 100).round()}%)' : '';
        return '- ${u.description}$sharePct: ${(u.unitPrice * assign.share).toStringAsFixed(2)} ETB';
      }).join('\n');

      text += "👤 *$name* owes *${res.totalOwed.toStringAsFixed(2)} ETB*\n";
      text += "  Items Subtotal: ${res.itemSubtotal.toStringAsFixed(2)} ETB\n";
      text += "  Service Charge Share: ${res.serviceChargeShare.toStringAsFixed(2)} ETB\n";
      text += "  VAT (15%) Share: ${res.taxShare.toStringAsFixed(2)} ETB\n";
      if (itemsText.isNotEmpty) {
        text += "  Items ordered:\n$itemsText\n";
      }
      text += "\n";
    }
    text += "Generated with Fair Split App.";
    return text;
  }

  @override
  Widget build(BuildContext context) {
    // Simulated mobile layout wrapper.
    // If screens size is larger, simulate a centered card
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: Center(
        child: Container(
          width: isDesktop ? 400 : double.infinity,
          height: isDesktop ? 840 : double.infinity,
          margin: isDesktop ? const EdgeInsets.symmetric(vertical: 24) : EdgeInsets.zero,
          decoration: isDesktop
              ? BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 30,
                      offset: const Offset(0, 15),
                    )
                  ],
                  border: Border.all(color: Colors.grey.shade300, width: 2),
                )
              : null,
          child: ClipRRect(
            borderRadius: isDesktop ? BorderRadius.circular(38) : BorderRadius.zero,
            child: Scaffold(
              backgroundColor: const Color(0xFFF9F9F9),
              body: _buildActiveScreen(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveScreen() {
    switch (_activeScreen) {
      case 'home':
        return _buildHomeScreen();
      case 'capture':
        return _buildCaptureScreen();
      case 'review':
        return _buildReviewScreen();
      case 'participants':
        return _buildParticipantsScreen();
      case 'assign':
        return _buildAssignScreen();
      case 'summary':
        return _buildSummaryScreen();
      default:
        return _buildHomeScreen();
    }
  }

  // =========================================================================
  // SCREEN 1: HOME
  // =========================================================================
  Widget _buildHomeScreen() {
    return Column(
      children: [
        // Header
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.settings, color: Colors.black),
                  onPressed: () => _showApiKeyDialog(),
                ),
                Text('Fair Split', style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
                IconButton(
                  icon: const Icon(Icons.more_horiz, color: Colors.grey),
                  onPressed: () {},
                )
              ],
            ),
          ),
        ),
        
        // Home contents
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            physics: const BouncingScrollPhysics(),
            children: [
              // Hero section
              Container(
                height: 320,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFE1EEF9),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: const Color(0xFFD0E0EE)),
                ),
                child: Stack(
                  children: [
                    // Background placeholder shape
                    Positioned(
                      right: -30,
                      top: -30,
                      child: Opacity(
                        opacity: 0.05,
                        child: Icon(Icons.restaurant, size: 240, color: Colors.blue.shade900),
                      ),
                    ),
                    
                    // Card Contents
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('Dinner with friends', style: GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
                          const SizedBox(height: 4),
                          const Text('Split bills proportionally. Service charges and VAT are shared without awkward math.', style: TextStyle(fontSize: 13, color: Colors.black87)),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () {
                              appState.resetCurrentSplit();
                              setState(() {
                                _activeScreen = 'capture';
                              });
                            },
                            icon: const Icon(Icons.add_circle, color: Colors.white, size: 20),
                            label: const Text('New Split', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                            ),
                          )
                        ],
                      ),
                    )
                  ],
                ),
              ),
              
              const SizedBox(height: 24),

              // Recent Splits Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Recent Splits', style: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.bold)),
                  if (appState.recentSplits.isNotEmpty)
                    TextButton(
                      onPressed: () {},
                      child: const Text('View All', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                    )
                ],
              ),
              const SizedBox(height: 12),

              // History list
              if (appState.recentSplits.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.receipt_long, size: 40, color: Colors.black26),
                      SizedBox(height: 12),
                      Text('No splits yet', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
                      SizedBox(height: 4),
                      Text('Calculated receipts will appear here.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                )
              else
                ...appState.recentSplits.map((split) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFEEEEEE)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFE1EEF9),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.restaurant, size: 18, color: Color(0xFF326385)),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(split['merchantName'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    const SizedBox(height: 2),
                                    Text('${split['date']} • ${split['participantsCount']} people', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  ],
                                )
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${split['total']} ETB', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF28CD41).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(9999),
                                  ),
                                  child: const Text('Settled', style: TextStyle(fontSize: 9, color: Color(0xFF28CD41), fontWeight: FontWeight.bold)),
                                )
                              ],
                            )
                          ],
                        )
                      ],
                    ),
                  );
                }),
              
              const SizedBox(height: 96), // Spacer for bottom navigation
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // SCREEN 2: SCAN/CAPTURE
  // =========================================================================
  Widget _buildCaptureScreen() {
    return Container(
      color: const Color(0xFF0F0F13),
      child: Column(
        children: [
          // Header
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => setState(() => _activeScreen = 'home'),
                  ),
                  const Text('Scan ERCA Receipt', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),
          
          // Camera viewport simulation
          Expanded(
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Alignment box
                  Container(
                    width: 260,
                    height: 380,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.3), width: 2, style: BorderStyle.solid),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.document_scanner, size: 40, color: Colors.white.withOpacity(0.8)),
                          const SizedBox(height: 12),
                          const Text(
                            'Fit the receipt in frame — good lighting helps. Only ERCA standard receipts are supported.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // loading indicator spinner
                  if (_loading)
                    Container(
                      color: Colors.black87,
                      width: double.infinity,
                      height: double.infinity,
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.blue),
                          SizedBox(height: 16),
                          Text('Reading receipt...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text('OCR parsing via Gemini Vision', style: TextStyle(color: Color(0x80FFFFFF), fontSize: 11)),
                        ],
                      ),
                    ),
                    
                  // error display
                  if (_errorMsg != null)
                    Container(
                      color: const Color(0xE6000000),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error, color: Colors.red, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            _errorMsg!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton(
                                onPressed: _skipToManual,
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                                child: const Text('Enter Manually'),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                onPressed: () => setState(() => _errorMsg = null),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade800, foregroundColor: Colors.white),
                                child: const Text('Try Again'),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          // Action Buttons
          Padding(
            padding: const EdgeInsets.only(bottom: 32, left: 24, right: 24),
            child: Column(
              children: [
                OutlinedButton.icon(
                  onPressed: _loadMockReceipt,
                  icon: const Icon(Icons.bolt, color: Color(0xFF60A5FA), size: 18),
                  label: const Text('Use Mock Receipt (Fast Testing)', style: TextStyle(color: Color(0xFF60A5FA), fontSize: 12, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: const Color(0xFF60A5FA).withOpacity(0.3)),
                    backgroundColor: const Color(0xFF60A5FA).withOpacity(0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard, color: Colors.white, size: 24),
                      onPressed: _skipToManual,
                    ),
                    
                    // Native Shutter
                    GestureDetector(
                      onTap: () => _pickImage(ImageSource.camera),
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(4),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF0F0F13), width: 3),
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),

                    IconButton(
                      icon: const Icon(Icons.photo_library, color: Colors.white, size: 24),
                      onPressed: () => _pickImage(ImageSource.gallery),
                    ),
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  // =========================================================================
  // SCREEN 3: CONFIRM DETAILS & REVIEW
  // =========================================================================
  Widget _buildReviewScreen() {
    return Column(
      children: [
        // Header
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: () => setState(() => _activeScreen = 'capture'),
                ),
                Text('Confirm Details', style: GoogleFonts.playfairDisplay(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(width: 48),
              ],
            ),
          ),
        ),
        
        // Editable list
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            physics: const BouncingScrollPhysics(),
            children: [
              const Text(
                'Tap any item to edit details. Ensure quantities and unit prices match your physical receipt.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),

              // Merchant input card
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFEEEEEE)),
                ),
                child: TextField(
                  controller: TextEditingController(text: appState.merchantName),
                  onChanged: (val) => appState.merchantName = val.trim(),
                  decoration: const InputDecoration(
                    labelText: 'Restaurant / Merchant',
                    labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    border: InputBorder.none,
                  ),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),

              // Items container
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFEEEEEE)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 5))
                  ]
                ),
                child: Column(
                  children: [
                    // Table Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.only(topLeft: Radius.circular(27), topRight: Radius.circular(27)),
                      ),
                      child: const Row(
                        children: [
                          Expanded(flex: 3, child: Text('ITEM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey))),
                          Expanded(flex: 1, child: Center(child: Text('QTY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)))),
                          Expanded(flex: 2, child: Align(alignment: Alignment.centerRight, child: Text('TOTAL (ETB)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)))),
                        ],
                      ),
                    ),
                    
                    // Table Rows
                    if (appState.lineItems.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Text('No items added yet.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: appState.lineItems.length,
                        separatorBuilder: (context, i) => const Divider(height: 1, color: Color(0xFFEEEEEE)),
                        itemBuilder: (context, i) {
                          final item = appState.lineItems[i];
                          return InkWell(
                            onTap: () => _showItemEditDialog(item),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item.description, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        const SizedBox(height: 2),
                                        Text('${item.unitPrice.toStringAsFixed(2)} ea', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(8)),
                                        child: Text(item.quantity.toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Text(item.amount.toStringAsFixed(2), style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 13)),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.edit, size: 12, color: Colors.grey),
                                      ],
                                    ),
                                  )
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                    // Add Missing Item Button
                    GestureDetector(
                      onTap: _showAddItemDialog,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: Color(0xFFEEEEEE), style: BorderStyle.solid)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add, size: 16, color: Color(0xFF326385)),
                            SizedBox(width: 6),
                            Text('Add Missing Item', style: TextStyle(color: Color(0xFF326385), fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),

              // Fees section card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFEEEEEE)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Subtotal', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text('${appState.receipt.subtotal.toStringAsFixed(2)} ETB', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => _showFeesEditDialog('service'),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Text('Service Charge', style: TextStyle(fontSize: 12, color: Colors.grey, decoration: TextDecoration.underline, decorationColor: Colors.grey, decorationStyle: TextDecorationStyle.dashed)),
                              SizedBox(width: 4),
                              Icon(Icons.edit, size: 10, color: Colors.grey),
                            ],
                          ),
                          Text('${appState.receipt.serviceChargeAmount.toStringAsFixed(2)} ETB', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => _showFeesEditDialog('tax'),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text('VAT (${(appState.receipt.taxRate * 100).round()}%)', style: const TextStyle(fontSize: 12, color: Colors.grey, decoration: TextDecoration.underline, decorationColor: Colors.grey, decorationStyle: TextDecorationStyle.dashed)),
                              const SizedBox(width: 4),
                              const Icon(Icons.edit, size: 10, color: Colors.grey),
                            ],
                          ),
                          Text('${appState.receipt.taxAmount.toStringAsFixed(2)} ETB', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    ),
                    const Divider(height: 24, color: Color(0xFFEEEEEE)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Target Bill (Reconciled)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${appState.receipt.total.ceil().toStringAsFixed(2)} ETB',
                              style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
                            ),
                            Text('Actual: ${appState.receipt.total.toStringAsFixed(2)} ETB', style: const TextStyle(fontSize: 9, color: Colors.grey)),
                          ],
                        )
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 120),
            ],
          ),
        ),
        
        // Fixed bottom Proceed action
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: ElevatedButton.icon(
            onPressed: () {
              if (appState.lineItems.isEmpty) {
                alert('Please add at least one item.');
                return;
              }
              setState(() => _activeScreen = 'participants');
            },
            icon: const Text('Proceed to Assign', style: TextStyle(fontWeight: FontWeight.bold)),
            label: const Icon(Icons.arrow_forward, size: 18),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
            ),
          ),
        )
      ],
    );
  }

  // =========================================================================
  // SCREEN 4: CHOOSE PARTICIPANTS
  // =========================================================================
  Widget _buildParticipantsScreen() {
    return Column(
      children: [
        // Header
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: () => setState(() => _activeScreen = 'review'),
                ),
                Text('Participants', style: GoogleFonts.playfairDisplay(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(width: 48),
              ],
            ),
          ),
        ),
        
        // Inputs
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            physics: const BouncingScrollPhysics(),
            children: [
              // Form box
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFEEEEEE)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add New Person', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _firstNameController,
                            decoration: InputDecoration(
                              hintText: 'First Name *',
                              filled: true,
                              fillColor: const Color(0xFFF2F2F7),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: _lastNameController,
                            decoration: InputDecoration(
                              hintText: 'Last Name',
                              filled: true,
                              fillColor: const Color(0xFFF2F2F7),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        if (_firstNameController.text.trim().isEmpty) return;
                        appState.addActiveParticipant(_firstNameController.text.trim(), _lastNameController.text.trim().isNotEmpty ? _lastNameController.text.trim() : null);
                        _firstNameController.clear();
                        _lastNameController.clear();
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Participant', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    )
                  ],
                ),
              ),
              
              const SizedBox(height: 24),

              // Selected for split
              Text('Selected for this split', style: GoogleFonts.playfairDisplay(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xDD000000))),
              const SizedBox(height: 12),
              if (appState.activeParticipants.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F7).withOpacity(0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFEEEEEE), style: BorderStyle.solid),
                  ),
                  child: const Text('No one selected. Add above or choose from recent list.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: appState.activeParticipants.map((p) {
                    final name = p.lastName != null ? '${p.firstName} ${p.lastName!.substring(0, 1)}.' : p.firstName;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE1EEF9),
                        borderRadius: BorderRadius.circular(9999),
                        border: Border.all(color: const Color(0xFF326385).withOpacity(0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 9,
                            backgroundColor: const Color(0xFF326385),
                            child: Text(p.firstName.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 6),
                          Text(name, style: const TextStyle(fontSize: 12, color: Color(0xFF326385), fontWeight: FontWeight.bold)),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => appState.removeActiveParticipant(p.id),
                            child: const Icon(Icons.close, size: 14, color: Color(0xFF326385)),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              
              const SizedBox(height: 24),

              // Recent list
              if (appState.recentParticipants.isNotEmpty) ...[
                Text('Recent People', style: GoogleFonts.playfairDisplay(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xDD000000))),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    mainAxisExtent: 54,
                  ),
                  itemCount: appState.recentParticipants.length,
                  itemBuilder: (context, i) {
                    final rp = appState.recentParticipants[i];
                    final isSelected = appState.activeParticipants.any((ap) => ap.id == rp.id);
                    return InkWell(
                      onTap: () => appState.toggleRecentParticipant(rp),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFE1EEF9) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isSelected ? const Color(0xFF326385) : const Color(0xFFEEEEEE)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: isSelected ? const Color(0xFF326385) : const Color(0xFFF2F2F7),
                              child: Text(
                                rp.firstName.substring(0, 1).toUpperCase(),
                                style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${rp.firstName} ${rp.lastName ?? ""}',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? const Color(0xFF326385) : Colors.black87),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle, size: 16, color: Color(0xFF326385)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
              
              const SizedBox(height: 120),
            ],
          ),
        ),

        // Action
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: ElevatedButton.icon(
            onPressed: appState.activeParticipants.isEmpty
                ? null
                : () {
                    appState.initializeUnits();
                    setState(() {
                      _activeUnitIndex = 0;
                      _activeScreen = 'assign';
                    });
                  },
            icon: const Text('Proceed to Assignment', style: TextStyle(fontWeight: FontWeight.bold)),
            label: const Icon(Icons.arrow_forward, size: 18),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
            ),
          ),
        )
      ],
    );
  }

  // =========================================================================
  // SCREEN 5: ITEM ASSIGNMENT
  // =========================================================================
  Widget _buildAssignScreen() {
    final activeUnit = appState.units[_activeUnitIndex];
    
    return Column(
      children: [
        // Header
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: () => setState(() => _activeScreen = 'participants'),
                ),
                Text('Assign Items', style: GoogleFonts.playfairDisplay(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(width: 48),
              ],
            ),
          ),
        ),

        // Stepper Progress bar
        Container(
          height: 4,
          width: double.infinity,
          color: const Color(0xFFF2F2F7),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: (_activeUnitIndex + 1) / appState.units.length,
            child: Container(
              height: 4,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF60A5FA)]),
              ),
            ),
          ),
        ),
        
        // Main view
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            physics: const BouncingScrollPhysics(),
            children: [
              // Bento Card item details
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFEEEEEE)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 15, offset: const Offset(0, 8))
                  ]
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('ITEM ${_activeUnitIndex + 1} OF ${appState.units.length}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(8)),
                          child: const Text('Unit Price', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(activeUnit.description, style: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Tap assignees below', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text('${activeUnit.unitPrice.toStringAsFixed(2)} ETB', style: const TextStyle(fontFamily: 'Courier', fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    )
                  ],
                ),
              ),
              
              const SizedBox(height: 24),

              // Title assign
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Assign to', style: GoogleFonts.playfairDisplay(fontSize: 14, fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () {
                      final hasAll = appState.activeParticipants.every((p) => activeUnit.assignments.any((a) => a.participantId == p.id));
                      for (final p in appState.activeParticipants) {
                        final exists = activeUnit.assignments.any((a) => a.participantId == p.id);
                        if (hasAll || !exists) {
                          appState.assignUnitParticipant(activeUnit.id, p.id);
                        }
                      }
                    },
                    child: Text(
                      activeUnit.assignments.length == appState.activeParticipants.length ? 'Clear All' : 'Select All',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  )
                ],
              ),
              const SizedBox(height: 12),

              // Grid of active participants
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: 96,
                ),
                itemCount: appState.activeParticipants.length,
                itemBuilder: (context, i) {
                  final p = appState.activeParticipants[i];
                  final assignment = activeUnit.assignments.firstWhere((a) => a.participantId == p.id, orElse: () => UnitAssignment(participantId: '', share: 0));
                  final isSelected = assignment.participantId.isNotEmpty;

                  return InkWell(
                    onTap: () => appState.assignUnitParticipant(activeUnit.id, p.id),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFE1EEF9) : const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isSelected ? const Color(0xFF326385) : Colors.transparent, width: 2),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: isSelected ? const Color(0xFF326385) : Colors.grey.shade400,
                            child: Text(p.firstName.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            p.firstName,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? const Color(0xFF326385) : Colors.black87),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (isSelected && assignment.share < 1.0)
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Text(
                                '${(assignment.share * 100).round()}% (${(activeUnit.unitPrice * assignment.share).toStringAsFixed(1)})',
                                style: const TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold),
                              ),
                            )
                        ],
                      ),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 16),

              // Custom split weights button
              if (activeUnit.assignments.length > 1)
                Center(
                  child: TextButton(
                    onPressed: () => _showCustomSharesDialog(activeUnit),
                    child: const Text('Adjust custom split ratios (weights)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                  ),
                ),
              
              const SizedBox(height: 160),
            ],
          ),
        ),

        // Fixed bottom control
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: const Color(0xFFEEEEEE).withOpacity(0.5))),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: List.generate(appState.units.length, (index) {
                      final hasAssignment = appState.units[index].assignments.isNotEmpty;
                      return Container(
                        margin: const EdgeInsets.only(right: 6),
                        width: index == _activeUnitIndex ? 16 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: index == _activeUnitIndex
                              ? const Color(0xFF326385)
                              : hasAssignment
                                  ? const Color(0xFF28CD41)
                                  : const Color(0xFFEEEEEE),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      '${appState.units.where((u) => u.assignments.isEmpty).length} items remaining',
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                  )
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: _activeUnitIndex == 0
                        ? null
                        : () => setState(() => _activeUnitIndex--),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      side: const BorderSide(color: Color(0xFFEEEEEE)),
                    ),
                    child: const Icon(Icons.arrow_back, color: Colors.black),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _activeUnitIndex < appState.units.length - 1
                        ? ElevatedButton.icon(
                            onPressed: () => setState(() => _activeUnitIndex++),
                            icon: const Text('Next Item', style: TextStyle(fontWeight: FontWeight.bold)),
                            label: const Icon(Icons.arrow_forward, size: 16),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed: () {
                              // If unassigned exists, verify
                              final unassigned = appState.units.where((u) => u.assignments.isEmpty).toList();
                              if (unassigned.isNotEmpty) {
                                showDialog(
                                  context: context,
                                  builder: (context) {
                                    return AlertDialog(
                                      title: const Text('Unassigned Items'),
                                      content: Text('There are ${unassigned.length} items without assignees. Proceeding will distribute their cost evenly to everyone.'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                        ElevatedButton(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            // auto assign unassigned to everyone
                                            for (final u in unassigned) {
                                              for (final p in appState.activeParticipants) {
                                                appState.assignUnitParticipant(u.id, p.id);
                                              }
                                            }
                                            appState.saveCurrentSplit();
                                            setState(() => _activeScreen = 'summary');
                                          },
                                          child: const Text('Continue'),
                                        )
                                      ],
                                    );
                                  },
                                );
                              } else {
                                appState.saveCurrentSplit();
                                setState(() => _activeScreen = 'summary');
                              }
                            },
                            icon: const Text('Calculate Split', style: TextStyle(fontWeight: FontWeight.bold)),
                            label: const Icon(Icons.calculate, size: 16),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF28CD41),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            ),
                          ),
                  )
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // SCREEN 6: SUMMARY BREAKDOWN
  // =========================================================================
  Widget _buildSummaryScreen() {
    final results = computeSplit(appState.receipt, appState.activeParticipants, appState.units);
    
    return Column(
      children: [
        // Header
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: () => setState(() => _activeScreen = 'home'),
                ),
                Text('Breakdown', style: GoogleFonts.playfairDisplay(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(width: 48),
              ],
            ),
          ),
        ),

        // Scroll content
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            physics: const BouncingScrollPhysics(),
            children: [
              // Celebration check mark
              const SizedBox(height: 12),
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                      child: const Icon(Icons.check, color: Colors.white, size: 30),
                    ),
                    const SizedBox(height: 12),
                    Text('All Settled Up!', style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text('Fractional roundings reconciled perfectly.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),

              // Total target card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFEEEEEE)),
                ),
                child: Column(
                  children: [
                    const Text('TOTAL BILL TARGET', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Text(
                      '${appState.receipt.total.ceil().toStringAsFixed(2)} ETB',
                      style: GoogleFonts.playfairDisplay(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFF28CD41).withOpacity(0.1), borderRadius: BorderRadius.circular(99)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.task_alt, size: 12, color: Color(0xFF28CD41)),
                          SizedBox(width: 4),
                          Text('Perfectly Reconciled', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF28CD41))),
                        ],
                      ),
                    )
                  ],
                ),
              ),
              
              const SizedBox(height: 24),

              // Who owes what
              Text('Who owes what', style: GoogleFonts.playfairDisplay(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              // list of participants results cards
              ...results.map((res) {
                final p = appState.activeParticipants.firstWhere((ap) => ap.id == res.participantId);
                final name = p.lastName != null ? '${p.firstName} ${p.lastName}' : p.firstName;
                final isExpanded = _expandedParticipantId == p.id;

                final pUnits = appState.units.where((u) => u.assignments.any((a) => a.participantId == p.id)).toList();

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(23),
                    child: Column(
                      children: [
                        // Clickable title bar
                        InkWell(
                          onTap: () {
                            setState(() {
                              _expandedParticipantId = isExpanded ? null : p.id;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: const Color(0xFFE1EEF9),
                                      child: Text(p.firstName.substring(0, 1).toUpperCase(), style: const TextStyle(color: Color(0xFF326385), fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                        const SizedBox(height: 2),
                                        Text('${pUnits.length} items', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                      ],
                                    )
                                  ],
                                ),
                                Row(
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('${res.totalOwed.toStringAsFixed(2)} ETB', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                        const Text('Owed', style: TextStyle(fontSize: 9, color: Colors.grey)),
                                      ],
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey, size: 18),
                                  ],
                                )
                              ],
                            ),
                          ),
                        ),

                        // Expanded itemized details
                        if (isExpanded)
                          Container(
                            color: const Color(0xFFF2F2F7).withOpacity(0.4),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('ITEMS ORDERED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                                const SizedBox(height: 8),
                                ...pUnits.map((u) {
                                  final assign = u.assignments.firstWhere((a) => a.participantId == p.id);
                                  final sharePct = assign.share < 1.0 ? ' (${(assign.share * 100).round()}%)' : '';
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(child: Text('${u.description}$sharePct', style: const TextStyle(fontSize: 12))),
                                        Text('${(u.unitPrice * assign.share).toStringAsFixed(2)} ETB', style: const TextStyle(fontSize: 12, fontFamily: 'Courier')),
                                      ],
                                    ),
                                  );
                                }),
                                const Divider(height: 20, color: Color(0xFFEEEEEE)),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Items Subtotal', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                    Text('${res.itemSubtotal.toStringAsFixed(2)} ETB', style: const TextStyle(fontSize: 11, fontFamily: 'Courier')),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Service Charge Share', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                    Text('+${res.serviceChargeShare.toStringAsFixed(2)} ETB', style: const TextStyle(fontSize: 11, fontFamily: 'Courier')),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('VAT (15%) Share', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                    Text('+${res.taxShare.toStringAsFixed(2)} ETB', style: const TextStyle(fontSize: 11, fontFamily: 'Courier')),
                                  ],
                                ),
                                const Divider(height: 16, color: Color(0xFFEEEEEE)),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Total Owed', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    Text('${res.totalOwed.toStringAsFixed(2)} ETB', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                                  ],
                                ),
                              ],
                            ),
                          )
                      ],
                    ),
                  ),
                );
              }).toList(),
              
              const SizedBox(height: 120),
            ],
          ),
        ),

        // Action Share
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: ElevatedButton.icon(
            onPressed: () {
              final text = _getShareText();
              Clipboard.setData(ClipboardData(text: text));
              alert('Split breakdown copied to clipboard! Ready to share.');
            },
            icon: const Icon(Icons.share, size: 16),
            label: const Text('Share Breakdown', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
            ),
          ),
        )
      ],
    );
  }
}
