import { useState } from 'react';
import {
  Box,
  Card,
  CardContent,
  TextField,
  Button,
  Typography,
  Alert,
  Link,
  CircularProgress,
  Divider
} from '@mui/material';
import { Login as LoginIcon, PersonAdd as SignUpIcon } from '@mui/icons-material';
import { useAuth } from '../../contexts/AuthContext';

interface LoginFormProps {
  onSwitchToSignUp: () => void;
  onSwitchToForgotPassword: () => void;
}

export const LoginForm = ({ onSwitchToSignUp, onSwitchToForgotPassword }: LoginFormProps) => {
  const { signIn } = useAuth();
  const [formData, setFormData] = useState({
    username: '',
    password: ''
  });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setFormData({
      ...formData,
      [e.target.name]: e.target.value
    });
    setError(''); // エラーをクリア
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!formData.username || !formData.password) {
      setError('ユーザー名とパスワードを入力してください');
      return;
    }

    setLoading(true);
    setError('');

    try {
      const result = await signIn(formData.username, formData.password);
      
      if (!result.success) {
        setError(result.message);
      }
      // 成功時は AuthContext が自動的に状態を更新
    } catch (error) {
      setError('ログインに失敗しました。もう一度お試しください。');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Box
      sx={{
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
        padding: 2
      }}
    >
      <Card
        sx={{
          maxWidth: 400,
          width: '100%',
          boxShadow: '0 8px 32px rgba(0,0,0,0.1)'
        }}
      >
        <CardContent sx={{ p: 4 }}>
          {/* ヘッダー */}
          <Box sx={{ textAlign: 'center', mb: 3 }}>
            <LoginIcon sx={{ fontSize: 48, color: 'primary.main', mb: 1 }} />
            <Typography variant="h4" component="h1" gutterBottom>
              ログイン
            </Typography>
            <Typography variant="body2" color="text.secondary">
              AWS Ollama LLM Platform
            </Typography>
          </Box>

          {/* エラー表示 */}
          {error && (
            <Alert severity="error" sx={{ mb: 2 }}>
              {error}
            </Alert>
          )}

          {/* ログインフォーム */}
          <Box component="form" onSubmit={handleSubmit}>
            <TextField
              fullWidth
              label="ユーザー名またはメールアドレス"
              name="username"
              type="text"
              value={formData.username}
              onChange={handleChange}
              margin="normal"
              required
              disabled={loading}
              autoComplete="username"
            />

            <TextField
              fullWidth
              label="パスワード"
              name="password"
              type="password"
              value={formData.password}
              onChange={handleChange}
              margin="normal"
              required
              disabled={loading}
              autoComplete="current-password"
            />

            <Button
              type="submit"
              fullWidth
              variant="contained"
              size="large"
              disabled={loading}
              startIcon={loading ? <CircularProgress size={20} /> : <LoginIcon />}
              sx={{ mt: 3, mb: 2 }}
            >
              {loading ? 'ログイン中...' : 'ログイン'}
            </Button>
          </Box>

          <Divider sx={{ my: 2 }} />

          {/* リンク */}
          <Box sx={{ textAlign: 'center' }}>
            <Link
              component="button"
              variant="body2"
              onClick={onSwitchToForgotPassword}
              sx={{ display: 'block', mb: 1 }}
            >
              パスワードを忘れた方はこちら
            </Link>
            
            <Typography variant="body2" color="text.secondary">
              アカウントをお持ちでない方は{' '}
              <Link
                component="button"
                onClick={onSwitchToSignUp}
                sx={{ fontWeight: 'bold' }}
              >
                新規登録
              </Link>
            </Typography>
          </Box>

          {/* デモ用情報 */}
          <Box sx={{ mt: 3, p: 2, bgcolor: 'grey.50', borderRadius: 1 }}>
            <Typography variant="caption" color="text.secondary" display="block">
              <strong>デモ用アカウント:</strong>
            </Typography>
            <Typography variant="caption" color="text.secondary" display="block">
              管理者にお問い合わせください
            </Typography>
          </Box>
        </CardContent>
      </Card>
    </Box>
  );
};
