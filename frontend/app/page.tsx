import Link from "next/link";

export default function Home() {
  return (
    <div className="flex flex-col items-center justify-center min-h-[calc(100vh-80px)] p-8 pb-20 gap-16 sm:p-20 font-[family-name:var(--font-geist-sans)]">
      <main className="flex flex-col gap-8 items-center text-center max-w-2xl">
        <h1 className="text-5xl font-bold tracking-tight">
          Automate Your Web3 Intents with <span className="text-blue-600">Labi</span>
        </h1>
        <p className="text-xl text-gray-600 dark:text-gray-300">
          The autonomous execution protocol for Base. Create flows, set triggers, and let Labi handle the rest.
        </p>
        
        <div className="flex gap-4 items-center flex-col sm:flex-row">
          <Link
            className="rounded-full border border-solid border-transparent transition-colors flex items-center justify-center bg-blue-600 text-white gap-2 hover:bg-blue-700 text-base h-12 px-8 font-medium"
            href="/dashboard"
          >
            Launch App
          </Link>
          <a
            className="rounded-full border border-solid border-black/[.08] dark:border-white/[.145] transition-colors flex items-center justify-center hover:bg-[#f2f2f2] dark:hover:bg-[#1a1a1a] hover:border-transparent text-base h-12 px-8"
            href="https://docs.labi.protocol"
            target="_blank"
            rel="noopener noreferrer"
          >
            Read Documentation
          </a>
        </div>
      </main>
      
      <div className="grid grid-cols-1 md:grid-cols-3 gap-8 w-full max-w-5xl">
        <div className="p-6 rounded-2xl border border-gray-200 dark:border-gray-800 bg-gray-50 dark:bg-gray-900/50">
          <h3 className="text-xl font-bold mb-2">Intent Vaults</h3>
          <p className="text-gray-600 dark:text-gray-400">Secure, non-custodial vaults that execute transactions on your behalf with strict spending caps.</p>
        </div>
        <div className="p-6 rounded-2xl border border-gray-200 dark:border-gray-800 bg-gray-50 dark:bg-gray-900/50">
          <h3 className="text-xl font-bold mb-2">Flexible Triggers</h3>
          <p className="text-gray-600 dark:text-gray-400">Execute actions based on time, price movements, or on-chain events.</p>
        </div>
        <div className="p-6 rounded-2xl border border-gray-200 dark:border-gray-800 bg-gray-50 dark:bg-gray-900/50">
          <h3 className="text-xl font-bold mb-2">Automated Flows</h3>
          <p className="text-gray-600 dark:text-gray-400">Chain multiple actions together to create complex DeFi automation strategies.</p>
        </div>
      </div>
    </div>
  );
}
