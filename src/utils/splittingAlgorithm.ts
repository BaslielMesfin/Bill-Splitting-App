export interface Participant {
  id: string;
  firstName: string;
  lastName?: string;
}

export interface UnitAssignment {
  participantId: string;
  share: number; // fraction 0 to 1, sum of shares for a unit must equal 1
}

export interface ReceiptUnit {
  id: string;
  description: string;
  unitPrice: number;
  assignments: UnitAssignment[];
}

export interface Receipt {
  subtotal: number;
  serviceChargeAmount: number;
  taxRate: number; // e.g. 0.15
  taxAmount: number;
  total: number;
}

export interface SplitResult {
  participantId: string;
  itemSubtotal: number;
  serviceChargeShare: number;
  taxShare: number;
  totalOwed: number; // Precise to the cent, reconciled to splitTarget
}

/**
 * Computes the split breakdown for each participant.
 * Ensures the sum of all final totals equals Math.ceil(receipt.total) exactly.
 */
export function computeSplit(
  receipt: Receipt,
  participants: Participant[],
  units: ReceiptUnit[]
): SplitResult[] {
  const splitTarget = Math.ceil(receipt.total);
  
  if (participants.length === 0) {
    return [];
  }

  // Step 1: Calculate per-person item subtotal
  const resultsMap: Record<string, Omit<SplitResult, 'totalOwed'> & { rawTotal: number; remainder: number; totalOwed: number }> = {};
  
  for (const p of participants) {
    resultsMap[p.id] = {
      participantId: p.id,
      itemSubtotal: 0,
      serviceChargeShare: 0,
      taxShare: 0,
      rawTotal: 0,
      remainder: 0,
      totalOwed: 0,
    };
  }

  // Sum up assigned items per participant
  for (const unit of units) {
    for (const assignment of unit.assignments) {
      if (resultsMap[assignment.participantId]) {
        resultsMap[assignment.participantId].itemSubtotal += unit.unitPrice * assignment.share;
      }
    }
  }

  // Step 2 & 3: Allocate Service Charge and Tax, compute Raw Totals
  for (const p of participants) {
    const res = resultsMap[p.id];
    
    // Service charge allocation proportional to item subtotal
    if (receipt.subtotal > 0) {
      res.serviceChargeShare = (res.itemSubtotal / receipt.subtotal) * receipt.serviceChargeAmount;
    } else {
      res.serviceChargeShare = 0;
    }
    
    // Taxable base and Tax allocation
    const taxableBase = res.itemSubtotal + res.serviceChargeShare;
    res.taxShare = taxableBase * receipt.taxRate;
    
    // Raw total before rounding reconciliation
    res.rawTotal = res.itemSubtotal + res.serviceChargeShare + res.taxShare;
  }

  // Step 4: Round down to 2 decimals and track remainders (in cents)
  let sumOfRoundedDown = 0;
  const participantRemainders: { participantId: string; remainder: number }[] = [];

  for (const p of participants) {
    const res = resultsMap[p.id];
    // Round down to 2 decimals
    res.totalOwed = Math.floor(res.rawTotal * 100) / 100;
    sumOfRoundedDown += res.totalOwed;
    
    // Remainder is the fraction of a cent dropped
    const remainder = res.rawTotal - res.totalOwed;
    res.remainder = remainder;
    participantRemainders.push({ participantId: p.id, remainder });
  }

  // Step 5: Distribute difference using the Largest Remainder Method
  // difference in cents (handling floating point inaccuracies)
  let diffCents = Math.round((splitTarget - sumOfRoundedDown) * 100);

  if (diffCents > 0) {
    // Sort by remainder descending
    participantRemainders.sort((a, b) => b.remainder - a.remainder);
    
    // Distribute 1 cent at a time, looping if necessary
    let i = 0;
    while (diffCents > 0) {
      const targetId = participantRemainders[i % participantRemainders.length].participantId;
      resultsMap[targetId].totalOwed = Math.round((resultsMap[targetId].totalOwed + 0.01) * 100) / 100;
      diffCents--;
      i++;
    }
  }

  // Format and return results
  return participants.map(p => {
    const res = resultsMap[p.id];
    return {
      participantId: p.id,
      itemSubtotal: Math.round(res.itemSubtotal * 100) / 100,
      serviceChargeShare: Math.round(res.serviceChargeShare * 100) / 100,
      taxShare: Math.round(res.taxShare * 100) / 100,
      totalOwed: Math.round(res.totalOwed * 100) / 100,
    };
  });
}
