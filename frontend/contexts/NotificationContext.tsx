'use client';

import { createContext, useContext, useCallback } from 'react';
import toast, { Toaster } from 'react-hot-toast';

type NotificationType = 'success' | 'error' | 'loading' | 'info';

interface NotificationContextType {
  notify: (message: string, type?: NotificationType) => string;
  dismiss: (toastId?: string) => void;
  updateNotification: (id: string, message: string, type: NotificationType) => void;
}

const NotificationContext = createContext<NotificationContextType | undefined>(undefined);

export const NotificationProvider = ({ children }: { children: React.ReactNode }) => {
  const notify = useCallback((message: string, type: NotificationType = 'info') => {
    switch (type) {
      case 'success':
        return toast.success(message);
      case 'error':
        return toast.error(message);
      case 'loading':
        return toast.loading(message);
      default:
        return toast(message);
    }
  }, []);

  const dismiss = useCallback((toastId?: string) => {
    if (toastId) {
      toast.dismiss(toastId);
    } else {
      toast.dismiss();
    }
  }, []);

  const updateNotification = useCallback((id: string, message: string, type: NotificationType) => {
    const options = { id };
    
    switch (type) {
      case 'success':
        toast.success(message, options);
        break;
      case 'error':
        toast.error(message, options);
        break;
      case 'loading':
        toast.loading(message, options);
        break;
      default:
        toast(message, options);
    }
  }, []);

  return (
    <NotificationContext.Provider value={{ notify, dismiss, updateNotification }}>
      <Toaster
        position="top-right"
        toastOptions={{
          duration: 5000,
          style: {
            background: '#363636',
            color: '#fff',
          },
          success: {
            duration: 3000,
            iconTheme: {
              primary: '#10B981',
              secondary: 'white',
            },
          },
          error: {
            duration: 5000,
            iconTheme: {
              primary: '#EF4444',
              secondary: 'white',
            },
          },
          loading: {
            duration: 10000,
          },
        }}
      />
      {children}
    </NotificationContext.Provider>
  );
};

export const useNotification = (): NotificationContextType => {
  const context = useContext(NotificationContext);
  if (context === undefined) {
    throw new Error('useNotification must be used within a NotificationProvider');
  }
  return context;
};
