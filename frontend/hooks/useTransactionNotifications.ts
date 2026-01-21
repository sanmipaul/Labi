'use client';

import { useCallback } from 'react';
import { useNotification } from '@/contexts/NotificationContext';
import { Hash, TransactionReceipt } from 'viem';

export const useTransactionNotifications = () => {
  const { notify, updateNotification } = useNotification();

  const handleTransaction = useCallback(
    async (
      txPromise: Promise<{ hash: Hash }>,
      {
        pending = 'Processing transaction...',
        success = 'Transaction successful!',
        error = 'Transaction failed',
        successCallback,
        errorCallback,
      }: {
        pending?: string;
        success?: string;
        error?: string;
        successCallback?: (result: { hash: Hash; receipt?: TransactionReceipt }) => void;
        errorCallback?: (error: Error) => void;
      } = {}
    ) => {
      const toastId = notify(pending, 'loading');

      try {
        const result = await txPromise;
        updateNotification(toastId, success, 'success');
        successCallback?.(result);
        return result;
      } catch (err: unknown) {
        console.error('Transaction error:', err);
        const errorMessage = err instanceof Error ? err.message : error;
        updateNotification(toastId, errorMessage, 'error');
        if (err instanceof Error) {
          errorCallback?.(err);
        }
        throw err;
      }
    },
    [notify, updateNotification]
  );

  return { handleTransaction };
};
