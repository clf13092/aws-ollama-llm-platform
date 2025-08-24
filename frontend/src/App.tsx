import { useState } from 'react';
import { ThemeProvider, createTheme } from '@mui/material/styles';
import CssBaseline from '@mui/material/CssBaseline';
import { CircularProgress, Box } from '@mui/material';

import { AuthProvider, useAuth } from './contexts/AuthContext';
import { LoginForm } from './components/auth/LoginForm';
import { SignUpForm } from './components/auth/SignUpForm';
import { ConfirmSignUpForm } from './components/auth/ConfirmSignUpForm';
import { NewPasswordForm } from './components/auth/NewPasswordForm';
import { DashboardApp } from './components/DashboardApp';

// テーマ設定
const theme = createTheme({
  palette: {
    mode: 'light',
    primary: {
      main: '#FF9900', // AWS Orange
    },
    secondary: {
      main: '#232F3E', // AWS Dark Blue
    },
    background: {
      default: '#f5f5f5',
    },
  },
});

// 認証状態の種類
type AuthView = 'login' | 'signup' | 'confirm' | 'newPassword';

// 認証画面を中央に配置するためのコンテナ
const AuthContainer = ({ children }: { children: React.ReactNode }) => (
  <Box
    sx={{
      minHeight: '100vh',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      backgroundColor: 'background.default'
    }}
  >
    {children}
  </Box>
);

// メインアプリケーションコンポーネント
const MainApp = () => {
  const { user, loading, isAuthenticated, needsNewPassword, resetNewPasswordState } = useAuth();
  const [authView, setAuthView] = useState<AuthView>('login');
  const [confirmUsername, setConfirmUsername] = useState('');

  // ローディング中
  if (loading) {
    return (
      <Box
        sx={{
          minHeight: '100vh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          background: 'linear-gradient(135deg, #f5f5f5 0%, #e0e0e0 100%)' // Changed gradient
        }}
      >
        <CircularProgress size={60} />
      </Box>
    );
  }

  // 新しいパスワード設定が必要な場合
  if (needsNewPassword) {
    return (
      <AuthContainer>
        <NewPasswordForm
          onSuccess={(user) => {
            console.log('新しいパスワードが設定されました:', user);
            resetNewPasswordState(); // 状態をリセットしてダッシュボードへ
          }}
          onBack={() => {
            resetNewPasswordState();
            setAuthView('login');
          }}
        />
      </AuthContainer>
    );
  }

  // 認証済みの場合はダッシュボードを表示
  if (isAuthenticated && user) {
    return <DashboardApp />;
  }

  // 認証画面の表示
  const handleSwitchToLogin = () => setAuthView('login');
  const handleSwitchToSignUp = () => setAuthView('signup');
  const handleSwitchToConfirm = (username: string) => {
    setConfirmUsername(username);
    setAuthView('confirm');
  };

  const authViews: { [key in AuthView]: React.ReactNode } = {
    login: (
      <LoginForm
        onSwitchToSignUp={handleSwitchToSignUp}
        onSwitchToForgotPassword={() => {
          console.log('パスワードリセット画面（未実装）');
        }}
      />
    ),
    signup: (
      <SignUpForm
        onSwitchToLogin={handleSwitchToLogin}
        onSwitchToConfirm={handleSwitchToConfirm}
      />
    ),
    confirm: (
      <ConfirmSignUpForm
        username={confirmUsername}
        onSwitchToLogin={handleSwitchToLogin}
        onSwitchToSignUp={handleSwitchToSignUp}
      />
    ),
    newPassword: null // This case is handled by the needsNewPassword flag
  };

  return <AuthContainer>{authViews[authView]}</AuthContainer>;
};

// ルートアプリケーションコンポーネント
function App() {
  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <AuthProvider>
        <MainApp />
      </AuthProvider>
    </ThemeProvider>
  );
}

export default App;
