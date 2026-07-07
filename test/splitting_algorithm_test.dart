import 'package:flutter_test/flutter_test.dart';
import 'package:fair_split/splitting_algorithm.dart';

void main() {
  group('Splitting Algorithm - largest remainder method', () {
    test('should calculate the exact split for the PRD worked test case', () {
      // Subtotal: 2227.69, Service Charge: 82.40, Tax (15%), Total: 2656.60
      // splitTarget = Math.ceil(2656.60) = 2657
      final receipt = Receipt(
        subtotal: 2227.69,
        serviceChargeAmount: 82.40,
        taxRate: 0.15,
        taxAmount: 346.51,
        total: 2656.60,
      );

      final participants = [
        Participant(id: '1', firstName: 'Abebe'),
        Participant(id: '2', firstName: 'Hirut'),
        Participant(id: '3', firstName: 'Dawit'),
      ];

      // Abebe: 1000 ETB
      // Hirut: 800 ETB
      // Dawit: 427.69 ETB
      final units = [
        ReceiptUnit(
          id: 'u1',
          description: 'Abebe Personal Item',
          unitPrice: 1000.0,
          assignments: [UnitAssignment(participantId: '1', share: 1.0)],
        ),
        ReceiptUnit(
          id: 'u2',
          description: 'Hirut Personal Item',
          unitPrice: 800.0,
          assignments: [UnitAssignment(participantId: '2', share: 1.0)],
        ),
        ReceiptUnit(
          id: 'u3',
          description: 'Dawit Personal Item',
          unitPrice: 427.69,
          assignments: [UnitAssignment(participantId: '3', share: 1.0)],
        ),
      ];

      final results = computeSplit(receipt, participants, units);

      // Sum should be exactly 2657.00
      double sum = results.fold(0.0, (acc, res) => acc + res.totalOwed);
      expect(sum, 2657.00);

      // Abebe: 1192.67
      // Hirut: 954.16
      // Dawit: 510.17
      final abebe = results.firstWhere((r) => r.participantId == '1');
      final hirut = results.firstWhere((r) => r.participantId == '2');
      final dawit = results.firstWhere((r) => r.participantId == '3');

      expect(abebe.totalOwed, 1192.67);
      expect(hirut.totalOwed, 954.16);
      expect(dawit.totalOwed, 510.17);
    });

    test('should split exactly for a single participant', () {
      final receipt = Receipt(
        subtotal: 100.0,
        serviceChargeAmount: 10.0,
        taxRate: 0.15,
        taxAmount: 16.5,
        total: 126.5,
      );

      final participants = [Participant(id: '1', firstName: 'Abebe')];

      final units = [
        ReceiptUnit(
          id: 'u1',
          description: 'Meal',
          unitPrice: 100.0,
          assignments: [UnitAssignment(participantId: '1', share: 1.0)],
        ),
      ];

      final results = computeSplit(receipt, participants, units);
      expect(results.length, 1);
      expect(results[0].totalOwed, 127.0); // ceil(126.5)
    });

    test('should split equally for shared items', () {
      final receipt = Receipt(
        subtotal: 90.0,
        serviceChargeAmount: 9.0,
        taxRate: 0.15,
        taxAmount: 14.85,
        total: 113.85, // splitTarget = 114
      );

      final participants = [
        Participant(id: '1', firstName: 'Abebe'),
        Participant(id: '2', firstName: 'Dawit'),
      ];

      final units = [
        ReceiptUnit(
          id: 'u1',
          description: 'Shared Pizza',
          unitPrice: 90.0,
          assignments: [
            UnitAssignment(participantId: '1', share: 0.5),
            UnitAssignment(participantId: '2', share: 0.5),
          ],
        ),
      ];

      final results = computeSplit(receipt, participants, units);
      double sum = results.fold(0.0, (acc, res) => acc + res.totalOwed);
      expect(sum, 114.00);
      expect(results[0].totalOwed, 57.00);
      expect(results[1].totalOwed, 57.00);
    });
  });
}
