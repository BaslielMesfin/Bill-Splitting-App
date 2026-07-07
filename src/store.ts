import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import { computeSplit } from './utils/splittingAlgorithm';
import type { Participant, Receipt, ReceiptUnit, SplitResult } from './utils/splittingAlgorithm';

export interface SavedSplit {
  id: string;
  merchantName?: string;
  date: string;
  total: number;
  participantsCount: number;
  results: (SplitResult & { participantName: string })[];
}

interface AppState {
  // Current Split State
  receipt: Receipt & { id: string; merchantName?: string; imageUri?: string };
  lineItems: { id: string; description: string; quantity: number; unitPrice: number; amount: number }[];
  activeParticipants: Participant[];
  units: ReceiptUnit[];
  
  // Persistence State
  recentParticipants: (Participant & { lastUsedAt: number })[];
  recentSplits: SavedSplit[];

  // Actions
  setReceipt: (receipt: Partial<AppState['receipt']>) => void;
  setLineItems: (items: AppState['lineItems']) => void;
  updateLineItem: (id: string, updated: Partial<AppState['lineItems'][0]>) => void;
  addLineItem: (item: Omit<AppState['lineItems'][0], 'id' | 'amount'>) => void;
  deleteLineItem: (id: string) => void;
  
  // Participant Actions
  addActiveParticipant: (firstName: string, lastName?: string) => string;
  removeActiveParticipant: (id: string) => void;
  toggleRecentParticipant: (id: string) => void;
  
  // Assignment Actions
  initializeUnits: () => void;
  assignUnitParticipant: (unitId: string, participantId: string) => void;
  setUnitCustomShares: (unitId: string, shares: { participantId: string; share: number }[]) => void;
  clearAssignments: () => void;
  
  // History Actions
  saveCurrentSplit: () => void;
  resetCurrentSplit: () => void;
}

const generateId = () => Math.random().toString(36).substring(2, 9);

