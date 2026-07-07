import { describe, it, expect } from 'vitest';
import { computeSplit } from './splittingAlgorithm';
import type { Receipt, Participant, ReceiptUnit } from './splittingAlgorithm';

describe('Splitting Algorithm - largest remainder method', () => {
  it('should calculate the exact split for the PRD worked test case', () => {
    // Subtotal: 2227.69, Service Charge: 82.40, Taxable base: 2310.09, Tax (15%): 346.51, Total: 2656.60
    // splitTarget = Math.ceil(2656.60) = 2657
    const receipt: Receipt = {
      subtotal: 2227.69,
      serviceChargeAmount: 82.40,
      taxRate: 0.15,
      taxAmount: 346.51,
      total: 2656.60,
    };

    const participants: Participant[] = [
      { id: '1', firstName: 'Abebe' },
      { id: '2', firstName: 'Hirut' },
      { id: '3', firstName: 'Dawit' },
    ];

    // Assign items:
    // Abebe: 1000 ETB subtotal
    // Hirut: 800 ETB subtotal
    // Dawit: 427.69 ETB subtotal
    // Sum = 2227.69
    const units: ReceiptUnit[] = [
      {
        id: 'u1',
        description: 'Abebe Personal Item',
        unitPrice: 1000,
        assignments: [{ participantId: '1', share: 1 }],
      },
      {
        id: 'u2',
        description: 'Hirut Personal Item',
        unitPrice: 800,
        assignments: [{ participantId: '2', share: 1 }],
      },
      {
        id: 'u3',
        description: 'Dawit Personal Item',
        unitPrice: 427.69,
        assignments: [{ participantId: '3', share: 1 }],
      },
    ];

    const results = computeSplit(receipt, participants, units);

    // Sum of results should be exactly 2657
    const sum = results.reduce((acc, curr) => acc + curr.totalOwed, 0);
    expect(sum).toBe(2657);

    // Specific expected shares based on manual calculation:
    // Abebe: 1192.67
    // Hirut: 954.16
    // Dawit: 510.17
    const abebe = results.find(r => r.participantId === '1');
    const hirut = results.find(r => r.participantId === '2');
    const dawit = results.find(r => r.participantId === '3');

    expect(abebe).toBeDefined();
    expect(hirut).toBeDefined();
    expect(dawit).toBeDefined();

    expect(abebe?.totalOwed).toBe(1192.67);
    expect(hirut?.totalOwed).toBe(954.16);
    expect(dawit?.totalOwed).toBe(510.17);
  });

  it('should split exactly for a single participant', () => {
    const receipt: Receipt = {
      subtotal: 100,
      serviceChargeAmount: 10,
      taxRate: 0.15,
      taxAmount: 16.5,
      total: 126.5,
    };

    const participants: Participant[] = [{ id: '1', firstName: 'Abebe' }];

    const units: ReceiptUnit[] = [
      {
        id: 'u1',
        description: 'Meal',
        unitPrice: 100,
        assignments: [{ participantId: '1', share: 1 }],
      },
    ];

    const results = computeSplit(receipt, participants, units);
    expect(results).toHaveLength(1);
    expect(results[0].totalOwed).toBe(127); // ceil(126.5)
  });

  it('should split equally for shared items', () => {
    const receipt: Receipt = {
      subtotal: 90,
      serviceChargeAmount: 9,
      taxRate: 0.15,
      taxAmount: 14.85,
      total: 113.85, // splitTarget = 114
    };

    const participants: Participant[] = [
      { id: '1', firstName: 'Abebe' },
      { id: '2', firstName: 'Dawit' },
    ];

    const units: ReceiptUnit[] = [
      {
        id: 'u1',
        description: 'Shared Pizza',
        unitPrice: 90,
        assignments: [
          { participantId: '1', share: 0.5 },
          { participantId: '2', share: 0.5 },
        ],
      },
    ];

    const results = computeSplit(receipt, participants, units);
    const sum = results.reduce((acc, curr) => acc + curr.totalOwed, 0);
    expect(sum).toBe(114);

    // Each person's raw total:
    // itemSubtotal = 45
    // serviceChargeShare = 4.5
    // taxShare = (45 + 4.5) * 0.15 = 7.425
    // rawTotal = 45 + 4.5 + 7.425 = 56.925
    // Rounded down = 56.92. Remainder = 0.005.
    // Sum of rounded down = 113.84.
    // Difference = 114 - 113.84 = 0.16 (16 cents)
    // Both remainders are identical (0.005). Abebe will get +8c, Dawit +8c.
    // So both should owe 56.92 + 0.08 = 57.00.
    expect(results[0].totalOwed).toBe(57);
    expect(results[1].totalOwed).toBe(57);
  });
});
