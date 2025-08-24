import { useState } from 'react';
import {
  Box,
  Card,
  CardContent,
  TextField,
  Button,
  Typography,
  Alert,
  CircularProgress
} from '@mui/material';
import { VerifiedUser as VerifyIcon, ArrowBack as BackIcon } from '@mui/icons-material';
import { useAuth } from '../../contexts/AuthContext';

interface ConfirmSignUpFormProps {
  username: string;
  onSwitchToLogin: () => void;
  onSwitchToSignUp: () => void;
}

export const ConfirmSignUpForm = ({ username, onSwitchToLogin, onSwitchToSignUp }: ConfirmSignUpFormProps) => {
  const { confirmSignUp } = useAuth();
  const [code, setCode] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState(false);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setCode(e.target.value);
    setError(''); // エラーをクリア
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!code) {
      setError('認証コードを入力してください');
      return;
    }

    setLoading(true);
    setError('');

    try {
      const result = await confirmSignUp(username, code);
      
      if (result.success) {
        setSuccess(true);
        // 3秒後にログイン画面に自動遷移
        setTimeout(() => {
          onSwitchToLogin();
        }, 3000);
      } else {
        setError(result.message);
      }
    } catch (error) {
      setError('認証コードの確認に失敗しました。もう一度お試しください。');
    } finally {
      setLoading(false);
    }
  };

  if (success) {
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
          <CardContent sx={{ p: 4, textAlign: 'center' }}>
            <VerifyIcon sx={{ fontSize: 64, color: 'success.main', mb: 2 }} />
            <Typography variant="h5" component="h1" gutterBottom color="success.main">
              認証完了！
            </Typography>
            <Typography variant="body1" color="text.secondary" paragraph>
              メール認証が正常に完了しました。
            </Typography>
            <Typography variant="body2" color="text.secondary">
              3秒後にログイン画面に移動します...
            </Typography>
            <Button
              variant="contained"
              onClick={onSwitchToLogin}
              sx={{ mt: 2 }}
            >
              今すぐログイン画面へ
            </Button>
          </CardContent>
        </Card>
      </Box>
    );
  }

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
            <VerifyIcon sx={{ fontSize: 48, color: 'primary.main', mb: 1 }} />
            <Typography variant="h4" component="h1" gutterBottom>
              メール認証
            </Typography>
            <Typography variant="body2" color="text.secondary">
              {username} 宛に送信された認証コードを入力してください
            </Typography>
          </Box>

          {/* エラー表示 */}
          {error && (
            <Alert severity="error" sx={{ mb: 2 }}>
              {error}
            </Alert>
          )}

          {/* 認証フォーム */}
          <Box component="form" onSubmit={handleSubmit}>
            <TextField
              fullWidth
              label="認証コード"
              name="code"
              type="text"
              value={code}
              onChange={handleChange}
              margin="normal"
              required
              disabled={loading}
              placeholder="例: 123456"
              helperText="メールで送信された6桁の認証コードを入力してください"
              inputProps={{
                maxLength: 6,
                pattern: '[0-9]{6}'
              }}
            />

            <Button
              type="submit"
              fullWidth
              variant="contained"
              size="large"
              disabled={loading || !code}
              startIcon={loading ? <CircularProgress size={20} /> : <VerifyIcon />}
              sx={{ mt: 3, mb: 2 }}
            >
              {loading ? '認証中...' : '認証する'}
            </Button>
          </Box>

          {/* リンク */}
          <Box sx={{ textAlign: 'center', mt: 2 }}>
            <Typography variant="body2" color="text.secondary" paragraph>
              認証コードが届かない場合は、迷惑メールフォルダをご確認ください。
            </Typography>
            
            <Button
              variant="text"
              onClick={onSwitchToSignUp}
              sx={{ display: 'block', mb: 1 }}
            >
              別のメールアドレスで登録し直す
            </Button>
            
            <Button
              variant="text"
              onClick={onSwitchToLogin}
              startIcon={<BackIcon />}
              sx={{ display: 'inline-flex', alignItems: 'center', gap: 0.5 }}
            >
              ログイン画面に戻る
            </Button>
          </Box>
        </CardContent>
      </Card>
    </Box>
  );
};
