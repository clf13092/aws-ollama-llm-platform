import { useState } from 'react';
import {
  Box,
  Card,
  CardContent,
  TextField,
  Button,
  Typography,
  Alert,
  CircularProgress,
  InputAdornment,
  IconButton
} from '@mui/material';
import { 
  Lock as LockIcon, 
  Visibility, 
  VisibilityOff,
  CheckCircle as CheckIcon
} from '@mui/icons-material';
import { useAuth } from '../../contexts/AuthContext';
import type { NewPasswordData } from '../../services/authService';

interface NewPasswordFormProps {
  onSuccess: (user: any) => void;
  onBack: () => void;
}

export const NewPasswordForm = ({ onSuccess, onBack }: NewPasswordFormProps) => {
  const { completeNewPassword } = useAuth();
  const [formData, setFormData] = useState<NewPasswordData>({
    newPassword: '',
    confirmPassword: ''
  });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setFormData({
      ...formData,
      [e.target.name]: e.target.value
    });
    setError(''); // エラーをクリア
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!formData.newPassword || !formData.confirmPassword) {
      setError('すべての項目を入力してください');
      return;
    }

    if (formData.newPassword !== formData.confirmPassword) {
      setError('パスワードが一致しません');
      return;
    }

    if (formData.newPassword.length < 8) {
      setError('パスワードは8文字以上で入力してください');
      return;
    }

    // パスワード強度チェック（AWS Cognitoの標準要件に準拠）
    const hasUpperCase = /[A-Z]/.test(formData.newPassword);
    const hasLowerCase = /[a-z]/.test(formData.newPassword);
    const hasNumbers = /\d/.test(formData.newPassword);
    const hasSpecialChar = /[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?~`]/.test(formData.newPassword);

    if (!hasUpperCase || !hasLowerCase || !hasNumbers || !hasSpecialChar) {
      setError('パスワードは大文字、小文字、数字、記号をそれぞれ1文字以上含む必要があります');
      return;
    }

    setLoading(true);
    setError('');

    try {
      const result = await completeNewPassword(formData);
      
      if (result.success) {
        setSuccess(true);
        // 2秒後に自動的にダッシュボードに遷移
        setTimeout(() => {
          onSuccess(null); // AuthContextが自動的にユーザー情報を管理
        }, 2000);
      } else {
        setError(result.message);
      }
    } catch (error) {
      setError('パスワード設定に失敗しました。もう一度お試しください。');
    } finally {
      setLoading(false);
    }
  };

  const getPasswordStrength = (password: string) => {
    let strength = 0;
    if (password.length >= 8) strength++;
    if (/[A-Z]/.test(password)) strength++;
    if (/[a-z]/.test(password)) strength++;
    if (/\d/.test(password)) strength++;
    if (/[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?~`]/.test(password)) strength++;
    return strength;
  };

  const passwordStrength = getPasswordStrength(formData.newPassword);
  const strengthColors = ['#f44336', '#ff9800', '#ffeb3b', '#8bc34a', '#4caf50'];
  const strengthLabels = ['非常に弱い', '弱い', '普通', '強い', '非常に強い'];

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
            <LockIcon sx={{ fontSize: 48, color: 'primary.main', mb: 1 }} />
            <Typography variant="h4" component="h1" gutterBottom>
              新しいパスワード設定
            </Typography>
            <Typography variant="body2" color="text.secondary">
              初回ログインのため、新しいパスワードを設定してください
            </Typography>
          </Box>

          {/* エラー・成功表示 */}
          {error && (
            <Alert severity="error" sx={{ mb: 2 }}>
              {error}
            </Alert>
          )}

          {success && (
            <Alert severity="success" sx={{ mb: 2 }}>
              <Typography variant="body2" sx={{ fontWeight: 'bold', mb: 1 }}>
                🎉 パスワード設定完了！
              </Typography>
              <Typography variant="body2">
                新しいパスワードが正常に設定されました。<br />
                自動的にログインしてダッシュボードに移動します...
              </Typography>
            </Alert>
          )}

          {/* パスワード設定フォーム */}
          <Box component="form" onSubmit={handleSubmit}>
            <TextField
              fullWidth
              label="新しいパスワード"
              name="newPassword"
              type={showPassword ? 'text' : 'password'}
              value={formData.newPassword}
              onChange={handleChange}
              margin="normal"
              required
              disabled={loading}
              InputProps={{
                endAdornment: (
                  <InputAdornment position="end">
                    <IconButton
                      onClick={() => setShowPassword(!showPassword)}
                      edge="end"
                    >
                      {showPassword ? <VisibilityOff /> : <Visibility />}
                    </IconButton>
                  </InputAdornment>
                )
              }}
            />

            {/* パスワード強度インジケーター */}
            {formData.newPassword && (
              <Box sx={{ mt: 1, mb: 2 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                  <Box
                    sx={{
                      flex: 1,
                      height: 4,
                      bgcolor: 'grey.200',
                      borderRadius: 2,
                      overflow: 'hidden'
                    }}
                  >
                    <Box
                      sx={{
                        width: `${(passwordStrength / 5) * 100}%`,
                        height: '100%',
                        bgcolor: strengthColors[passwordStrength - 1] || strengthColors[0],
                        transition: 'all 0.3s ease'
                      }}
                    />
                  </Box>
                  <Typography variant="caption" color="text.secondary">
                    {strengthLabels[passwordStrength - 1] || strengthLabels[0]}
                  </Typography>
                </Box>
              </Box>
            )}

            <TextField
              fullWidth
              label="パスワード確認"
              name="confirmPassword"
              type={showConfirmPassword ? 'text' : 'password'}
              value={formData.confirmPassword}
              onChange={handleChange}
              margin="normal"
              required
              disabled={loading}
              InputProps={{
                endAdornment: (
                  <InputAdornment position="end">
                    <IconButton
                      onClick={() => setShowConfirmPassword(!showConfirmPassword)}
                      edge="end"
                    >
                      {showConfirmPassword ? <VisibilityOff /> : <Visibility />}
                    </IconButton>
                  </InputAdornment>
                )
              }}
            />

            {/* パスワード一致確認 */}
            {formData.confirmPassword && (
              <Box sx={{ mt: 1, display: 'flex', alignItems: 'center', gap: 1 }}>
                {formData.newPassword === formData.confirmPassword ? (
                  <>
                    <CheckIcon sx={{ color: 'success.main', fontSize: 16 }} />
                    <Typography variant="caption" color="success.main">
                      パスワードが一致しています
                    </Typography>
                  </>
                ) : (
                  <Typography variant="caption" color="error.main">
                    パスワードが一致しません
                  </Typography>
                )}
              </Box>
            )}

            <Button
              type="submit"
              fullWidth
              variant="contained"
              size="large"
              disabled={loading || passwordStrength < 3 || success}
              startIcon={loading ? <CircularProgress size={20} /> : success ? <CheckIcon /> : <LockIcon />}
              sx={{ mt: 3, mb: 2 }}
            >
              {loading ? 'パスワード設定中...' : success ? '設定完了！ダッシュボードに移動中...' : 'パスワードを設定'}
            </Button>
          </Box>

          {/* 戻るボタン */}
          <Box sx={{ textAlign: 'center' }}>
            <Button
              variant="text"
              onClick={onBack}
              disabled={loading || success}
              sx={{ mt: 1 }}
            >
              ログイン画面に戻る
            </Button>
          </Box>

          {/* パスワード要件 */}
          <Box sx={{ mt: 3, p: 2, bgcolor: 'grey.50', borderRadius: 1 }}>
            <Typography variant="caption" color="text.secondary" display="block" sx={{ fontWeight: 'bold', mb: 1 }}>
              パスワード要件:
            </Typography>
            <Typography variant="caption" color="text.secondary" display="block">
              • 8文字以上
            </Typography>
            <Typography variant="caption" color="text.secondary" display="block">
              • 大文字・小文字・数字・記号を含む
            </Typography>
            <Typography variant="caption" color="text.secondary" display="block" sx={{ fontSize: '0.65rem', opacity: 0.8 }}>
              記号例: ! @ # $ % ^ &amp; * ( ) _ + - = [ ] {'{}'} ; &apos; : &quot; \ | , . &lt; &gt; / ? ~ `
            </Typography>
          </Box>
        </CardContent>
      </Card>
    </Box>
  );
};
