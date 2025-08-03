import { useState } from 'react';
import { ThemeProvider, createTheme } from '@mui/material/styles';
import CssBaseline from '@mui/material/CssBaseline';
import { CircularProgress, Box } from '@mui/material';

import { AuthProvider, useAuth } from './contexts/AuthContext';
import { LoginForm } from './components/auth/LoginForm';
import { SignUpForm } from './components/auth/SignUpForm';
import { ConfirmSignUpForm } from './components/auth/ConfirmSignUpForm';
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
type AuthView = 'login' | 'signup' | 'confirm';

// メインアプリケーションコンポーネント
const MainApp = () => {
  const { user, loading, isAuthenticated } = useAuth();
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
          background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)'
        }}
      >
        <CircularProgress size={60} />
      </Box>
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

  switch (authView) {
    case 'signup':
      return (
        <SignUpForm
          onSwitchToLogin={handleSwitchToLogin}
          onSwitchToConfirm={handleSwitchToConfirm}
        />
      );
    
    case 'confirm':
      return (
        <ConfirmSignUpForm
          username={confirmUsername}
          onSwitchToLogin={handleSwitchToLogin}
          onSwitchToSignUp={handleSwitchToSignUp}
        />
      );
    
    default:
      return (
        <LoginForm
          onSwitchToSignUp={handleSwitchToSignUp}
          onSwitchToForgotPassword={() => {
            // TODO: パスワードリセット画面の実装
            console.log('パスワードリセット画面（未実装）');
          }}
        />
      );
  }
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
