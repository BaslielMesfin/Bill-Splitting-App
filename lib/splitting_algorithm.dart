class Participant {
  final String id;
  final String firstName;
  final String? lastName;

  Participant({required this.id, required this.firstName, this.lastName});

  Map<String, dynamic> toJson() => {
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
      };

  factory Participant.fromJson(Map<String, dynamic> json) => Participant(
        id: json['id'] as String,
        firstName: json['firstName'] as String,
        lastName: json['lastName'] as String?,
      );
}

class UnitAssignment {
  final String participantId;
  final double share; // fraction 0 to 1

  UnitAssignment({required this.participantId, required this.share});

  Map<String, dynamic> toJson() => {
        'participantId': participantId,
        'share': share,
      };

  factory UnitAssignment.fromJson(Map<String, dynamic> json) => UnitAssignment(
        participantId: json['participantId'] as String,
        share: (json['share'] as num).toDouble(),
      );
}

class ReceiptUnit {
  final String id;
  final String description;
  final double unitPrice;
  final List<UnitAssignment> assignments;

  ReceiptUnit({
    required this.id,
    required this.description,
    required this.unitPrice,
    required this.assignments,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'unitPrice': unitPrice,
        'assignments': assignments.map((a) => a.toJson()).toList(),
      };

  factory ReceiptUnit.fromJson(Map<String, dynamic> json) => ReceiptUnit(
        id: json['id'] as String,
        description: json['description'] as String,
        unitPrice: (json['unitPrice'] as num).toDouble(),
        assignments: (json['assignments'] as List<dynamic>)
            .map((a) => UnitAssignment.fromJson(a as Map<String, dynamic>))
            .toList(),
      );
}

class Receipt {
  final double subtotal;
  final double serviceChargeAmount;
  final double taxRate; // e.g. 0.15
  final double taxAmount;
  final double total;

  Receipt({
    required this.subtotal,
    required this.serviceChargeAmount,
    required this.taxRate,
    required this.taxAmount,
    required this.total,
  });

  Map<String, dynamic> toJson() => {
        'subtotal': subtotal,
        'serviceChargeAmount': serviceChargeAmount,
        'taxRate': taxRate,
        'taxAmount': taxAmount,
        'total': total,
      };

  factory Receipt.fromJson(Map<String, dynamic> json) => Receipt(
        subtotal: (json['subtotal'] as num).toDouble(),
        serviceChargeAmount: (json['serviceChargeAmount'] as num).toDouble(),
        taxRate: (json['taxRate'] as num).toDouble(),
        taxAmount: (json['taxAmount'] as num).toDouble(),
        total: (json['total'] as num).toDouble(),
      );
}

class SplitResult {
  final String participantId;
  final double itemSubtotal;
  final double serviceChargeShare;
  final double taxShare;
  final double totalOwed; // Precise to the cent, reconciled to splitTarget

  SplitResult({
    required this.participantId,
    required this.itemSubtotal,
    required this.serviceChargeShare,
    required this.taxShare,
    required this.totalOwed,
  });

  Map<String, dynamic> toJson() => {
        'participantId': participantId,
        'itemSubtotal': itemSubtotal,
        'serviceChargeShare': serviceChargeShare,
        'taxShare': taxShare,
        'totalOwed': totalOwed,
      };

  factory SplitResult.fromJson(Map<String, dynamic> json) => SplitResult(
        participantId: json['participantId'] as String,
        itemSubtotal: (json['itemSubtotal'] as num).toDouble(),
        serviceChargeShare: (json['serviceChargeShare'] as num).toDouble(),
        taxShare: (json['taxShare'] as num).toDouble(),
        totalOwed: (json['totalOwed'] as num).toDouble(),
      );
}

/// Computes the split breakdown for each participant.
/// Ensures the sum of all final totals equals receipt.total.ceil() exactly.
List<SplitResult> computeSplit(
  Receipt receipt,
  List<Participant> participants,
  List<ReceiptUnit> units,
) {
  final int splitTarget = receipt.total.ceil();

  if (participants.isEmpty) {
    return [];
  }

  // Pre-fill results structures
  final Map<String, double> itemSubtotals = {};
  final Map<String, double> serviceChargeShares = {};
  final Map<String, double> taxShares = {};
  final Map<String, double> rawTotals = {};
  final Map<String, double> roundedDownTotals = {};
  final Map<String, double> remainders = {};

  for (final p in participants) {
    itemSubtotals[p.id] = 0.0;
  }

  // Step 1: Calculate per-person item subtotal
  for (final unit in units) {
    for (final assignment in unit.assignments) {
      if (itemSubtotals.containsKey(assignment.participantId)) {
        itemSubtotals[assignment.participantId] =
            itemSubtotals[assignment.participantId]! +
                (unit.unitPrice * assignment.share);
      }
    }
  }

  // Step 2 & 3: Allocate Service Charge and Tax, compute Raw Totals
  for (final p in participants) {
    final double sub = itemSubtotals[p.id]!;

    // Service charge allocation proportional to item subtotal
    double serviceShare = 0.0;
    if (receipt.subtotal > 0) {
      serviceShare = (sub / receipt.subtotal) * receipt.serviceChargeAmount;
    }
    serviceChargeShares[p.id] = serviceShare;

    // Taxable base and Tax allocation
    final double taxableBase = sub + serviceShare;
    final double taxShare = taxableBase * receipt.taxRate;
    taxShares[p.id] = taxShare;

    // Raw total before rounding reconciliation
    rawTotals[p.id] = sub + serviceShare + taxShare;
  }

  // Step 4: Round down to 2 decimals and track remainders
  double sumOfRoundedDown = 0.0;
  final List<MapEntry<String, double>> participantRemainders = [];

  for (final p in participants) {
    final double raw = rawTotals[p.id]!;
    // Round down to 2 decimals
    final double rounded = (raw * 100).floorToDouble() / 100;
    roundedDownTotals[p.id] = rounded;
    sumOfRoundedDown += rounded;

    final double remainder = raw - rounded;
    remainders[p.id] = remainder;
    participantRemainders.add(MapEntry(p.id, remainder));
  }

  // Step 5: Distribute difference using the Largest Remainder Method
  // difference in cents (handling floating point inaccuracies)
  int diffCents = ((splitTarget - sumOfRoundedDown) * 100).round();

  if (diffCents > 0) {
    // Sort by remainder descending
    participantRemainders.sort((a, b) => b.value.compareTo(a.value));

    int i = 0;
    while (diffCents > 0) {
      final String targetId =
          participantRemainders[i % participantRemainders.length].key;
      roundedDownTotals[targetId] =
          ((roundedDownTotals[targetId]! + 0.01) * 100).roundToDouble() / 100;
      diffCents--;
      i++;
    }
  }

  // Format and return results
  return participants.map((p) {
    return SplitResult(
      participantId: p.id,
      itemSubtotal: (itemSubtotals[p.id]! * 100).roundToDouble() / 100,
      serviceChargeShare:
          (serviceChargeShares[p.id]! * 100).roundToDouble() / 100,
      taxShare: (taxShares[p.id]! * 100).roundToDouble() / 100,
      totalOwed: (roundedDownTotals[p.id]! * 100).roundToDouble() / 100,
    );
  }).toList();
}
