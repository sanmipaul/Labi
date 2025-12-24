import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { base, baseSepolia, foundry } from 'wagmi/chains';

export const config = getDefaultConfig({
  appName: 'Labi Protocol',
  projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || 'YOUR_PROJECT_ID',
  chains: [base, baseSepolia, foundry],
  ssr: true,
});
