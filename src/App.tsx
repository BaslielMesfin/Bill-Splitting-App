import React, { useState, useRef } from 'react';
import { useAppStore } from './store';
import { computeSplit } from './utils/splittingAlgorithm';

export default function App() {
  const [screen, setScreen] = useState<'home' | 'capture' | 'review' | 'participants' | 'assign' | 'summary'>('home');
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  
  // App store selections
  const {
    receipt,
    lineItems,
    activeParticipants,
    units,
    recentParticipants,
    recentSplits,
    setReceipt,
    setLineItems,
    updateLineItem,
    addLineItem,
    deleteLineItem,
    addActiveParticipant,
    toggleRecentParticipant,
    removeActiveParticipant,
    initializeUnits,
    assignUnitParticipant,
    setUnitCustomShares,
    saveCurrentSplit,
    resetCurrentSplit,
  } = useAppStore();

  // Modals / Dialog State
  const [editingItem, setEditingItem] = useState<{ id: string; description: string; quantity: number; unitPrice: number } | null>(null);
  const [addingItem, setAddingItem] = useState<{ description: string; quantity: number; unitPrice: number } | null>(null);
  const [editingFees, setEditingFees] = useState<{ type: 'service' | 'tax'; value: number } | null>(null);
  const [editingCustomShares, setEditingCustomShares] = useState<{ unitId: string; description: string; price: number } | null>(null);

  // Participant Form Inputs
  const [newFirstName, setNewFirstName] = useState('');
  const [newLastName, setNewLastName] = useState('');

  // Active Assignment Index (for item-by-item assignment screen)
  const [activeUnitIndex, setActiveUnitIndex] = useState(0);

  // Expand states for Summary screen card items
  const [expandedParticipantId, setExpandedParticipantId] = useState<string | null>(null);

  // Reference for file upload input
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Set default receipt ID on entry to capture
  const handleStartNewSplit = () => {
    resetCurrentSplit();
    setReceipt({
      id: Math.random().toString(36).substring(2, 9),
      taxRate: 0.15,
      subtotal: 0,
      serviceChargeAmount: 0,
      taxAmount: 0,
      total: 0,
    });
    setScreen('capture');
  };

  // Mock Receipt loader for fast testing without OCR
  const handleLoadMockReceipt = () => {
    const mockId = 'mock_' + Math.random().toString(36).substring(2, 5);
    setReceipt({
      id: mockId,
      merchantName: 'Maleda Restaurant',
      subtotal: 2227.69,
      serviceChargeAmount: 82.40,
      taxRate: 0.15,
      taxAmount: 346.51,
      total: 2656.60,
    });
    setLineItems([
      { id: 'item_1', description: 'Macchiato', quantity: 2, unitPrice: 45.00, amount: 90.00 },
      { id: 'item_2', description: 'Fasting Firfir', quantity: 1, unitPrice: 150.00, amount: 150.00 },
      { id: 'item_3', description: 'Shiro Tegabino', quantity: 3, unitPrice: 180.00, amount: 540.00 },
      { id: 'item_4', description: 'Bottled Water (L)', quantity: 2, unitPrice: 30.00, amount: 60.00 },
      { id: 'item_5', description: 'Margherita Pizza Large', quantity: 1, unitPrice: 1387.69, amount: 1387.69 }
    ]);
    setErrorMsg(null);
    setScreen('review');
  };

  // File Upload parsing logic calling Express proxy server
  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setLoading(true);
    setErrorMsg(null);

    const formData = new FormData();
    formData.append('receipt', file);

    try {
      const response = await fetch('http://localhost:3001/api/parse-receipt', {
        method: 'POST',
        body: formData,
      });

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}));
        throw new Error(errorData.message || 'Failed to parse receipt.');
      }

      const res = await response.json();
      
      if (res.success && res.data) {
        const { merchantName, subtotal, serviceChargeAmount, taxRate, taxAmount, total, lineItems: parsedItems } = res.data;
        
        setReceipt({
          merchantName: merchantName || 'ERCA Receipt',
          subtotal: subtotal || 0,
          serviceChargeAmount: serviceChargeAmount || 0,
          taxRate: taxRate || 0.15,
          taxAmount: taxAmount || 0,
          total: total || 0,
        });

        // Add IDs to parsed line items
        const itemsWithIds = parsedItems.map((item: any) => ({
          ...item,
          id: Math.random().toString(36).substring(2, 9),
          amount: (item.quantity || 1) * (item.unitPrice || 0)
        }));
        
        setLineItems(itemsWithIds);
        setScreen('review');
      } else {
        throw new Error('Parsing succeeded but data was malformed.');
      }
    } catch (err: any) {
      console.error(err);
      setErrorMsg(err.message || 'Could not connect to parsing server. Make sure the proxy backend is running.');
    } finally {
      setLoading(false);
    }
  };

  // Skip parsing and input manually
  const handleSkipToManual = () => {
    setReceipt({
      merchantName: 'Manual Receipt',
      subtotal: 0,
      serviceChargeAmount: 0,
      taxRate: 0.15,
      taxAmount: 0,
      total: 0,
    });
    setLineItems([]);
    setErrorMsg(null);
    setScreen('review');
  };

  // Proceed from Review to Participants Selection
  const handleProceedToParticipants = () => {
    if (lineItems.length === 0) {
      alert('Please add at least one line item before proceeding.');
      return;
    }
    setScreen('participants');
  };

  // Handle adding new participant
  const handleAddParticipantSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newFirstName.trim()) return;
    addActiveParticipant(newFirstName.trim(), newLastName.trim() || undefined);
    setNewFirstName('');
    setNewLastName('');
  };

  // Proceed to item assignment
  const handleProceedToAssign = () => {
    if (activeParticipants.length === 0) {
      alert('Please select or add at least one participant.');
      return;
    }
    initializeUnits();
    setActiveUnitIndex(0);
    setScreen('assign');
  };

  // Proceed from Assign to Summary
  const handleCalculateSplit = () => {
    // Verify if all units are assigned
    const unassignedUnitsCount = units.filter(u => u.assignments.length === 0).length;
    if (unassignedUnitsCount > 0) {
      const confirmProceed = window.confirm(`There are ${unassignedUnitsCount} unassigned items. Proceeding will distribute their cost evenly to everyone. Continue?`);
      if (!confirmProceed) return;
      
      // Auto assign unassigned items to everyone
      units.forEach(u => {
        if (u.assignments.length === 0) {
          activeParticipants.forEach(p => {
            assignUnitParticipant(u.id, p.id);
          });
        }
      });
    }

    saveCurrentSplit();
    setScreen('summary');
  };

  // Formatted summary text block for sharing
  const getFormattedShareText = () => {
    const splitResults = computeSplit(receipt, activeParticipants, units);
    const targetTotal = Math.ceil(receipt.total);
    
    let text = `🧾 *Fair Split Breakdown — ${receipt.merchantName || 'Receipt'}*\n`;
    text += `📅 Date: ${new Date().toLocaleDateString()}\n`;
    text += `💰 Total Bill: ${targetTotal} ETB (reconciled)\n`;
    text += `---------------------------\n`;
    
    splitResults.forEach((res) => {
      const p = activeParticipants.find(ap => ap.id === res.participantId)!;
      const name = p.lastName ? `${p.firstName} ${p.lastName}` : p.firstName;
      
      // Get item names assigned to this person
      const assignedItemDetails = units
        .filter(u => u.assignments.some(a => a.participantId === res.participantId))
        .map(u => {
          const userAssignment = u.assignments.find(a => a.participantId === res.participantId)!;
          const sharePct = userAssignment.share < 1 ? ` (${Math.round(userAssignment.share * 100)}%)` : '';
          return `- ${u.description}${sharePct}: ${(u.unitPrice * userAssignment.share).toFixed(2)} ETB`;
        })
        .join('\n');

      text += `👤 *${name}* owes *${res.totalOwed.toFixed(2)} ETB*\n`;
      text += `  Items Subtotal: ${res.itemSubtotal.toFixed(2)} ETB\n`;
      text += `  Service Charge Share: ${res.serviceChargeShare.toFixed(2)} ETB\n`;
      text += `  VAT (15%) Share: ${res.taxShare.toFixed(2)} ETB\n`;
      if (assignedItemDetails) {
        text += `  Items ordered:\n${assignedItemDetails}\n`;
      }
      text += `\n`;
    });
    
    text += `Generated with Fair Split App.`;
    return text;
  };

  const handleShare = async () => {
    const text = getFormattedShareText();
    if (navigator.share) {
      try {
        await navigator.share({
          title: `Fair Split - ${receipt.merchantName}`,
          text: text,
        });
      } catch (err) {
        console.log('Share canceled or failed', err);
      }
    } else {
      // Fallback: Copy to Clipboard
      navigator.clipboard.writeText(text);
      alert('Breakdown copied to clipboard!');
    }
  };

  return (
    <div className="min-h-screen flex flex-col md:bg-surface-gray py-4 md:py-8 select-none">
      
      {/* Mobile Frame Container */}
      <div className="md:max-w-[400px] md:mx-auto md:bg-background md:min-h-[820px] md:max-h-[880px] md:rounded-[40px] md:shadow-2xl md:relative overflow-hidden w-full h-full flex flex-col bg-background border border-surface-container-high/40">
        
        {/* ========================================================================= */}
        {/* 1. HOME SCREEN */}
        {/* ========================================================================= */}
        {screen === 'home' && (
          <div className="flex-1 flex flex-col h-full overflow-hidden">
            {/* Header */}
            <header className="flex justify-between items-center px-container-padding h-16 w-full bg-surface/80 backdrop-blur-xl sticky top-0 z-50 pt-safe-area border-b border-surface-container-high/20">
              <div className="w-10"></div>
              <h1 className="text-headline-md font-headline-md font-bold text-primary text-center">Fair Split</h1>
              <button className="text-on-surface-variant hover:opacity-70 transition-opacity active:scale-95 w-10 h-10 flex items-center justify-center">
                <span className="material-symbols-outlined">more_horiz</span>
              </button>
            </header>

            <main className="flex-1 overflow-y-auto pb-24 hide-scrollbar">
              {/* Hero Banner Card */}
              <section className="px-container-padding py-stack-gap-md">
                <div className="relative w-full h-[320px] rounded-[32px] overflow-hidden mb-6 bg-surface-blue shadow-ambient border border-surface-container">
                  <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/30 to-transparent z-10"></div>
                  
                  {/* Styled Local Image Placeholder representing a restaurant table */}
                  <div className="absolute inset-0 bg-slate-900 flex items-center justify-center text-slate-500 z-0">
                    <span className="material-symbols-outlined text-[96px] opacity-10">restaurant</span>
                  </div>

                  <div className="absolute bottom-0 left-0 w-full p-6 z-20 text-on-primary">
                    <h2 className="text-2xl font-serif font-bold text-white mb-1">Addis Dinner Splits</h2>
                    <p className="text-sm text-white/80 mb-6">Proportionally split service charges and taxes without rounding errors.</p>
                    <button 
                      onClick={handleStartNewSplit}
                      className="w-full bg-white text-primary rounded-full py-3.5 px-6 text-label-md font-label-md flex justify-center items-center gap-2 hover:bg-surface-gray transition-colors active:scale-[0.98] duration-150 shadow-lg font-bold"
                    >
                      <span className="material-symbols-outlined filled text-[20px]">add_circle</span>
                      New Split
                    </button>
                  </div>
                </div>
              </section>

              {/* Recent Splits List */}
              <section className="px-container-padding pb-6">
                <div className="flex justify-between items-end mb-4">
                  <h3 className="font-serif text-xl font-bold text-on-background">Recent Splits</h3>
                  {recentSplits.length > 0 && (
                    <button className="text-xs font-semibold text-on-surface-variant hover:text-primary transition-colors">View All</button>
                  )}
                </div>

                {recentSplits.length === 0 ? (
                  <div className="bg-surface-container-lowest border border-surface-container-high rounded-3xl p-8 text-center flex flex-col items-center">
                    <span className="material-symbols-outlined text-slate-300 text-[48px] mb-3">receipt_long</span>
                    <p className="text-sm font-semibold text-on-surface-variant mb-1">No splits yet</p>
                    <p className="text-xs text-outline">Your calculated receipts will be listed here.</p>
                  </div>
                ) : (
                  <div className="flex flex-col gap-4">
                    {recentSplits.map((split) => (
                      <div 
                        key={split.id} 
                        className="bg-surface-container-lowest border border-surface-container-high rounded-3xl p-5 shadow-ambient hover:shadow-ambient-hover transition-shadow flex flex-col gap-3"
                      >
                        <div className="flex justify-between items-start">
                          <div className="flex items-center gap-3">
                            <div className="w-11 h-11 rounded-full bg-surface-blue flex items-center justify-center text-secondary border border-[#cbe6ff]">
                              <span className="material-symbols-outlined text-[20px]">restaurant</span>
                            </div>
                            <div>
                              <h4 className="text-sm font-bold text-on-background truncate max-w-[150px]">{split.merchantName}</h4>
                              <p className="text-xs text-on-surface-variant">{split.date} • {split.participantsCount} people</p>
                            </div>
                          </div>
                          <div className="text-right">
                            <span className="text-sm font-bold text-on-background block">{split.total} ETB</span>
                            <span className="text-[10px] font-bold text-success-green bg-success-green/10 px-2 py-0.5 rounded-full inline-block mt-1">Settled</span>
                          </div>
                        </div>
                        
                        {/* Avatar overlapped list */}
                        <div className="flex items-center -space-x-1.5 mt-1">
                          {split.results.slice(0, 4).map((res, i) => (
                            <div 
                              key={res.participantId} 
                              style={{ zIndex: 10 - i }}
                              className="w-7 h-7 rounded-full bg-surface-gray border border-surface-container-lowest flex items-center justify-center text-[10px] font-bold text-primary-fixed-dim uppercase"
                            >
                              {res.participantName.charAt(0)}
                            </div>
                          ))}
                          {split.results.length > 4 && (
                            <div className="w-7 h-7 rounded-full bg-surface-dim border border-surface-container-lowest flex items-center justify-center text-[9px] font-bold text-on-surface-variant z-0">
                              +{split.results.length - 4}
                            </div>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </section>
            </main>

            {/* Bottom Nav Bar */}
            <nav className="absolute bottom-0 left-0 w-full flex justify-around items-center px-6 py-4 bg-surface/90 backdrop-blur-2xl border-t border-surface-container-high/40 shadow-lg z-50">
              <button className="flex flex-col items-center justify-center bg-gradient-to-r from-[#3B82F6] to-[#60A5FA] text-white rounded-full px-5 py-1.5 hover:opacity-90 active:scale-95 duration-150">
                <span className="material-symbols-outlined filled mb-0.5 text-[20px]">home</span>
                <span className="text-[10px] font-bold">Home</span>
              </button>
              <button 
                onClick={() => alert('Activity history list is stored locally on this screen. (v2 details feature)')}
                className="flex flex-col items-center justify-center text-on-surface-variant px-5 py-1.5 rounded-full hover:bg-surface-container-high active:scale-95 transition-colors"
              >
                <span className="material-symbols-outlined mb-0.5 text-[20px]">receipt_long</span>
                <span className="text-[10px] font-medium">Activity</span>
              </button>
            </nav>
          </div>
        )}

        {/* ========================================================================= */}
        {/* 2. CAPTURE / UPLOAD SCREEN */}
        {/* ========================================================================= */}
        {screen === 'capture' && (
          <div className="flex-1 flex flex-col h-full bg-slate-950 text-white relative">
            
            {/* Header */}
            <header className="flex justify-between items-center px-container-padding h-16 w-full absolute top-0 z-50 bg-gradient-to-b from-black/80 to-transparent">
              <button 
                onClick={() => setScreen('home')}
                className="w-10 h-10 flex items-center justify-center text-white hover:opacity-70 transition-opacity"
              >
                <span className="material-symbols-outlined">arrow_back</span>
              </button>
              <h2 className="text-md font-bold">Scan ERCA Receipt</h2>
              <div className="w-10"></div>
            </header>

            {/* Simulated Live Viewport with Alignment Guide Overlay */}
            <div className="flex-1 flex flex-col justify-center items-center p-6 relative">
              
              {/* Outer Alignment Bounds */}
              <div className="w-full max-w-[280px] h-[400px] border-2 border-dashed border-white/40 rounded-3xl relative flex flex-col justify-between p-4 bg-black/20">
                
                {/* Guide corners */}
                <div className="absolute top-0 left-0 w-8 h-8 border-t-4 border-l-4 border-white rounded-tl-xl"></div>
                <div className="absolute top-0 right-0 w-8 h-8 border-t-4 border-r-4 border-white rounded-tr-xl"></div>
                <div className="absolute bottom-0 left-0 w-8 h-8 border-b-4 border-l-4 border-white rounded-bl-xl"></div>
                <div className="absolute bottom-0 right-0 w-8 h-8 border-b-4 border-r-4 border-white rounded-br-xl"></div>

                <div className="text-center text-xs text-white/80 select-none my-auto px-4 pointer-events-none">
                  <span className="material-symbols-outlined text-[36px] mb-2 text-white block opacity-85">document_scanner</span>
                  Fit the receipt in frame — good lighting helps. Only ERCA fiscal receipts are supported.
                </div>
              </div>

              {/* Hidden File Upload input */}
              <input 
                type="file" 
                ref={fileInputRef}
                onChange={handleFileChange}
                accept="image/*"
                capture="environment"
                className="hidden"
              />
            </div>

            {/* Error Message state */}
            {errorMsg && (
              <div className="absolute top-20 left-4 right-4 bg-error-red/90 text-white rounded-2xl p-4 text-center text-xs z-50 flex flex-col items-center gap-2">
                <span className="material-symbols-outlined">error</span>
                <p className="font-semibold">{errorMsg}</p>
                <button 
                  onClick={handleSkipToManual}
                  className="bg-white text-error-red rounded-full px-3 py-1 font-bold active:scale-95"
                >
                  Enter Manually
                </button>
              </div>
            )}

            {/* Loading Modal state */}
            {loading && (
              <div className="absolute inset-0 bg-black/80 flex flex-col justify-center items-center z-50">
                <div className="w-12 h-12 border-4 border-[#60A5FA] border-t-transparent rounded-full animate-spin mb-4"></div>
                <p className="text-sm font-bold tracking-wide">Reading receipt...</p>
                <p className="text-xs text-white/60 mt-1">OCR processing via Gemini Vision proxy</p>
              </div>
            )}

            {/* Shutter Button Action Bar */}
            <div className="p-container-padding bg-gradient-to-t from-black to-transparent flex flex-col items-center gap-6 pb-8 z-40">
              
              <button 
                onClick={handleLoadMockReceipt}
                className="text-xs font-semibold text-[#60A5FA] border border-[#60A5FA]/40 bg-[#60A5FA]/10 px-4 py-2 rounded-full hover:bg-[#60A5FA]/20 active:scale-95 duration-150 flex items-center gap-1.5"
              >
                <span className="material-symbols-outlined text-[16px]">bolt</span>
                Use Mock Receipt (Fast Testing)
              </button>

              <div className="flex justify-between items-center w-full max-w-[280px]">
                <button 
                  onClick={handleSkipToManual}
                  className="text-xs hover:opacity-70 text-white/80 flex flex-col items-center gap-1 active:scale-95"
                >
                  <span className="material-symbols-outlined text-[24px]">keyboard</span>
                  Manual
                </button>
                
                {/* Simulated Shutter */}
                <button 
                  onClick={() => fileInputRef.current?.click()}
                  className="w-20 h-20 bg-white rounded-full flex items-center justify-center p-1 active:scale-90 transition-transform duration-100"
                >
                  <div className="w-full h-full border-4 border-slate-950 rounded-full bg-white"></div>
                </button>

                <button 
                  onClick={() => fileInputRef.current?.click()}
                  className="text-xs hover:opacity-70 text-white/80 flex flex-col items-center gap-1 active:scale-95"
                >
                  <span className="material-symbols-outlined text-[24px]">photo_library</span>
                  Upload
                </button>
              </div>
            </div>
          </div>
        )}

        {/* ========================================================================= */}
        {/* 3. REVIEW & EDIT RECEIPT SCREEN */}
        {/* ========================================================================= */}
        {screen === 'review' && (
          <div className="flex-1 flex flex-col h-full overflow-hidden bg-background">
            
            {/* Header */}
            <header className="flex justify-between items-center px-container-padding h-16 w-full bg-surface/80 backdrop-blur-xl sticky top-0 z-50 border-b border-surface-container-high/20">
              <button 
                onClick={() => setScreen('capture')}
                className="w-10 h-10 flex items-center justify-center text-primary hover:opacity-70 transition-opacity active:scale-95"
              >
                <span className="material-symbols-outlined">arrow_back</span>
              </button>
              <h1 className="text-md font-serif font-bold text-primary">Confirm Details</h1>
              <button className="w-10 h-10 flex items-center justify-center text-on-surface-variant hover:opacity-70 active:scale-95">
                <span className="material-symbols-outlined">more_horiz</span>
              </button>
            </header>

            <main className="flex-1 overflow-y-auto px-container-padding py-stack-gap-md pb-32 hide-scrollbar">
              <p className="text-xs text-on-surface-variant mb-4">Tap any item to edit details. Ensure quantities and unit prices match your physical receipt.</p>

              {/* Receipt Table Container */}
              <div className="bg-surface-container-lowest rounded-3xl shadow-[0_2px_12px_rgba(0,0,0,0.04)] border border-surface-container-high overflow-hidden mb-6">
                
                {/* Table Header */}
                <div className="grid grid-cols-[3fr_1fr_1.5fr] gap-4 px-5 py-3 bg-surface-gray border-b border-surface-container-high text-[10px] font-semibold text-on-surface-variant uppercase tracking-wider">
                  <div>Item</div>
                  <div className="text-center">Qty</div>
                  <div className="text-right">Total (ETB)</div>
                </div>

                {/* Table Body */}
                <div className="divide-y divide-surface-container-high">
                  {lineItems.length === 0 ? (
                    <div className="p-6 text-center text-xs text-outline">No items added yet.</div>
                  ) : (
                    lineItems.map((item) => (
                      <button 
                        key={item.id}
                        onClick={() => setEditingItem({ ...item })}
                        className="w-full grid grid-cols-[3fr_1fr_1.5fr] gap-4 px-5 py-4 items-center text-left hover:bg-surface-container-low transition-colors active:bg-surface-container group"
                      >
                        <div className="flex flex-col">
                          <span className="text-sm font-semibold text-on-surface line-clamp-1">{item.description}</span>
                          <span className="text-[10px] text-on-surface-variant">{item.unitPrice.toFixed(2)} ea</span>
                        </div>
                        <div className="text-center">
                          <span className="inline-block bg-surface-gray text-on-surface rounded-full px-2.5 py-0.5 text-xs font-bold">{item.quantity}</span>
                        </div>
                        <div className="text-right flex items-center justify-end gap-1.5">
                          <span className="text-sm font-semibold font-mono">{item.amount.toFixed(2)}</span>
                          <span className="material-symbols-outlined text-[14px] text-surface-tint opacity-0 group-hover:opacity-100 transition-opacity">edit</span>
                        </div>
                      </button>
                    ))
                  )}

                  {/* Add Missing Item Button */}
                  <button 
                    onClick={() => setAddingItem({ description: '', quantity: 1, unitPrice: 0 })}
                    className="w-full flex items-center justify-center gap-1.5 px-5 py-4 text-secondary hover:bg-surface-container-low transition-colors text-xs font-bold border-t border-dashed border-surface-container-high"
                  >
                    <span className="material-symbols-outlined text-[16px]">add</span>
                    Add Missing Item
                  </button>
                </div>
              </div>

              {/* Receipt Summary Card */}
              <div className="bg-surface-container-lowest rounded-3xl p-5 shadow-[0_2px_12px_rgba(0,0,0,0.04)] border border-surface-container-high">
                <div className="flex flex-col gap-3 text-xs">
                  <div className="flex justify-between items-center text-on-surface-variant">
                    <span>Subtotal</span>
                    <span className="font-mono">{receipt.subtotal.toFixed(2)} ETB</span>
                  </div>

                  <div 
                    onClick={() => setEditingFees({ type: 'service', value: receipt.serviceChargeAmount })}
                    className="flex justify-between items-center text-on-surface-variant cursor-pointer hover:text-on-surface transition-colors"
                  >
                    <span className="flex items-center gap-1 border-b border-dashed border-outline-variant">
                      Service Charge 
                      <span className="material-symbols-outlined text-[12px]">edit</span>
                    </span>
                    <span className="font-mono">{receipt.serviceChargeAmount.toFixed(2)} ETB</span>
                  </div>

                  <div 
                    onClick={() => setEditingFees({ type: 'tax', value: receipt.taxRate })}
                    className="flex justify-between items-center text-on-surface-variant cursor-pointer hover:text-on-surface transition-colors"
                  >
                    <span className="flex items-center gap-1 border-b border-dashed border-outline-variant">
                      VAT ({Math.round(receipt.taxRate * 100)}%) 
                      <span className="material-symbols-outlined text-[12px]">edit</span>
                    </span>
                    <span className="font-mono">{receipt.taxAmount.toFixed(2)} ETB</span>
                  </div>

                  <hr className="border-surface-container-high my-1" />
                  
                  <div className="flex justify-between items-end">
                    <span className="text-sm font-bold text-on-surface">Target Bill (Reconciled)</span>
                    <div className="text-right">
                      <span className="text-2xl font-serif font-black text-primary tracking-tight">
                        {Math.ceil(receipt.total)} 
                        <span className="text-xs font-sans text-on-surface-variant font-medium ml-1">ETB</span>
                      </span>
                      <span className="text-[10px] text-outline block">Actual: {receipt.total.toFixed(2)} ETB</span>
                    </div>
                  </div>
                </div>
              </div>
            </main>

            {/* Bottom Action Footer */}
            <div className="absolute bottom-0 left-0 w-full p-4 bg-surface/90 backdrop-blur-2xl border-t border-surface-container-high/40 flex justify-center z-40">
              <button 
                onClick={handleProceedToParticipants}
                className="w-full bg-gradient-to-r from-[#3B82F6] to-[#60A5FA] text-white rounded-full py-4 text-sm font-bold shadow-lg hover:opacity-90 active:scale-[0.98] transition-all flex justify-center items-center gap-2"
              >
                Proceed to Assign
                <span className="material-symbols-outlined text-[18px]">arrow_forward</span>
              </button>
            </div>
          </div>
        )}

        {/* ========================================================================= */}
        {/* 4. PARTICIPANTS SCREEN */}
        {/* ========================================================================= */}
        {screen === 'participants' && (
          <div className="flex-1 flex flex-col h-full overflow-hidden bg-background">
            {/* Header */}
            <header className="flex justify-between items-center px-container-padding h-16 w-full bg-surface/80 backdrop-blur-xl sticky top-0 z-50 border-b border-surface-container-high/20">
              <button 
                onClick={() => setScreen('review')}
                className="w-10 h-10 flex items-center justify-center text-primary hover:opacity-70 transition-opacity active:scale-95"
              >
                <span className="material-symbols-outlined">arrow_back</span>
              </button>
              <h1 className="text-md font-serif font-bold text-primary">Participants</h1>
              <div className="w-10"></div>
            </header>

            <main className="flex-grow overflow-y-auto px-container-padding py-stack-gap-md pb-32 hide-scrollbar">
              
              {/* Add New Participant Form */}
              <form onSubmit={handleAddParticipantSubmit} className="bg-surface-container-lowest rounded-3xl p-5 border border-surface-container-high shadow-[0_2px_12px_rgba(0,0,0,0.04)] mb-6">
                <h3 className="font-serif text-sm font-bold text-on-surface mb-3">Add New Person</h3>
                <div className="flex flex-col gap-3">
                  <div className="flex gap-2">
                    <input 
                      type="text" 
                      placeholder="First Name *"
                      value={newFirstName}
                      onChange={(e) => setNewFirstName(e.target.value)}
                      required
                      className="flex-1 bg-surface-gray border border-surface-container-high rounded-2xl px-4 py-2.5 text-xs text-on-background focus:outline-none focus:border-[#3B82F6]"
                    />
                    <input 
                      type="text" 
                      placeholder="Last Name (opt)"
                      value={newLastName}
                      onChange={(e) => setNewLastName(e.target.value)}
                      className="w-28 bg-surface-gray border border-surface-container-high rounded-2xl px-4 py-2.5 text-xs text-on-background focus:outline-none focus:border-[#3B82F6]"
                    />
                  </div>
                  <button 
                    type="submit"
                    className="bg-primary text-white rounded-2xl py-2.5 text-xs font-bold active:scale-95 transition-transform flex items-center justify-center gap-1"
                  >
                    <span className="material-symbols-outlined text-[16px]">add</span> Add Participant
                  </button>
                </div>
              </form>

              {/* Selected List */}
              <section className="mb-6">
                <h3 className="font-serif text-sm font-bold text-on-surface-variant mb-3 px-1">Selected for this split</h3>
                
                {activeParticipants.length === 0 ? (
                  <div className="text-center py-6 text-xs text-outline bg-surface-gray/50 rounded-2xl border border-dashed border-surface-container-high">
                    No one selected yet. Choose from below or add a new person.
                  </div>
                ) : (
                  <div className="flex flex-wrap gap-2">
                    {activeParticipants.map((p) => (
                      <div 
                        key={p.id}
                        className="bg-surface-blue border border-[#60A5FA]/40 rounded-full px-3 py-1.5 text-xs font-semibold text-[#3B82F6] flex items-center gap-1.5 shadow-sm"
                      >
                        <span className="uppercase">{p.firstName.charAt(0)}</span>
                        <span>{p.lastName ? `${p.firstName} ${p.lastName.charAt(0)}.` : p.firstName}</span>
                        <button 
                          onClick={() => removeActiveParticipant(p.id)}
                          className="hover:text-error-red active:scale-75 transition-transform flex items-center justify-center"
                        >
                          <span className="material-symbols-outlined text-[16px]">close</span>
                        </button>
                      </div>
                    ))}
                  </div>
                )}
              </section>

              {/* Recent list of participants */}
              {recentParticipants.length > 0 && (
                <section>
                  <h3 className="font-serif text-sm font-bold text-on-surface-variant mb-3 px-1">Recent People</h3>
                  <div className="grid grid-cols-2 gap-2">
                    {recentParticipants.map((rp) => {
                      const isSelected = activeParticipants.some(ap => ap.id === rp.id);
                      return (
                        <button
                          key={rp.id}
                          onClick={() => toggleRecentParticipant(rp.id)}
                          className={`flex items-center gap-3 p-3 rounded-2xl border text-left active:scale-[0.98] transition-all ${
                            isSelected 
                              ? 'bg-surface-blue border-[#60A5FA] shadow-sm' 
                              : 'bg-surface-container-lowest border-surface-container-high hover:bg-surface-container-low'
                          }`}
                        >
                          <div className={`w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold uppercase ${
                            isSelected ? 'bg-[#3B82F6] text-white' : 'bg-surface-gray text-on-surface-variant'
                          }`}>
                            {rp.firstName.charAt(0)}
                          </div>
                          <div className="flex-1 min-w-0">
                            <p className={`text-xs font-bold truncate ${isSelected ? 'text-[#3B82F6]' : 'text-on-background'}`}>
                              {rp.firstName} {rp.lastName}
                            </p>
                          </div>
                          {isSelected && (
                            <span className="material-symbols-outlined text-[16px] text-[#3B82F6]">check_circle</span>
                          )}
                        </button>
                      );
                    })}
                  </div>
                </section>
              )}
            </main>

            {/* Bottom Action Footer */}
            <div className="absolute bottom-0 left-0 w-full p-4 bg-surface/90 backdrop-blur-2xl border-t border-surface-container-high/40 flex justify-center z-40">
              <button 
                onClick={handleProceedToAssign}
                disabled={activeParticipants.length === 0}
                className="w-full bg-gradient-to-r from-[#3B82F6] to-[#60A5FA] text-white rounded-full py-4 text-sm font-bold shadow-lg hover:opacity-90 active:scale-[0.98] transition-all flex justify-center items-center gap-2 disabled:opacity-50"
              >
                Proceed to Assignment
                <span className="material-symbols-outlined text-[18px]">arrow_forward</span>
              </button>
            </div>
          </div>
        )}

        {/* ========================================================================= */}
        {/* 5. ASSIGN ITEMS SCREEN */}
        {/* ========================================================================= */}
        {screen === 'assign' && units.length > 0 && (
          <div className="flex-1 flex flex-col h-full overflow-hidden bg-background">
            
            {/* Header */}
            <header className="flex justify-between items-center px-container-padding h-16 w-full bg-surface/80 backdrop-blur-xl sticky top-0 z-50 border-b border-surface-container-high/20">
              <button 
                onClick={() => setScreen('participants')}
                className="w-10 h-10 flex items-center justify-center text-primary hover:opacity-70 transition-opacity active:scale-95"
              >
                <span className="material-symbols-outlined">arrow_back</span>
              </button>
              <h1 className="text-md font-serif font-bold text-primary">Assign Items</h1>
              <div className="w-10"></div>
            </header>

            {/* Top progress indicator bar */}
            <div className="w-full h-1 bg-surface-container-high sticky z-40 top-16">
              <div 
                style={{ width: `${((activeUnitIndex + 1) / units.length) * 100}%` }}
                className="h-full bg-gradient-to-r from-[#3B82F6] to-[#60A5FA] transition-all duration-300 ease-out"
              ></div>
            </div>

            <main className="flex-grow overflow-y-auto px-container-padding py-stack-gap-md pb-[180px] hide-scrollbar mt-2">
              
              {/* Active Item Card (Bento style) */}
              <section className="bg-surface-container-lowest rounded-3xl p-6 shadow-[0_4px_16px_rgba(0,0,0,0.04)] border border-surface-container-high/60 relative overflow-hidden mb-6">
                <div className="absolute -right-8 -top-8 w-28 h-28 bg-surface-blue rounded-full blur-2xl opacity-40"></div>
                
                <div className="flex justify-between items-start z-10 relative">
                  <div className="flex flex-col gap-0.5">
                    <span className="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">Item {activeUnitIndex + 1} of {units.length}</span>
                    <h2 className="font-serif text-xl font-bold text-primary tracking-tight pr-4">
                      {units[activeUnitIndex].description}
                    </h2>
                  </div>
                  <div className="bg-surface-gray px-2.5 py-1 rounded-lg text-xs font-bold">
                    Unit Price
                  </div>
                </div>

                <div className="flex items-end justify-between mt-6 z-10 relative">
                  <div className="flex items-center gap-1.5 text-on-surface-variant text-xs">
                    <span className="material-symbols-outlined text-[16px]">info</span>
                    <span>Tapping select splits cost equally</span>
                  </div>
                  <div className="flex flex-col items-end">
                    <span className="text-2xl font-black font-mono text-primary leading-none">
                      {units[activeUnitIndex].unitPrice.toFixed(2)}
                      <span className="text-xs font-sans text-on-surface-variant font-medium ml-1">ETB</span>
                    </span>
                  </div>
                </div>
              </section>

              {/* Assignment Selector */}
              <section className="flex flex-col gap-3">
                <div className="flex items-center justify-between px-1">
                  <h3 className="font-serif text-sm font-bold text-on-surface-variant">Assign to</h3>
                  <button 
                    onClick={() => {
                      const allIds = activeParticipants.map(p => p.id);
                      const currentAssigned = units[activeUnitIndex].assignments.map(a => a.participantId);
                      const areAllSelected = allIds.length === currentAssigned.length;
                      
                      // Clear or select all
                      activeParticipants.forEach(p => {
                        const isSelected = currentAssigned.includes(p.id);
                        if (areAllSelected || !isSelected) {
                          assignUnitParticipant(units[activeUnitIndex].id, p.id);
                        }
                      });
                    }}
                    className="text-xs font-bold text-primary hover:opacity-70 transition-opacity"
                  >
                    {units[activeUnitIndex].assignments.length === activeParticipants.length ? 'Clear All' : 'Select All'}
                  </button>
                </div>

                {/* Participant Grid */}
                <div className="grid grid-cols-2 gap-3">
                  {activeParticipants.map((p) => {
                    const assignment = units[activeUnitIndex].assignments.find(a => a.participantId === p.id);
                    const isSelected = !!assignment;
                    
                    return (
                      <button
                        key={p.id}
                        onClick={() => assignUnitParticipant(units[activeUnitIndex].id, p.id)}
                        className={`group flex flex-col items-center justify-center gap-2 rounded-[20px] p-4 border-2 transition-all duration-200 active:scale-95 ${
                          isSelected 
                            ? 'bg-surface-blue border-[#60A5FA] shadow-md shadow-blue-500/5' 
                            : 'bg-surface-gray border-transparent hover:bg-surface-container-high'
                        }`}
                      >
                        <div className={`w-12 h-12 rounded-full flex items-center justify-center text-sm font-bold uppercase relative ${
                          isSelected ? 'bg-[#3B82F6] text-white' : 'bg-surface-dim text-on-surface-variant'
                        }`}>
                          {p.firstName.charAt(0)}
                          
                          {/* Checkmark badge */}
                          {isSelected && (
                            <div className="absolute -bottom-1 -right-1 bg-[#3b82f6] text-white rounded-full w-5 h-5 flex items-center justify-center border-2 border-surface-blue">
                              <span className="material-symbols-outlined text-[12px] font-bold">check</span>
                            </div>
                          )}
                        </div>

                        <span className={`text-xs font-bold ${isSelected ? 'text-[#3B82F6]' : 'text-on-surface-variant group-hover:text-primary'}`}>
                          {p.firstName}
                        </span>

                        {isSelected && assignment.share < 1 && (
                          <span className="text-[10px] font-semibold text-outline leading-none mt-0.5">
                            Share: {Math.round(assignment.share * 100)}% ({ (units[activeUnitIndex].unitPrice * assignment.share).toFixed(2) } ETB)
                          </span>
                        )}
                      </button>
                    );
                  })}
                </div>

                {/* Custom Ratio Trigger Button */}
                {units[activeUnitIndex].assignments.length > 1 && (
                  <button
                    onClick={() => setEditingCustomShares({
                      unitId: units[activeUnitIndex].id,
                      description: units[activeUnitIndex].description,
                      price: units[activeUnitIndex].unitPrice
                    })}
                    className="mt-2 text-center text-xs font-bold text-secondary hover:text-primary underline py-2"
                  >
                    Adjust custom split ratios (weights)
                  </button>
                )}
              </section>
            </main>

            {/* Bottom Floating Navigation footer */}
            <div className="absolute bottom-0 left-0 w-full bg-surface/90 backdrop-blur-2xl border-t border-surface-container-high/40 p-4 pb-6 z-50 flex flex-col gap-3">
              <div className="flex items-center justify-between px-2">
                
                {/* Dots indicator for item items */}
                <div className="flex items-center gap-1.5 overflow-x-auto max-w-[200px] py-1">
                  {units.map((u, idx) => {
                    const isAssigned = u.assignments.length > 0;
                    return (
                      <button 
                        key={u.id}
                        onClick={() => setActiveUnitIndex(idx)}
                        className={`h-2.5 rounded-full transition-all duration-300 ${
                          idx === activeUnitIndex 
                            ? 'w-5 bg-[#3B82F6]' 
                            : isAssigned 
                              ? 'w-2.5 bg-success-green' 
                              : 'w-2.5 bg-surface-dim hover:bg-slate-400'
                        }`}
                      />
                    );
                  })}
                </div>

                <span className="text-[10px] font-bold text-on-surface-variant bg-surface-gray px-3 py-1 rounded-full">
                  {units.filter(u => u.assignments.length === 0).length} items left
                </span>
              </div>

              <div className="flex gap-2">
                <button 
                  onClick={() => setActiveUnitIndex(prev => Math.max(0, prev - 1))}
                  disabled={activeUnitIndex === 0}
                  className="bg-surface-gray text-primary border border-surface-container-high rounded-2xl py-3.5 px-4 flex items-center justify-center disabled:opacity-30 active:scale-95"
                >
                  <span className="material-symbols-outlined">arrow_back</span>
                </button>

                {activeUnitIndex < units.length - 1 ? (
                  <button 
                    onClick={() => setActiveUnitIndex(prev => prev + 1)}
                    className="flex-1 bg-gradient-to-r from-[#3B82F6] to-[#60A5FA] text-white rounded-2xl py-3.5 flex items-center justify-center gap-1.5 font-bold shadow-md active:scale-95 transition-transform"
                  >
                    <span>Next Item</span>
                    <span className="material-symbols-outlined text-[18px]">arrow_forward</span>
                  </button>
                ) : (
                  <button 
                    onClick={handleCalculateSplit}
                    className="flex-1 bg-primary text-white rounded-2xl py-3.5 flex items-center justify-center gap-1.5 font-bold shadow-md active:scale-95 transition-transform"
                  >
                    <span className="material-symbols-outlined text-[18px]">calculate</span>
                    <span>Calculate Split</span>
                  </button>
                )}
              </div>
            </div>
          </div>
        )}

        {/* ========================================================================= */}
        {/* 6. SUMMARY SCREEN */}
        {/* ========================================================================= */}
        {screen === 'summary' && (
          <div className="flex-1 flex flex-col h-full overflow-hidden bg-surface-blue relative">
            
            {/* Confetti Animation Background */}
            <div className="absolute inset-0 pointer-events-none z-0 overflow-hidden">
              <div className="confetti-piece animate-fall-1 rounded-full"></div>
              <div className="confetti-piece animate-fall-2 rounded-sm"></div>
              <div className="confetti-piece animate-fall-3 rounded-full"></div>
              <div className="confetti-piece animate-fall-4 rounded-sm"></div>
              <div className="confetti-piece animate-fall-5 rounded-full"></div>
            </div>

            {/* Header */}
            <header className="flex justify-between items-center px-container-padding h-16 w-full bg-surface/80 backdrop-blur-xl sticky top-0 z-50 border-b border-[#a8d7ff]/20">
              <button 
                onClick={() => setScreen('home')}
                className="w-10 h-10 flex items-center justify-center text-primary hover:opacity-70 transition-opacity active:scale-95 rounded-full"
              >
                <span className="material-symbols-outlined">arrow_back</span>
              </button>
              <h1 className="text-md font-serif font-bold text-primary text-center">Fair Split</h1>
              <div className="w-10"></div>
            </header>

            <main className="flex-grow overflow-y-auto px-container-padding py-stack-gap-md pb-32 z-10 hide-scrollbar">
              
              {/* Success Check circle */}
              <div className="text-center mb-8 flex flex-col items-center">
                <div className="w-16 h-16 bg-primary text-white rounded-full flex items-center justify-center mb-4 shadow-md">
                  <span className="material-symbols-outlined text-3xl filled">check_circle</span>
                </div>
                <h2 className="text-xl font-serif font-bold text-primary mb-1">All Settled Up!</h2>
                <p className="text-xs text-on-surface-variant">Roundings reconciled. Here is the final breakdown.</p>
              </div>

              {/* Total Summary Card */}
              <div className="bg-surface-container-lowest rounded-3xl p-5 shadow-[0_4px_16px_rgba(0,0,0,0.04)] mb-6 flex flex-col items-center border border-surface-variant/30 relative overflow-hidden">
                <div className="absolute -top-10 -right-10 w-28 h-28 bg-secondary-fixed rounded-full opacity-30 blur-2xl pointer-events-none"></div>
                <span className="text-[10px] font-bold text-on-surface-variant uppercase tracking-wider mb-1 z-10">Total Bill Target</span>
                <div className="text-3xl font-serif font-black text-primary z-10 flex items-baseline gap-1">
                  <span>{Math.ceil(receipt.total).toFixed(2)}</span>
                  <span className="text-sm font-sans font-bold text-outline">ETB</span>
                </div>
                <div className="mt-3 flex items-center gap-1 bg-success-green/10 text-success-green px-3.5 py-1 rounded-full z-10 text-[10px] font-bold">
                  <span className="material-symbols-outlined text-[14px]">task_alt</span>
                  <span>Perfectly Reconciled</span>
                </div>
              </div>

              {/* Breakdown title */}
              <h3 className="font-serif text-md font-bold text-primary mb-3 px-1">Who owes what</h3>
              
              {/* Participant breakdown lists */}
              <div className="flex flex-col gap-3">
                {computeSplit(receipt, activeParticipants, units).map((res) => {
                  const p = activeParticipants.find(ap => ap.id === res.participantId)!;
                  const name = p.lastName ? `${p.firstName} ${p.lastName}` : p.firstName;
                  const isExpanded = expandedParticipantId === p.id;

                  // Find items assigned to this participant
                  const pUnits = units.filter(u => u.assignments.some(a => a.participantId === p.id));

                  return (
                    <div 
                      key={p.id}
                      className="bg-surface-container-lowest rounded-2xl shadow-[0_2px_10px_rgba(0,0,0,0.02)] border border-surface-container/50 overflow-hidden transition-all duration-300"
                    >
                      {/* Main Card row (tappable to expand details) */}
                      <button 
                        onClick={() => setExpandedParticipantId(isExpanded ? null : p.id)}
                        className="w-full flex items-center justify-between p-4 text-left active:bg-surface-container-low transition-colors"
                      >
                        <div className="flex items-center gap-3">
                          <div className="w-10 h-10 bg-accent-pink/20 text-[#3B82F6] rounded-full flex items-center justify-center text-xs font-black uppercase">
                            {p.firstName.charAt(0)}
                          </div>
                          <div className="flex flex-col">
                            <span className="text-sm font-bold text-primary">{name}</span>
                            <span className="text-[10px] text-on-surface-variant flex items-center gap-0.5 mt-0.5">
                              <span className="material-symbols-outlined text-[12px]">receipt_long</span> 
                              {pUnits.length} items
                            </span>
                          </div>
                        </div>

                        <div className="text-right flex items-center gap-2">
                          <div>
                            <div className="text-sm font-serif font-black text-primary font-mono">{res.totalOwed.toFixed(2)}</div>
                            <div className="text-[10px] text-outline">ETB</div>
                          </div>
                          <span className={`material-symbols-outlined text-outline transition-transform duration-200 ${
                            isExpanded ? 'rotate-180' : ''
                          }`}>
                            expand_more
                          </span>
                        </div>
                      </button>

                      {/* Expanded Section */}
                      {isExpanded && (
                        <div className="bg-surface-gray/40 border-t border-surface-container-high/40 p-4 text-xs text-on-surface-variant flex flex-col gap-2.5">
                          {/* Itemized list */}
                          <div className="flex flex-col gap-1.5">
                            <span className="font-bold text-[10px] uppercase tracking-wider text-outline">Items Ordered</span>
                            {pUnits.map((u) => {
                              const ua = u.assignments.find(a => a.participantId === p.id)!;
                              const cost = u.unitPrice * ua.share;
                              return (
                                <div key={u.id} className="flex justify-between items-center text-on-surface">
                                  <span>
                                    {u.description} 
                                    {ua.share < 1 && <span className="text-[10px] text-outline ml-1">({Math.round(ua.share * 100)}% share)</span>}
                                  </span>
                                  <span className="font-mono">{cost.toFixed(2)} ETB</span>
                                </div>
                              );
                            })}
                          </div>
                          
                          <hr className="border-surface-container-high/60 my-0.5" />

                          {/* Allocation math breakdown */}
                          <div className="flex flex-col gap-1 text-[11px]">
                            <div className="flex justify-between">
                              <span>Items Subtotal</span>
                              <span className="font-mono text-on-surface">{res.itemSubtotal.toFixed(2)} ETB</span>
                            </div>
                            <div className="flex justify-between">
                              <span>Service Charge Share</span>
                              <span className="font-mono text-on-surface">+{res.serviceChargeShare.toFixed(2)} ETB</span>
                            </div>
                            <div className="flex justify-between">
                              <span>VAT (15%) Share</span>
                              <span className="font-mono text-on-surface">+{res.taxShare.toFixed(2)} ETB</span>
                            </div>
                            <div className="flex justify-between font-bold text-primary mt-1 border-t border-dashed border-surface-container-high/60 pt-1">
                              <span>Final Reconciled Share</span>
                              <span className="font-mono">{res.totalOwed.toFixed(2)} ETB</span>
                            </div>
                          </div>
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            </main>

            {/* Bottom Float share bar */}
            <div className="absolute bottom-0 left-0 w-full p-4 bg-gradient-to-t from-surface-blue via-surface-blue/90 to-transparent z-40 pb-6 flex justify-center">
              <button 
                onClick={handleShare}
                className="w-full max-w-md bg-primary text-white text-sm font-bold py-4 rounded-full shadow-lg flex items-center justify-center gap-2 active:scale-[0.98] transition-transform duration-100"
              >
                <span className="material-symbols-outlined text-[18px]">share</span>
                <span>Share Breakdown</span>
              </button>
            </div>
          </div>
        )}

      </div>

      {/* ========================================================================= */}
      {/* DIALOG MODALS SECTION (WEB COMPATIBILITY) */}
      {/* ========================================================================= */}
      
      {/* Edit Line Item Dialog */}
      {editingItem && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-xs flex items-center justify-center p-4 z-50">
          <div className="bg-background rounded-3xl p-6 w-full max-w-sm border border-surface-container-high shadow-2xl flex flex-col gap-4">
            <h3 className="font-serif text-lg font-bold text-primary">Edit Item</h3>
            
            <div className="flex flex-col gap-3 text-xs">
              <div className="flex flex-col gap-1">
                <label className="font-semibold text-outline">Description</label>
                <input 
                  type="text" 
                  value={editingItem.description}
                  onChange={(e) => setEditingItem({ ...editingItem, description: e.target.value })}
                  className="bg-surface-gray border border-surface-container-high rounded-xl px-4 py-2 text-on-background focus:outline-none focus:border-[#3B82F6]"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div className="flex flex-col gap-1">
                  <label className="font-semibold text-outline">Quantity</label>
                  <input 
                    type="number" 
                    min="1"
                    value={editingItem.quantity}
                    onChange={(e) => setEditingItem({ ...editingItem, quantity: parseInt(e.target.value) || 1 })}
                    className="bg-surface-gray border border-surface-container-high rounded-xl px-4 py-2 text-on-background focus:outline-none focus:border-[#3B82F6]"
                  />
                </div>
                <div className="flex flex-col gap-1">
                  <label className="font-semibold text-outline">Unit Price (ETB)</label>
                  <input 
                    type="number" 
                    step="0.01"
                    min="0"
                    value={editingItem.unitPrice}
                    onChange={(e) => setEditingItem({ ...editingItem, unitPrice: parseFloat(e.target.value) || 0 })}
                    className="bg-surface-gray border border-surface-container-high rounded-xl px-4 py-2 text-on-background focus:outline-none focus:border-[#3B82F6]"
                  />
                </div>
              </div>
            </div>

            <div className="flex justify-between items-center mt-2 gap-2 text-xs">
              <button 
                onClick={() => {
                  deleteLineItem(editingItem.id);
                  setEditingItem(null);
                }}
                className="bg-error-red/10 text-error-red border border-error-red/20 rounded-xl px-4 py-2.5 font-bold hover:bg-error-red/25 active:scale-95"
              >
                Delete Item
              </button>

              <div className="flex gap-2">
                <button 
                  onClick={() => setEditingItem(null)}
                  className="bg-surface-gray text-on-surface-variant border border-surface-container-high rounded-xl px-4 py-2.5 font-bold hover:bg-surface-container-high active:scale-95"
                >
                  Cancel
                </button>
                <button 
                  onClick={() => {
                    updateLineItem(editingItem.id, {
                      description: editingItem.description,
                      quantity: editingItem.quantity,
                      unitPrice: editingItem.unitPrice
                    });
                    setEditingItem(null);
                  }}
                  className="bg-primary text-white rounded-xl px-4 py-2.5 font-bold active:scale-95"
                >
                  Save
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Add Line Item Dialog */}
      {addingItem && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-xs flex items-center justify-center p-4 z-50">
          <div className="bg-background rounded-3xl p-6 w-full max-w-sm border border-surface-container-high shadow-2xl flex flex-col gap-4">
            <h3 className="font-serif text-lg font-bold text-primary">Add Missing Item</h3>
            
            <div className="flex flex-col gap-3 text-xs">
              <div className="flex flex-col gap-1">
                <label className="font-semibold text-outline">Description</label>
                <input 
                  type="text" 
                  placeholder="e.g. Novida"
                  value={addingItem.description}
                  onChange={(e) => setAddingItem({ ...addingItem, description: e.target.value })}
                  className="bg-surface-gray border border-surface-container-high rounded-xl px-4 py-2 text-on-background focus:outline-none focus:border-[#3B82F6]"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div className="flex flex-col gap-1">
                  <label className="font-semibold text-outline">Quantity</label>
                  <input 
                    type="number" 
                    min="1"
                    value={addingItem.quantity}
                    onChange={(e) => setAddingItem({ ...addingItem, quantity: parseInt(e.target.value) || 1 })}
                    className="bg-surface-gray border border-surface-container-high rounded-xl px-4 py-2 text-on-background focus:outline-none focus:border-[#3B82F6]"
                  />
                </div>
                <div className="flex flex-col gap-1">
                  <label className="font-semibold text-outline">Unit Price (ETB)</label>
                  <input 
                    type="number" 
                    step="0.01"
                    min="0"
                    value={addingItem.unitPrice}
                    onChange={(e) => setAddingItem({ ...addingItem, unitPrice: parseFloat(e.target.value) || 0 })}
                    className="bg-surface-gray border border-surface-container-high rounded-xl px-4 py-2 text-on-background focus:outline-none focus:border-[#3B82F6]"
                  />
                </div>
              </div>
            </div>

            <div className="flex justify-end gap-2 text-xs mt-2">
              <button 
                onClick={() => setAddingItem(null)}
                className="bg-surface-gray text-on-surface-variant border border-surface-container-high rounded-xl px-4 py-2.5 font-bold active:scale-95"
              >
                Cancel
              </button>
              <button 
                onClick={() => {
                  if (!addingItem.description.trim()) {
                    alert('Please enter a description.');
                    return;
                  }
                  addLineItem({
                    description: addingItem.description.trim(),
                    quantity: addingItem.quantity,
                    unitPrice: addingItem.unitPrice
                  });
                  setAddingItem(null);
                }}
                className="bg-primary text-white rounded-xl px-4 py-2.5 font-bold active:scale-95"
              >
                Add Item
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Edit Fees Dialog (Service Charge & VAT) */}
      {editingFees && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-xs flex items-center justify-center p-4 z-50">
          <div className="bg-background rounded-3xl p-6 w-full max-w-sm border border-surface-container-high shadow-2xl flex flex-col gap-4">
            <h3 className="font-serif text-lg font-bold text-primary">
              Edit {editingFees.type === 'service' ? 'Service Charge' : 'VAT Percentage'}
            </h3>
            
            <div className="flex flex-col gap-1 text-xs">
              <label className="font-semibold text-outline">
                {editingFees.type === 'service' ? 'Absolute Amount (ETB)' : 'Tax Rate (fraction: e.g. 0.15 for 15%)'}
              </label>
              <input 
                type="number" 
                step="0.01"
                min="0"
                value={editingFees.value}
                onChange={(e) => setEditingFees({ ...editingFees, value: parseFloat(e.target.value) || 0 })}
                className="bg-surface-gray border border-surface-container-high rounded-xl px-4 py-2 text-on-background focus:outline-none focus:border-[#3B82F6]"
              />
            </div>

            <div className="flex justify-end gap-2 text-xs mt-2">
              <button 
                onClick={() => setEditingFees(null)}
                className="bg-surface-gray text-on-surface-variant border border-surface-container-high rounded-xl px-4 py-2.5 font-bold active:scale-95"
              >
                Cancel
              </button>
              <button 
                onClick={() => {
                  if (editingFees.type === 'service') {
                    const newService = editingFees.value;
                    const newTax = parseFloat(((receipt.subtotal + newService) * receipt.taxRate).toFixed(2));
                    const newTotal = parseFloat((receipt.subtotal + newService + newTax).toFixed(2));
                    setReceipt({
                      serviceChargeAmount: newService,
                      taxAmount: newTax,
                      total: newTotal
                    });
                  } else {
                    const newRate = editingFees.value;
                    const newTax = parseFloat(((receipt.subtotal + receipt.serviceChargeAmount) * newRate).toFixed(2));
                    const newTotal = parseFloat((receipt.subtotal + receipt.serviceChargeAmount + newTax).toFixed(2));
                    setReceipt({
                      taxRate: newRate,
                      taxAmount: newTax,
                      total: newTotal
                    });
                  }
                  setEditingFees(null);
                }}
                className="bg-primary text-white rounded-xl px-4 py-2.5 font-bold active:scale-95"
              >
                Save
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Edit Custom Split Weights Dialog */}
      {editingCustomShares && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-xs flex items-center justify-center p-4 z-50">
          <div className="bg-background rounded-3xl p-6 w-full max-w-sm border border-surface-container-high shadow-2xl flex flex-col gap-4">
            <h3 className="font-serif text-lg font-bold text-primary">Custom Split Weights</h3>
            <p className="text-xs text-on-surface-variant">Adjust weight values to split {editingCustomShares.description} ({editingCustomShares.price.toFixed(2)} ETB) proportionally.</p>
            
            <div className="flex flex-col gap-3 max-h-[300px] overflow-y-auto pr-1">
              {(() => {
                const unit = units.find(u => u.id === editingCustomShares.unitId)!;
                return activeParticipants
                  .filter(p => unit.assignments.some(a => a.participantId === p.id))
                  .map((p) => {
                    const assignment = unit.assignments.find(a => a.participantId === p.id)!;
                    
                    // Let's use relative weights. By default weight can be relative to share or custom
                    // We can let them input a weight (e.g. 1, 2, 0.5)
                    const currentWeight = assignment.share > 0 ? (assignment.share * 100) : 0;

                    return (
                      <div key={p.id} className="flex justify-between items-center gap-2 text-xs">
                        <span className="font-bold flex-1">{p.firstName}</span>
                        <div className="flex items-center gap-1.5">
                          <input 
                            type="number"
                            min="0"
                            placeholder="Weight"
                            defaultValue={Math.round(currentWeight)}
                            id={`weight-${p.id}`}
                            className="w-20 bg-surface-gray border border-surface-container-high rounded-xl px-3 py-1.5 text-center text-xs text-on-background focus:outline-none focus:border-[#3B82F6]"
                          />
                          <span className="text-outline">pts</span>
                        </div>
                      </div>
                    );
                  });
              })()}
            </div>

            <div className="flex justify-end gap-2 text-xs mt-2">
              <button 
                onClick={() => setEditingCustomShares(null)}
                className="bg-surface-gray text-on-surface-variant border border-surface-container-high rounded-xl px-4 py-2.5 font-bold active:scale-95"
              >
                Cancel
              </button>
              <button 
                onClick={() => {
                  const unit = units.find(u => u.id === editingCustomShares.unitId)!;
                  
                  // Read the input weights
                  const weightInputs: { participantId: string; weight: number }[] = [];
                  let sumWeights = 0;
                  
                  unit.assignments.forEach(a => {
                    const el = document.getElementById(`weight-${a.participantId}`) as HTMLInputElement;
                    const val = el ? parseFloat(el.value) : 1;
                    const weight = isNaN(val) || val < 0 ? 0 : val;
                    weightInputs.push({ participantId: a.participantId, weight });
                    sumWeights += weight;
                  });

                  if (sumWeights === 0) {
                    alert('Sum of weights must be greater than 0.');
                    return;
                  }

                  // Recalculate shares
                  const newShares = weightInputs.map(wi => ({
                    participantId: wi.participantId,
                    share: wi.weight / sumWeights
                  }));

                  setUnitCustomShares(editingCustomShares.unitId, newShares);
                  setEditingCustomShares(null);
                }}
                className="bg-primary text-white rounded-xl px-4 py-2.5 font-bold active:scale-95"
              >
                Apply Custom Ratio
              </button>
            </div>
          </div>
        </div>
      )}

    </div>
  );
}
