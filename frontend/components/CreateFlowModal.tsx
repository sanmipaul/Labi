'use client';

import { useState } from 'react';
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { IntentRegistryABI, IntentRegistryAddress } from '@/lib/contracts';
import { encodeAbiParameters, parseAbiParameters } from 'viem';
import { TokenModal } from '@/components/TokenModal';

type TriggerType = 'time' | 'price';
type ActionType = 'swap' | 'crossChainSwap';

type Token = {
  symbol: string;
  name: string;
  address: string;
};

type Token = {
  symbol: string;
  name: string;
  address: string;
};

const DEFAULT_TOKEN_IN: Token = { symbol: 'USDC', name: 'USD Coin', address: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913' };
const DEFAULT_TOKEN_OUT: Token = { symbol: 'ETH', name: 'Ethereum', address: '0x0000000000000000000000000000000000000000' };

export function CreateFlowModal({ isOpen, onClose }: { isOpen: boolean; onClose: () => void }) {
  const [step, setStep] = useState(1);
  const [triggerType, setTriggerType] = useState<TriggerType>('time');
  const [actionType, setActionType] = useState<ActionType>('swap');

  // Trigger State
  const [frequency, setFrequency] = useState('daily');
  const [time, setTime] = useState('00:00');
  
  // Condition State
  const [minBalance, setMinBalance] = useState('');
  
  // Action State
  const [swapAmount, setSwapAmount] = useState('');
  const [tokenIn, setTokenIn] = useState<Token>(DEFAULT_TOKEN_IN);
  const [tokenOut, setTokenOut] = useState<Token>(DEFAULT_TOKEN_OUT);
  const [dstEid, setDstEid] = useState('');

  // Modal State
  const [isTokenModalOpen, setIsTokenModalOpen] = useState(false);
  const [selectingFor, setSelectingFor] = useState<'in' | 'out'>('in');

  const { writeContract, data: hash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  const handleCreateFlow = async () => {
    try {
      // 1. Encode Trigger Data
      let triggerData = '0x';
      let typeId = 0;
      let value = BigInt(0);

      if (triggerType === 'time') {
         typeId = 1;
         // Mock encoding for time trigger (dayOfWeek, timeOfDay, lastExecution)
         // For MVP: simple encoding placeholder
         triggerData = encodeAbiParameters(
           parseAbiParameters('uint256, uint256, uint256'),
           [BigInt(1), BigInt(0), BigInt(0)]
         );
      } else {
         typeId = 2;
         value = BigInt(0); // Price target
         triggerData = encodeAbiParameters(
            parseAbiParameters('address, uint256, bool'),
            ['0x0000000000000000000000000000000000000000', BigInt(0), true]
         );
      }

      // 2. Encode Condition Data
      const conditionData = encodeAbiParameters(
        parseAbiParameters('uint256, address'),
        [BigInt(Number(minBalance || 0) * 1e18), '0x0000000000000000000000000000000000000000']
      );

      // 3. Encode Action Data
      const actionData = encodeAbiParameters(
        parseAbiParameters('address, address, uint256, uint256, uint256'),
        [
          tokenIn.address as `0x${string}`, // tokenIn
          tokenOut.address as `0x${string}`, // tokenOut
          BigInt(Number(swapAmount || 0) * 1e18),      // amountIn
          BigInt(0),                                   // amountOutMin
          BigInt(Math.floor(Date.now() / 1000) + 3600) // deadline
        ]
      );

      const actionTypeId = actionType === 'swap' ? 1 : 2;
      const dstEidValue = dstEid ? BigInt(dstEid) : BigInt(0);

      writeContract({
        address: IntentRegistryAddress,
        abi: IntentRegistryABI,
        functionName: 'createFlow',
        args: [
          typeId,
          actionTypeId,
          value,
          triggerData,
          conditionData,
          actionData,
          dstEidValue
        ],
      });
    } catch (e) {
      console.error("Error creating flow:", e);
    }
  };

  const openTokenModal = (type: 'in' | 'out') => {
    setSelectingFor(type);
    setIsTokenModalOpen(true);
  };

  if (!isOpen) return null;

  return (
    <>
      <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4">
        <div className="bg-white dark:bg-gray-900 rounded-2xl w-full max-w-2xl overflow-hidden shadow-2xl border border-gray-200 dark:border-gray-800">
          <div className="p-6 border-b border-gray-200 dark:border-gray-800 flex justify-between items-center">
            <h2 className="text-xl font-bold">Create New Flow</h2>
            <button onClick={onClose} className="text-gray-500 hover:text-gray-700 dark:hover:text-gray-300">
              <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <div className="p-6 max-h-[70vh] overflow-y-auto">
            {/* Success Message */}
            {isSuccess && (
              <div className="mb-6 p-4 bg-green-50 dark:bg-green-900/20 text-green-600 dark:text-green-400 rounded-xl flex items-center gap-2">
                <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                </svg>
                Flow created successfully! Transaction hash: {hash?.slice(0, 6)}...{hash?.slice(-4)}
              </div>
            )}

            {/* Error Message */}
            {error && (
              <div className="mb-6 p-4 bg-red-50 dark:bg-red-900/20 text-red-600 dark:text-red-400 rounded-xl break-words text-sm">
                Error: {error.message.slice(0, 100)}...
              </div>
            )}

            {/* Step Indicator */}
            <div className="flex items-center mb-8 text-sm">
              <div className={`flex items-center ${step >= 1 ? 'text-blue-600' : 'text-gray-400'}`}>
                <div className={`w-8 h-8 rounded-full flex items-center justify-center border-2 ${step >= 1 ? 'border-blue-600 bg-blue-50 dark:bg-blue-900/20' : 'border-gray-300'}`}>1</div>
                <span className="ml-2 font-medium">Trigger</span>
              </div>
              <div className={`flex-1 h-0.5 mx-4 ${step >= 2 ? 'bg-blue-600' : 'bg-gray-200 dark:bg-gray-700'}`} />
              <div className={`flex items-center ${step >= 2 ? 'text-blue-600' : 'text-gray-400'}`}>
                <div className={`w-8 h-8 rounded-full flex items-center justify-center border-2 ${step >= 2 ? 'border-blue-600 bg-blue-50 dark:bg-blue-900/20' : 'border-gray-300'}`}>2</div>
                <span className="ml-2 font-medium">Condition</span>
              </div>
              <div className={`flex-1 h-0.5 mx-4 ${step >= 3 ? 'bg-blue-600' : 'bg-gray-200 dark:bg-gray-700'}`} />
              <div className={`flex items-center ${step >= 3 ? 'text-blue-600' : 'text-gray-400'}`}>
                <div className={`w-8 h-8 rounded-full flex items-center justify-center border-2 ${step >= 3 ? 'border-blue-600 bg-blue-50 dark:bg-blue-900/20' : 'border-gray-300'}`}>3</div>
                <span className="ml-2 font-medium">Action</span>
              </div>
            </div>

            {step === 1 && (
              <div className="space-y-4">
                <h3 className="text-lg font-semibold">Select Trigger Type</h3>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <button
                    onClick={() => setTriggerType('time')}
                    className={`p-4 rounded-xl border-2 text-left transition-all ${
                      triggerType === 'time' 
                      ? 'border-blue-600 bg-blue-50 dark:bg-blue-900/20' 
                      : 'border-gray-200 dark:border-gray-800 hover:border-gray-300'
                    }`}
                  >
                    <div className="font-bold mb-1">Time-Based</div>
                    <div className="text-sm text-gray-500">Execute at specific times or intervals (Cron)</div>
                  </button>
                  <button
                    onClick={() => setTriggerType('price')}
                    className={`p-4 rounded-xl border-2 text-left transition-all ${
                      triggerType === 'price' 
                      ? 'border-blue-600 bg-blue-50 dark:bg-blue-900/20' 
                      : 'border-gray-200 dark:border-gray-800 hover:border-gray-300'
                    }`}
                  >
                    <div className="font-bold mb-1">Price-Based</div>
                    <div className="text-sm text-gray-500">Execute when a token hits a target price</div>
                  </button>
                </div>

                {triggerType === 'time' && (
                  <div className="mt-6 p-4 bg-gray-50 dark:bg-gray-800/50 rounded-xl space-y-4">
                    <div>
                      <label className="block text-sm font-medium mb-1">Frequency</label>
                      <select 
                        value={frequency}
                        onChange={(e) => setFrequency(e.target.value)}
                        className="w-full p-2 rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-800"
                      >
                        <option value="daily">Daily</option>
                        <option value="weekly">Weekly</option>
                        <option value="monthly">Monthly</option>
                      </select>
                    </div>
                    <div>
                      <label className="block text-sm font-medium mb-1">Time (UTC)</label>
                      <input 
                        type="time" 
                        value={time}
                        onChange={(e) => setTime(e.target.value)}
                        className="w-full p-2 rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-800" 
                      />
                    </div>
                  </div>
                )}
              </div>
            )}
            
            {step === 2 && (
              <div className="space-y-4">
                <h3 className="text-lg font-semibold">Set Conditions (Optional)</h3>
                <p className="text-gray-500 text-sm">Define checks that must pass before execution.</p>
                
                <div className="p-4 bg-gray-50 dark:bg-gray-800/50 rounded-xl space-y-4">
                    <div>
                      <label className="block text-sm font-medium mb-1">Minimum Balance Required</label>
                      <div className="flex gap-2">
                        <input 
                          type="number" 
                          placeholder="0.00" 
                          value={minBalance}
                          onChange={(e) => setMinBalance(e.target.value)}
                          className="flex-1 p-2 rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-800"
                        />
                        <select className="w-32 p-2 rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-800">
                          <option>ETH</option>
                          <option>USDC</option>
                        </select>
                      </div>
                    </div>
                </div>
              </div>
            )}

            {step === 3 && (
              <div className="space-y-4">
                <h3 className="text-lg font-semibold">Configure Action</h3>
                <div className="p-4 bg-gray-50 dark:bg-gray-800/50 rounded-xl space-y-4">
                  <div>
                    <label className="block text-sm font-medium mb-1">Action Type</label>
                    <select 
                      value={actionType}
                      onChange={(e) => setActionType(e.target.value as ActionType)}
                      className="w-full p-2 rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-800"
                    >
                      <option value="swap">Swap on this chain</option>
                      <option value="crossChainSwap">Cross-chain Swap</option>
                    </select>
                  </div>
                  {actionType === 'crossChainSwap' && (
                    <div>
                      <label className="block text-sm font-medium mb-1">Destination Chain</label>
                      <select 
                        value={dstEid}
                        onChange={(e) => setDstEid(e.target.value)}
                        className="w-full p-2 rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-800"
                      >
                        <option value="">Select Chain</option>
                        <option value="30101">Ethereum Mainnet</option>
                        <option value="184">Base</option>
                      </select>
                    </div>
                  )}
                  <div>
                      <label className="block text-sm font-medium mb-1">Swap Amount</label>
                      <div className="flex gap-2">
                        <input 
                          type="number" 
                          placeholder="0.00" 
                          value={swapAmount}
                          onChange={(e) => setSwapAmount(e.target.value)}
                          className="flex-1 p-2 rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-800"
                        />
                        <button 
                          onClick={() => openTokenModal('in')}
                          className="w-32 p-2 rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-800 flex items-center justify-between"
                        >
                          <span>{tokenIn.symbol}</span>
                          <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                          </svg>
                        </button>
                      </div>
                  </div>
                  <div className="flex justify-center">
                      <svg className="w-6 h-6 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 14l-7 7m0 0l-7-7m7 7V3" />
                      </svg>
                  </div>
                  <div>
                      <label className="block text-sm font-medium mb-1">Receive Token</label>
                      <button 
                          onClick={() => openTokenModal('out')}
                          className="w-full p-2 rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-800 flex items-center justify-between"
                      >
                          <span>{tokenOut.symbol}</span>
                          <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                          </svg>
                      </button>
                  </div>
                </div>
              </div>
            )}
          </div>

          <div className="p-6 border-t border-gray-200 dark:border-gray-800 flex justify-between">
            <button
              onClick={() => setStep(Math.max(1, step - 1))}
              disabled={step === 1 || isPending || isConfirming}
              className={`px-6 py-2 rounded-lg font-medium ${
                step === 1 
                ? 'text-gray-400 cursor-not-allowed' 
                : 'text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-800'
              }`}
            >
              Back
            </button>
            
            {step < 3 ? (
              <button
                onClick={() => setStep(step + 1)}
                className="bg-blue-600 hover:bg-blue-700 text-white px-6 py-2 rounded-lg font-medium transition-colors"
              >
                Continue
              </button>
            ) : (
              <button
                onClick={handleCreateFlow}
                disabled={isPending || isConfirming}
                className={`bg-green-600 hover:bg-green-700 text-white px-6 py-2 rounded-lg font-medium transition-colors flex items-center gap-2 ${
                  (isPending || isConfirming) ? 'opacity-50 cursor-not-allowed' : ''
                }`}
              >
                {(isPending || isConfirming) ? (
                  <>
                    <svg className="animate-spin h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                    Processing...
                  </>
                ) : 'Create Flow'}
              </button>
            )}
          </div>
        </div>
      </div>

      <TokenModal 
        isOpen={isTokenModalOpen} 
        onClose={() => setIsTokenModalOpen(false)} 
        onSelect={(token) => {
          if (selectingFor === 'in') setTokenIn(token);
          else setTokenOut(token);
        }}
      />
    </>
  );
}
