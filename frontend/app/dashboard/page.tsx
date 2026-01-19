'use client';

import { useState } from 'react';
import { useAccount, useReadContract } from 'wagmi';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { CreateFlowModal } from '@/components/CreateFlowModal';
import { IntentRegistryABI, IntentRegistryAddress } from '@/lib/contracts';

type ExecutionHistory = {
  id: string;
  flowId: string;
  timestamp: number;
  status: 'success' | 'failed' | 'pending';
  txHash: string;
  label: string;
};

const MOCK_HISTORY: ExecutionHistory[] = [
  {
    id: '1',
    flowId: '1',
    timestamp: Date.now() - 3600000,
    status: 'success',
    txHash: '0x123...abc',
    label: 'Daily Balance Check',
  },
  {
    id: '2',
    flowId: '1',
    timestamp: Date.now() - 86400000,
    status: 'success',
    txHash: '0x456...def',
    label: 'Daily Balance Check',
  },
  {
    id: '3',
    flowId: '2',
    timestamp: Date.now() - 172800000,
    status: 'failed',
    txHash: '0x789...ghi',
    label: 'Weekly Portfolio Rebalance',
  },
];

export default function DashboardPage() {
  const { address, isConnected } = useAccount();
  const [isModalOpen, setIsModalOpen] = useState(false);

  // Fetch user flow IDs
  const { data: userFlowIds } = useReadContract({
    address: IntentRegistryAddress,
    abi: IntentRegistryABI,
    functionName: 'getUserFlows',
    args: [address as `0x${string}`],
    query: {
      enabled: !!address,
    },
  });

  if (!isConnected) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[60vh] gap-6 text-center">
        <h2 className="text-3xl font-bold">Connect Wallet to Continue</h2>
        <p className="text-gray-600 dark:text-gray-400 max-w-md">
          To manage your intent vaults and create automation flows, please connect your wallet first.
        </p>
        <ConnectButton />
      </div>
    );
  }

  return (
    <div className="container mx-auto p-6 max-w-6xl">
      <header className="flex justify-between items-center mb-8">
        <div>
          <h1 className="text-3xl font-bold">Dashboard</h1>
          <p className="text-gray-600 dark:text-gray-400 mt-2">Manage your autonomous flows and vault settings.</p>
        </div>
        <button 
          className="bg-blue-600 hover:bg-blue-700 text-white px-6 py-3 rounded-xl font-medium transition-colors shadow-lg shadow-blue-600/20"
          onClick={() => setIsModalOpen(true)}
        >
          + Create New Flow
        </button>
      </header>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Left Column: Stats & Vault Info */}
        <div className="lg:col-span-1 space-y-6">
          <div className="bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-800 rounded-2xl p-6">
            <h3 className="text-lg font-semibold mb-4 text-gray-900 dark:text-white">Vault Overview</h3>
            <div className="space-y-4">
              <div className="flex justify-between items-center p-3 bg-gray-50 dark:bg-gray-800 rounded-lg">
                <span className="text-gray-500 dark:text-gray-400">Total Flows</span>
                <span className="font-bold text-xl">{userFlowIds ? userFlowIds.length : 0}</span>
              </div>
              <div className="flex justify-between items-center p-3 bg-gray-50 dark:bg-gray-800 rounded-lg">
                <span className="text-gray-500 dark:text-gray-400">Active</span>
                <span className="font-bold text-xl text-green-500">-</span>
              </div>
              <div className="flex justify-between items-center p-3 bg-gray-50 dark:bg-gray-800 rounded-lg">
                <span className="text-gray-500 dark:text-gray-400">Executed</span>
                <span className="font-bold text-xl text-blue-500">{MOCK_HISTORY.length}</span>
              </div>
            </div>
          </div>
        </div>

        {/* Right Column: Active Flows List */}
        <div className="lg:col-span-2">
          <div className="bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-800 rounded-2xl p-6 min-h-[400px]">
            <h3 className="text-lg font-semibold mb-6 text-gray-900 dark:text-white">Your Intent Flows</h3>
            
            {userFlowIds && userFlowIds.length > 0 ? (
               <div className="space-y-4">
                 {userFlowIds.map((flowId) => (
                   <div key={flowId.toString()} className="flex items-center justify-between p-4 bg-gray-50 dark:bg-gray-800/50 rounded-xl border border-gray-200 dark:border-gray-700">
                     <div className="flex items-center gap-4">
                       <div className="w-10 h-10 rounded-full bg-blue-100 dark:bg-blue-900/30 flex items-center justify-center text-blue-600">
                         <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                           <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
                         </svg>
                       </div>
                       <div>
                         <h4 className="font-medium text-gray-900 dark:text-white">Flow #{flowId.toString()}</h4>
                         <div className="text-sm text-gray-500">Active • Daily Trigger</div>
                       </div>
                     </div>
                     <div className="flex items-center gap-2">
                       <span className="px-3 py-1 bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400 text-xs rounded-full font-medium">
                         Active
                       </span>
                     </div>
                   </div>
                 ))}
               </div>
            ) : (
              <div className="flex flex-col items-center justify-center h-[300px] text-center border-2 border-dashed border-gray-200 dark:border-gray-800 rounded-xl">
                <div className="bg-gray-100 dark:bg-gray-800 p-4 rounded-full mb-4">
                  <svg className="w-8 h-8 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
                  </svg>
                </div>
                <h4 className="text-lg font-medium text-gray-900 dark:text-white">No flows yet</h4>
                <p className="text-gray-500 dark:text-gray-400 mt-2 max-w-xs">
                  Create your first automation flow to get started with autonomous execution.
                </p>
              </div>
            )}
          </div>
        </div>
      </div>

      <div className="mt-8">
        <ExecutionHistorySection />
      </div>

      <CreateFlowModal isOpen={isModalOpen} onClose={() => setIsModalOpen(false)} />
    </div>
  );
}

