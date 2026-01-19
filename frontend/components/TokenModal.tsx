'use client';
import { useState, useEffect } from 'react';
import { isAddress } from 'viem';

type Token = {
  symbol: string;
  name: string;
  address: string;
};

const TOKENS: Token[] = [
  { symbol: 'ETH', name: 'Ethereum', address: '0x0000000000000000000000000000000000000000' },
  { symbol: 'WETH', name: 'Wrapped Ether', address: '0x4200000000000000000000000000000000000006' },
  { symbol: 'USDC', name: 'USD Coin', address: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913' },
  { symbol: 'DAI', name: 'Dai Stablecoin', address: '0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb' },
  { symbol: 'WBTC', name: 'Wrapped Bitcoin', address: '0x03323097073E9D1F0847f93234d71B9d2a816172' },
  { symbol: 'USDT', name: 'Tether USD', address: '0xfde4C96256153296af772439a5414e863d0F4f15' },
  { symbol: 'LINK', name: 'Chainlink', address: '0xf97f4df70a175d211846e3202867cf34065d6201' },
  { symbol: 'UNI', name: 'Uniswap', address: '0x2262C56D5AD2397B5100045743D9392264653B78' },
];

const POPULAR_TOKENS = ['ETH', 'USDC', 'USDT', 'WBTC'];

export function TokenModal({ 
  isOpen, 
  onClose, 
  onSelect 
}: { 
  isOpen: boolean; 
  onClose: () => void;
  onSelect: (token: Token) => void;
}) {
  const [searchQuery, setSearchQuery] = useState('');

  useEffect(() => {
    const handleEsc = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handleEsc);
    return () => window.removeEventListener('keydown', handleEsc);
  }, [onClose]);

  const filteredTokens = TOKENS.filter((token) =>
    token.symbol.toLowerCase().includes(searchQuery.toLowerCase()) ||
    token.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
    token.address.toLowerCase() === searchQuery.toLowerCase()
  );

  const popularTokensData = TOKENS.filter((t) => POPULAR_TOKENS.includes(t.symbol));

  const isSearchAddress = isAddress(searchQuery);
  const customToken: Token | null = isSearchAddress ? {
    symbol: 'CUSTOM',
    name: 'Imported Token',
    address: searchQuery
  } : null;

  if (!isOpen) return null;

  return (
    <div 
      className="fixed inset-0 z-[60] flex items-center justify-center bg-black/50 backdrop-blur-sm p-4"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="bg-white dark:bg-gray-900 rounded-2xl w-full max-w-md overflow-hidden shadow-2xl border border-gray-200 dark:border-gray-800">
        <div className="p-4 border-b border-gray-200 dark:border-gray-800">
          <div className="flex justify-between items-center mb-4">
            <h2 className="text-lg font-bold">Select Token</h2>
            <button onClick={onClose} className="text-gray-500 hover:text-gray-700 dark:hover:text-gray-300">
              <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
          
          <div className="relative">
            <input
              type="text"
              placeholder="Search name or paste address"
              className="w-full bg-gray-100 dark:bg-gray-800 border-none rounded-xl py-3 pl-10 pr-4 focus:ring-2 focus:ring-blue-500 transition-all"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
            {searchQuery && (
              <button 
                onClick={() => setSearchQuery('')}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-200"
              >
                <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            )}
            <svg 
              className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" 
              fill="none" 
              viewBox="0 0 24 24" 
              stroke="currentColor"
            >
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
          </div>
        </div>

        <div className="p-4 border-b border-gray-100 dark:border-gray-800">
          <div className="text-xs font-semibold text-gray-500 mb-3 uppercase tracking-wider">Popular Tokens</div>
          <div className="flex flex-wrap gap-2">
            {popularTokensData.map((token) => (
              <button
                key={token.symbol}
                onClick={() => {
                  onSelect(token);
                  onClose();
                }}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-gray-200 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
              >
                <div className="w-4 h-4 rounded-full bg-blue-100 dark:bg-blue-900/30 flex items-center justify-center text-[10px] font-bold text-blue-600">
                  {token.symbol[0]}
                </div>
                <span className="text-sm font-medium">{token.symbol}</span>
              </button>
            ))}
          </div>
        </div>
        
        <div className="max-h-[60vh] overflow-y-auto">
          {customToken && !TOKENS.find(t => t.address.toLowerCase() === searchQuery.toLowerCase()) && (
            <button
              onClick={() => {
                onSelect(customToken);
                onClose();
              }}
              className="w-full flex items-center justify-between p-4 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors border-b border-gray-100 dark:border-gray-800"
            >
              <div className="flex items-center gap-3">
                <div className="w-8 h-8 rounded-full bg-orange-100 dark:bg-orange-900/30 flex items-center justify-center text-xs font-bold text-orange-600">
                  ?
                </div>
                <div className="text-left">
                  <div className="font-medium text-gray-900 dark:text-white">Import Custom Token</div>
                  <div className="text-xs text-gray-500 truncate max-w-[200px]">{customToken.address}</div>
                </div>
              </div>
            </button>
          )}
          {filteredTokens.length === 0 && !customToken ? (
            <div className="p-8 text-center text-gray-500">
              No tokens found
            </div>
          ) : (
            filteredTokens.map((token) => (
              <button
                key={token.symbol}
                onClick={() => {
                  onSelect(token);
                  onClose();
                }}
                className="w-full flex items-center justify-between p-4 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors border-b border-gray-100 dark:border-gray-800 last:border-0"
              >
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-full bg-blue-100 dark:bg-blue-900/30 flex items-center justify-center text-xs font-bold text-blue-600">
                    {token.symbol[0]}
                  </div>
                  <div className="text-left">
                    <div className="font-medium text-gray-900 dark:text-white">{token.symbol}</div>
                    <div className="text-xs text-gray-500">{token.name}</div>
                  </div>
                </div>
                <div className="text-right text-xs text-gray-400 font-mono">
                  {token.address.slice(0, 6)}...{token.address.slice(-4)}
                </div>
              </button>
            ))
          )}
        </div>
      </div>
    </div>
  );
}
