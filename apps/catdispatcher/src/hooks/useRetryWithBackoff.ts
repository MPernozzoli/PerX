import { useState, useCallback } from 'react';

interface RetryConfig {
  maxRetries?: number;
  initialDelay?: number;
  maxDelay?: number;
  backoffMultiplier?: number;
  onRetry?: (attempt: number, error: Error) => void;
}

interface RetryState {
  attempts: number;
  lastError: Error | null;
  isRetrying: boolean;
}

export const useRetryWithBackoff = () => {
  const [retryState, setRetryState] = useState<RetryState>({
    attempts: 0,
    lastError: null,
    isRetrying: false,
  });

  const executeWithRetry = useCallback(
    async <T>(
      fn: () => Promise<T>,
      config: RetryConfig = {}
    ): Promise<T> => {
      const {
        maxRetries = 3,
        initialDelay = 1000,
        maxDelay = 10000,
        backoffMultiplier = 2,
        onRetry,
      } = config;

      let lastError: Error | null = null;

      for (let attempt = 0; attempt <= maxRetries; attempt++) {
        try {
          setRetryState({
            attempts: attempt,
            lastError: null,
            isRetrying: attempt > 0,
          });

          const result = await fn();

          // Success - reset state
          setRetryState({
            attempts: 0,
            lastError: null,
            isRetrying: false,
          });

          return result;
        } catch (error) {
          lastError = error as Error;
          
          console.warn(`❌ Attempt ${attempt + 1}/${maxRetries + 1} failed:`, error);

          // If this was the last attempt, throw the error
          if (attempt === maxRetries) {
            setRetryState({
              attempts: attempt + 1,
              lastError: lastError,
              isRetrying: false,
            });
            throw error;
          }

          // Calculate delay with exponential backoff
          const delay = Math.min(
            initialDelay * Math.pow(backoffMultiplier, attempt),
            maxDelay
          );

          console.log(`⏳ Retrying in ${delay}ms... (attempt ${attempt + 1}/${maxRetries + 1})`);

          if (onRetry) {
            onRetry(attempt + 1, lastError);
          }

          // Wait before retrying
          await new Promise((resolve) => setTimeout(resolve, delay));
        }
      }

      // This should never be reached, but TypeScript needs it
      throw lastError || new Error('Unknown error during retry');
    },
    []
  );

  return {
    executeWithRetry,
    retryState,
  };
};

// Utility function for standalone use without hook
export const retryWithBackoff = async <T>(
  fn: () => Promise<T>,
  config: RetryConfig = {}
): Promise<T> => {
  const {
    maxRetries = 3,
    initialDelay = 1000,
    maxDelay = 10000,
    backoffMultiplier = 2,
    onRetry,
  } = config;

  let lastError: Error | null = null;

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error as Error;
      
      console.warn(`❌ Attempt ${attempt + 1}/${maxRetries + 1} failed:`, error);

      if (attempt === maxRetries) {
        throw error;
      }

      const delay = Math.min(
        initialDelay * Math.pow(backoffMultiplier, attempt),
        maxDelay
      );

      console.log(`⏳ Retrying in ${delay}ms... (attempt ${attempt + 1}/${maxRetries + 1})`);

      if (onRetry) {
        onRetry(attempt + 1, lastError);
      }

      await new Promise((resolve) => setTimeout(resolve, delay));
    }
  }

  throw lastError || new Error('Unknown error during retry');
};