function ExecutionHistorySection() {
  const timeAgo = (timestamp: number) => {
    const seconds = Math.floor((Date.now() - timestamp) / 1000);
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
    return `${Math.floor(seconds / 86400)}d ago`;
  };

  const getStatusBadge = (status: ExecutionHistory['status']) => {
    switch (status) {
      case 'success':
        return 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400';
      case 'failed':
        return 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400';
      case 'pending':
        return 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400';
      default:
        return 'bg-gray-100 text-gray-700 dark:bg-gray-900/30 dark:text-gray-400';
    }
  };

  return (
    <div className="bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-800 rounded-2xl p-6">
      <div className="flex justify-between items-center mb-6">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white">Execution History</h3>
        <button className="text-sm text-blue-500 hover:text-blue-600 font-medium transition-colors">
          View All
        </button>
      </div>
      <div className="space-y-4">
        {MOCK_HISTORY.length > 0 ? (
          MOCK_HISTORY.map((execution) => (
            <div key={execution.id} className="flex items-center justify-between p-4 bg-gray-50 dark:bg-gray-800/50 rounded-xl border border-gray-100 dark:border-gray-800 transition-all hover:bg-gray-100 dark:hover:bg-gray-800">
              <div className="flex items-center gap-4">
                <div className={`w-10 h-10 rounded-full flex items-center justify-center ${
                  execution.status === 'success' ? 'bg-green-100 text-green-600 dark:bg-green-900/20' : 
                  execution.status === 'failed' ? 'bg-red-100 text-red-600 dark:bg-red-900/20' : 
                  'bg-yellow-100 text-yellow-600 dark:bg-yellow-900/20'
                }`}>
                  {execution.status === 'success' ? (
                    <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                    </svg>
                  ) : execution.status === 'failed' ? (
                    <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                    </svg>
                  ) : (
                    <svg className="w-5 h-5 animate-spin" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                    </svg>
                  )}
                </div>
                <div className="text-left">
                  <h4 className="font-medium text-gray-900 dark:text-white">{execution.label}</h4>
                  <div className="text-xs text-gray-500">Flow #{execution.flowId}</div>
                </div>
              </div>
              <div className="flex items-center gap-6">
                <div className="text-right flex flex-col items-end gap-1">
                  <a 
                    href={`https://etherscan.io/tx/${execution.txHash}`} 
                    target="_blank" 
                    rel="noopener noreferrer"
                    className="text-xs text-blue-500 hover:text-blue-600 font-mono flex items-center gap-1"
                  >
                    {execution.txHash}
                    <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
                    </svg>
                  </a>
                  <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold uppercase tracking-wider ${getStatusBadge(execution.status)}`}>
                    {execution.status}
                  </span>
                  <div className="text-xs text-gray-500 flex gap-2">
                    <span>{timeAgo(execution.timestamp)}</span>
                    <span className="text-gray-300 dark:text-gray-700">•</span>
                    <span>{new Date(execution.timestamp).toLocaleDateString()}</span>
                  </div>
                </div>
              </div>
            </div>
          ))
        ) : (
          <div className="text-center py-12 bg-gray-50 dark:bg-gray-800/50 rounded-xl border-2 border-dashed border-gray-200 dark:border-gray-800">
            <p className="text-gray-500 dark:text-gray-400">No execution history found.</p>
          </div>
        )}
      </div>
    </div>
  );
}
