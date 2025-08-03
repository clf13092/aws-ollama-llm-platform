import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { AuthService } from '../services/authService';
import type { AuthUser } from '../services/authService';

interface AuthContextType {
  user: AuthUser | null;
  loading: boolean;
  isAuthenticated: boolean;
  signIn: (username: string, password: string) => Promise<{ success: boolean; message: string }>;
  signUp: (username: string, password: string, email: string, name?: string) => Promise<{ success: boolean; message: string; needsConfirmation?: boolean }>;
  confirmSignUp: (username: string, code: string) => Promise<{ success: boolean; message: string }>;
  forgotPassword: (username: string) => Promise<{ success: boolean; message: string }>;
  confirmPassword: (username: string, code: string, newPassword: string) => Promise<{ success: boolean; message: string }>;
  signOut: () => Promise<void>;
  getAccessToken: () => Promise<string | null>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

interface AuthProviderProps {
  children: ReactNode;
}

export const AuthProvider = ({ children }: AuthProviderProps) => {
  const [user, setUser] = useState<AuthUser | null>(null);
  const [loading, setLoading] = useState(true);
  const [isAuthenticated, setIsAuthenticated] = useState(false);

  // 初期化時に認証状態をチェック
  useEffect(() => {
    checkAuthState();
  }, []);

  const checkAuthState = async () => {
    try {
      setLoading(true);
      const authenticated = await AuthService.isAuthenticated();
      
      if (authenticated) {
        const currentUser = await AuthService.getCurrentUser();
        setUser(currentUser);
        setIsAuthenticated(true);
      } else {
        setUser(null);
        setIsAuthenticated(false);
      }
    } catch (error) {
      console.error('認証状態の確認に失敗:', error);
      setUser(null);
      setIsAuthenticated(false);
    } finally {
      setLoading(false);
    }
  };

  const signIn = async (username: string, password: string) => {
    try {
      const result = await AuthService.signIn({ username, password });
      
      if (result.success && result.user) {
        setUser(result.user);
        setIsAuthenticated(true);
      }
      
      return result;
    } catch (error) {
      return {
        success: false,
        message: 'ログインに失敗しました'
      };
    }
  };

  const signUp = async (username: string, password: string, email: string, name?: string) => {
    try {
      return await AuthService.signUp({ username, password, email, name });
    } catch (error) {
      return {
        success: false,
        message: 'サインアップに失敗しました'
      };
    }
  };

  const confirmSignUp = async (username: string, code: string) => {
    try {
      return await AuthService.confirmSignUp(username, code);
    } catch (error) {
      return {
        success: false,
        message: '認証コードの確認に失敗しました'
      };
    }
  };

  const forgotPassword = async (username: string) => {
    try {
      return await AuthService.forgotPassword(username);
    } catch (error) {
      return {
        success: false,
        message: 'パスワードリセットに失敗しました'
      };
    }
  };

  const confirmPassword = async (username: string, code: string, newPassword: string) => {
    try {
      return await AuthService.confirmPassword(username, code, newPassword);
    } catch (error) {
      return {
        success: false,
        message: 'パスワード変更に失敗しました'
      };
    }
  };

  const signOut = async () => {
    try {
      await AuthService.signOut();
      setUser(null);
      setIsAuthenticated(false);
    } catch (error) {
      console.error('サインアウトに失敗:', error);
    }
  };

  const getAccessToken = async () => {
    try {
      return await AuthService.getAccessToken();
    } catch (error) {
      console.error('トークンの取得に失敗:', error);
      return null;
    }
  };

  const value = {
    user,
    loading,
    isAuthenticated,
    signIn,
    signUp,
    confirmSignUp,
    forgotPassword,
    confirmPassword,
    signOut,
    getAccessToken
  };

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};