export const useAppStore = create<AppState>()(
  persist(
    (set) => ({
      // Initial state
      receipt: {
        id: '',
        merchantName: '',
        subtotal: 0,
        serviceChargeAmount: 0,
        taxRate: 0.15,
        taxAmount: 0,
        total: 0,
        imageUri: '',
      },
      lineItems: [],
      activeParticipants: [],
      units: [],
      recentParticipants: [],
      recentSplits: [],

      // Actions
      setReceipt: (receiptUpdate) => set((state) => {
        const newReceipt = { ...state.receipt, ...receiptUpdate };
        // If totals are updated, check if we need to auto-calculate/update total or subtotal
        return { receipt: newReceipt };
      }),

      setLineItems: (items) => set({ lineItems: items }),

      updateLineItem: (id, updated) => set((state) => {
        const lineItems = state.lineItems.map(item => {
          if (item.id === id) {
            const newItem = { ...item, ...updated };
            if (updated.quantity !== undefined || updated.unitPrice !== undefined) {
              newItem.amount = newItem.quantity * newItem.unitPrice;
            }
            return newItem;
          }
          return item;
        });

        // Auto-recalculate subtotal based on line items
        const newSubtotal = lineItems.reduce((sum, item) => sum + item.amount, 0);
        // Recalculate default service charge (10%) and tax (15%) if they were 0 or we want to match ERCA default
        const newService = state.receipt.serviceChargeAmount > 0 
          ? state.receipt.serviceChargeAmount 
          : parseFloat((newSubtotal * 0.1).toFixed(2));
        const newTax = parseFloat(((newSubtotal + newService) * state.receipt.taxRate).toFixed(2));
        const newTotal = parseFloat((newSubtotal + newService + newTax).toFixed(2));

        return {
          lineItems,
          receipt: {
            ...state.receipt,
            subtotal: newSubtotal,
            serviceChargeAmount: newService,
            taxAmount: newTax,
            total: newTotal
          }
        };
      }),

      addLineItem: (item) => set((state) => {
        const newItem = {
          ...item,
          id: generateId(),
          amount: item.quantity * item.unitPrice
        };
        const lineItems = [...state.lineItems, newItem];
        const newSubtotal = lineItems.reduce((sum, i) => sum + i.amount, 0);
        const newService = state.receipt.serviceChargeAmount > 0 
          ? state.receipt.serviceChargeAmount 
          : parseFloat((newSubtotal * 0.1).toFixed(2));
        const newTax = parseFloat(((newSubtotal + newService) * state.receipt.taxRate).toFixed(2));
        const newTotal = parseFloat((newSubtotal + newService + newTax).toFixed(2));

        return {
          lineItems,
          receipt: {
            ...state.receipt,
            subtotal: newSubtotal,
            serviceChargeAmount: newService,
            taxAmount: newTax,
            total: newTotal
          }
        };
      }),

      deleteLineItem: (id) => set((state) => {
        const lineItems = state.lineItems.filter(item => item.id !== id);
        const newSubtotal = lineItems.reduce((sum, i) => sum + i.amount, 0);
        const newService = state.receipt.serviceChargeAmount > 0 
          ? state.receipt.serviceChargeAmount 
          : parseFloat((newSubtotal * 0.1).toFixed(2));
        const newTax = parseFloat(((newSubtotal + newService) * state.receipt.taxRate).toFixed(2));
        const newTotal = parseFloat((newSubtotal + newService + newTax).toFixed(2));

        return {
          lineItems,
          receipt: {
            ...state.receipt,
            subtotal: newSubtotal,
            serviceChargeAmount: newService,
            taxAmount: newTax,
            total: newTotal
          }
        };
      }),

      addActiveParticipant: (firstName, lastName) => {
        const id = generateId();
        const newParticipant: Participant = { id, firstName, lastName };
        
        set((state) => {
          // Add to active
          const activeParticipants = [...state.activeParticipants, newParticipant];
          
          // Add/Update in recent participants list
          const existingRecentIdx = state.recentParticipants.findIndex(
            p => p.firstName.toLowerCase() === firstName.toLowerCase() && 
                 p.lastName?.toLowerCase() === lastName?.toLowerCase()
          );

          let recentParticipants = [...state.recentParticipants];
          if (existingRecentIdx > -1) {
            recentParticipants[existingRecentIdx].lastUsedAt = Date.now();
          } else {
            recentParticipants.push({ ...newParticipant, lastUsedAt: Date.now() });
          }

          // Sort recent participants by last used
          recentParticipants.sort((a, b) => b.lastUsedAt - a.lastUsedAt);

          return { activeParticipants, recentParticipants };
        });

        return id;
      },

      removeActiveParticipant: (id) => set((state) => {
        // Remove from active list
        const activeParticipants = state.activeParticipants.filter(p => p.id !== id);
        
        // Also clean up assignments containing this participant
        const units = state.units.map(unit => {
          const assignments = unit.assignments.filter(a => a.participantId !== id);
          // Recalculate equal shares for remaining assignees
          const updatedAssignments = assignments.map(a => ({
            ...a,
            share: 1 / assignments.length
          }));
          return { ...unit, assignments: updatedAssignments };
        });

        return { activeParticipants, units };
      }),

      toggleRecentParticipant: (id) => set((state) => {
        const p = state.recentParticipants.find(rp => rp.id === id);
        if (!p) return {};

        const isActive = state.activeParticipants.some(ap => ap.id === id);
        let activeParticipants = [];

        if (isActive) {
          // Remove it
          activeParticipants = state.activeParticipants.filter(ap => ap.id !== id);
        } else {
          // Add it
          activeParticipants = [...state.activeParticipants, { id: p.id, firstName: p.firstName, lastName: p.lastName }];
        }

        // Update lastUsedAt in recent list
        const recentParticipants = state.recentParticipants.map(rp => {
          if (rp.id === id) {
            return { ...rp, lastUsedAt: Date.now() };
          }
          return rp;
        }).sort((a, b) => b.lastUsedAt - a.lastUsedAt);

        // Clean up assignments if removed
        let units = state.units;
        if (isActive) {
          units = state.units.map(unit => {
            const assignments = unit.assignments.filter(a => a.participantId !== id);
            const updatedAssignments = assignments.map(a => ({
              ...a,
              share: assignments.length > 0 ? 1 / assignments.length : 0
            }));
            return { ...unit, assignments: updatedAssignments };
          });
        }

        return { activeParticipants, recentParticipants, units };
      }),

      initializeUnits: () => set((state) => {
        const units: ReceiptUnit[] = [];
        
        state.lineItems.forEach((item) => {
          const qty = item.quantity;
          
          if (qty <= 1) {
            // Check if a unit for this item already exists (to preserve assignments)
            const existingUnit = state.units.find(u => u.id === item.id);
            units.push({
              id: item.id,
              description: item.description,
              unitPrice: item.unitPrice,
              assignments: existingUnit ? existingUnit.assignments : [],
            });
          } else {
            // Expand into individual unit items
            for (let index = 0; index < qty; index++) {
              const unitId = `${item.id}_unit_${index}`;
              const existingUnit = state.units.find(u => u.id === unitId);
              units.push({
                id: unitId,
                description: `${item.description} (${index + 1}/${qty})`,
                unitPrice: item.unitPrice,
                assignments: existingUnit ? existingUnit.assignments : [],
              });
            }
          }
        });

        return { units };
      }),

      assignUnitParticipant: (unitId, participantId) => set((state) => {
        const units = state.units.map(unit => {
          if (unit.id === unitId) {
            const isAssigned = unit.assignments.some(a => a.participantId === participantId);
            let assignments = [];

            if (isAssigned) {
              // Unassign
              assignments = unit.assignments.filter(a => a.participantId !== participantId);
            } else {
              // Assign
              assignments = [...unit.assignments, { participantId, share: 0 }];
            }

            // Recalculate equal shares
            const count = assignments.length;
            const updatedAssignments = assignments.map(a => ({
              ...a,
              share: count > 0 ? 1 / count : 0
            }));

            return { ...unit, assignments: updatedAssignments };
          }
          return unit;
        });

        return { units };
      }),

      setUnitCustomShares: (unitId, shares) => set((state) => {
        const units = state.units.map(unit => {
          if (unit.id === unitId) {
            return { ...unit, assignments: shares };
          }
          return unit;
        });
        return { units };
      }),

      clearAssignments: () => set((state) => {
        const units = state.units.map(u => ({ ...u, assignments: [] }));
        return { units };
      }),

      saveCurrentSplit: () => set((state) => {
        const splitResults = computeSplit(state.receipt, state.activeParticipants, state.units);
        
        // Map names to results for convenience
        const results = splitResults.map(res => {
          const p = state.activeParticipants.find(ap => ap.id === res.participantId)!;
          const name = p.lastName ? `${p.firstName} ${p.lastName}` : p.firstName;
          return {
            ...res,
            participantName: name
          };
        });

        const newSplit: SavedSplit = {
          id: state.receipt.id || generateId(),
          merchantName: state.receipt.merchantName || 'Unnamed Split',
          date: new Date().toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }),
          total: Math.ceil(state.receipt.total),
          participantsCount: state.activeParticipants.length,
          results
        };

        // Update lastUsedAt for all active participants in recent list
        const activeIds = new Set(state.activeParticipants.map(ap => ap.id));
        const recentParticipants = state.recentParticipants.map(rp => {
          if (activeIds.has(rp.id)) {
            return { ...rp, lastUsedAt: Date.now() };
          }
          return rp;
        }).sort((a, b) => b.lastUsedAt - a.lastUsedAt);

        return {
          recentSplits: [newSplit, ...state.recentSplits],
          recentParticipants
        };
      }),

      resetCurrentSplit: () => set({
        receipt: {
          id: '',
          merchantName: '',
          subtotal: 0,
          serviceChargeAmount: 0,
          taxRate: 0.15,
          taxAmount: 0,
          total: 0,
          imageUri: '',
        },
        lineItems: [],
        activeParticipants: [],
        units: []
      })
    }),
    {
      name: 'fair-split-storage',
      partialize: (state) => ({
        recentParticipants: state.recentParticipants,
        recentSplits: state.recentSplits,
      }),
    }
  )
);
