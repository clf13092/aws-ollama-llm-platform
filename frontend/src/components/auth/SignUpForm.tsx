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
  CircularProgress
} from '@mui/material';
import { PersonAdd as SignUpIcon, ArrowBack as BackIcon } from '@mui/icons-material';
import { useAuth } from '../../contexts/AuthContext';

interface SignUpFormProps {
  onSwitchToLogin: () => void;
  onSwitchToConfirm: (username: string) => void;
}

export const SignUpForm = ({ onSwitchToLogin, onSwitchToConfirm }: SignUpFormProps) => {
  const { signUp } = useAuth();
  const [formData, setFormData] = useState({
    username: '',
    email: '',
    password: '',
    confirmPassword: '',
    name: ''
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

  const validateForm = () => {
    if (!formData.username || !formData.email || !formData.password) {
      setError('必須項目を入力してください');
      return false;
    }

    if (formData.password !== formData.confirmPassword) {
      setError('パスワードが一致しません');
      return false;
    }

    if (formData.password.length < 8) {
      setError('パスワードは8文字以上で入力してください');
      return false;
    }

    // パスワード強度チェック
    const passwordRegex = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]/;
    if (!passwordRegex.test(formData.password)) {
      setError('パスワードは大文字・小文字・数字・記号を含む必要があります');
      return false;
    }

    // メールアドレス形式チェック
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(formData.email)) {
      setError('正しいメールアドレスを入力してください');
      return false;
    }

    return true;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!validateForm()) {
      return;
    }

    setLoading(true);
    setError('');

    try {
      const result = await signUp(
        formData.username,
        formData.password,
        formData.email,
        formData.name || undefined
      );
      
      if (result.success) {
        if (result.needsConfirmation) {
          onSwitchToConfirm(formData.username);
        } else {
          // 自動的にログイン画面に戻る
          onSwitchToLogin();
        }
      } else {
        setError(result.message);
      }
    } catch (error) {
      setError('サインアップに失敗しました。もう一度お試しください。');
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
          maxWidth: 450,
          width: '100%',
          boxShadow: '0 8px 32px rgba(0,0,0,0.1)'
        }}
      >
        <CardContent sx={{ p: 4 }}>
          {/* ヘッダー */}
          <Box sx={{ textAlign: 'center', mb: 3 }}>
            <SignUpIcon sx={{ fontSize: 48, color: 'primary.main', mb: 1 }} />
            <Typography variant="h4" component="h1" gutterBottom>
              新規登録
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

          {/* サインアップフォーム */}
          <Box component="form" onSubmit={handleSubmit}>
            <TextField
              fullWidth
              label="ユーザー名"
              name="username"
              type="text"
              value={formData.username}
              onChange={handleChange}
              margin="normal"
              required
              disabled={loading}
              helperText="英数字とアンダースコアのみ使用可能"
            />

            <TextField
              fullWidth
              label="メールアドレス"
              name="email"
              type="email"
              value={formData.email}
              onChange={handleChange}
              margin="normal"
              required
              disabled={loading}
              helperText="認証コードの送信先になります"
            />

            <TextField
              fullWidth
              label="名前（任意）"
              name="name"
              type="text"
              value={formData.name}
              onChange={handleChange}
              margin="normal"
              disabled={loading}
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
              helperText="8文字以上、大文字・小文字・数字・記号を含む"
            />

            <TextField
              fullWidth
              label="パスワード（確認）"
              name="confirmPassword"
              type="password"
              value={formData.confirmPassword}
              onChange={handleChange}
              margin="normal"
              required
              disabled={loading}
            />

            <Button
              type="submit"
              fullWidth
              variant="contained"
              size="large"
              disabled={loading}
              startIcon={loading ? <CircularProgress size={20} /> : <SignUpIcon />}
              sx={{ mt: 3, mb: 2 }}
            >
              {loading ? '登録中...' : '新規登録'}
            </Button>
          </Box>

          {/* 戻るリンク */}
          <Box sx={{ textAlign: 'center' }}>
            <Link
              component="button"
              variant="body2"
              onClick={onSwitchToLogin}
              startIcon={<BackIcon />}
              sx={{ display: 'inline-flex', alignItems: 'center', gap: 0.5 }}
            >
              ログイン画面に戻る
            </Link>
          </Box>

          {/* 注意事項 */}
          <Box sx={{ mt: 3, p: 2, bgcolor: 'info.light', borderRadius: 1 }}>
            <Typography variant="caption" color="info.contrastText" display="block">
              <strong>ご注意:</strong>
            </Typography>
            <Typography variant="caption" color="info.contrastText" display="block">
              登録後、メールアドレスに認証コードが送信されます。
              認証を完了してからログインしてください。
            </Typography>
          </Box>
        </CardContent>
      </Card>
    </Box>
  );
};
