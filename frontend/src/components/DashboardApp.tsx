import { useState } from 'react';
import {
  Container,
  Typography,
  Card,
  CardContent,
  CardActions,
  Button,
  Chip,
  Box,
  AppBar,
  Toolbar,
  Paper,
  Alert,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  IconButton,
  Tooltip,
  Snackbar,
  CircularProgress,
  Skeleton,
  Menu,
  MenuItem,
  Avatar,
  FormControl,
  FormLabel,
  RadioGroup,
  FormControlLabel,
  Radio
} from '@mui/material';
import {
  PlayArrow,
  Stop,
  ContentCopy,
  Memory,
  Storage,
  Speed,
  CloudQueue,
  CheckCircle,
  Error as ErrorIcon,
  Refresh,
  Warning,
  AccountCircle,
  Logout
} from '@mui/icons-material';
import { useModels, useInstances, type LLMModel } from '../hooks/useModels';
import { useAuth } from '../contexts/AuthContext';

export const DashboardApp = () => {
  const { user, signOut } = useAuth();
  
  const { models, loading: modelsLoading, error: modelsError, refetch: refetchModels } = useModels();
  const {
    instances,
    loading: instancesLoading,
    error: instancesError,
    refetch: refetchInstances,
    deployModel,
    stopInstance
  } = useInstances();

  const [selectedModel, setSelectedModel] = useState<LLMModel | null>(null);
  const [deployDialogOpen, setDeployDialogOpen] = useState(false);
  const [instanceType, setInstanceType] = useState('{"cpu": 2048, "memory": 8192}');
  const [snackbarOpen, setSnackbarOpen] = useState(false);
  const [snackbarMessage, setSnackbarMessage] = useState('');
  const [deployLoading, setDeployLoading] = useState(false);
  const [userMenuAnchor, setUserMenuAnchor] = useState<null | HTMLElement>(null);
  const [compute, setCompute] = useState('fargate');

  const handleDeployModel = async (model: LLMModel) => {
    try {
      setDeployLoading(true);
      let body = {};
      if (compute === 'fargate') {
        body = { fargate_resources: JSON.parse(instanceType) };
      } else {
        body = { instance_type: instanceType };
      }
      await deployModel(model.id, body);
      setDeployDialogOpen(false);
      setSnackbarMessage(`${model.name} のデプロイを開始しました`);
      setSnackbarOpen(true);
      
      setTimeout(() => {
        refetchInstances();
      }, 1000);
    } catch (error) {
      setSnackbarMessage(`デプロイに失敗しました: ${error instanceof Error ? error.message : '不明なエラー'}`);
      setSnackbarOpen(true);
    } finally {
      setDeployLoading(false);
    }
  };

  const handleStopInstance = async (instanceId: string, modelName: string) => {
    try {
      await stopInstance(instanceId);
      setSnackbarMessage(`${modelName} を停止しました`);
      setSnackbarOpen(true);
    } catch (error) {
      setSnackbarMessage(`停止に失敗しました: ${error instanceof Error ? error.message : '不明なエラー'}`);
      setSnackbarOpen(true);
    }
  };

  const copyToClipboard = (text: string, message: string) => {
    navigator.clipboard.writeText(text);
    setSnackbarMessage(message);
    setSnackbarOpen(true);
  };

  const copyEndpoint = (endpoint: string) => {
    copyToClipboard(endpoint, 'エンドポイントURLをコピーしました');
  };

  const handleUserMenuOpen = (event: React.MouseEvent<HTMLElement>) => {
    setUserMenuAnchor(event.currentTarget);
  };

  const handleUserMenuClose = () => {
    setUserMenuAnchor(null);
  };

  const handleSignOut = async () => {
    handleUserMenuClose();
    await signOut();
  };

  const getCategoryColor = (category: string) => {
    switch (category) {
      case 'chat': return '#4CAF50';
      case 'code': return '#2196F3';
      case 'text': return '#FF9800';
      default: return '#9E9E9E';
    }
  };

  const getStatusInfo = (status: string) => {
    switch (status.toLowerCase()) {
      case 'starting':
      case 'deploying':
        return { color: '#FF9800', icon: <CloudQueue />, text: '起動中...' };
      case 'running':
        return { color: '#4CAF50', icon: <CheckCircle />, text: '実行中' };
      case 'stopping':
        return { color: '#FF5722', icon: <Refresh />, text: '停止中...' };
      case 'error':
        return { color: '#F44336', icon: <ErrorIcon />, text: 'エラー' };
      default:
        return { color: '#9E9E9E', icon: <CloudQueue />, text: status };
    }
  };

  const ModelSkeleton = () => (
    <Box sx={{ width: { xs: '100%', md: '48%', lg: '31%' }, mb: 3 }}>
      <Card elevation={2} sx={{ height: '100%' }}>
        <CardContent>
          <Skeleton variant="text" width="60%" height={32} />
          <Skeleton variant="text" width="100%" height={20} sx={{ mt: 1 }} />
          <Skeleton variant="text" width="100%" height={20} />
          <Skeleton variant="text" width="80%" height={20} />
          <Box sx={{ mt: 2 }}>
            <Skeleton variant="text" width="40%" height={20} />
            <Skeleton variant="text" width="50%" height={20} />
            <Skeleton variant="text" width="45%" height={20} />
          </Box>
        </CardContent>
        <CardActions>
          <Skeleton variant="rectangular" width={100} height={36} />
        </CardActions>
      </Card>
    </Box>
  );

  return (
    <>
      <AppBar position="static" sx={{ mb: 4 }}>
        <Toolbar>
          <Typography variant="h6" component="div" sx={{ flexGrow: 1 }}>
            🚀 AWS Ollama LLM Platform
          </Typography>
          
          <Chip 
            label={`実行中: ${instances.filter(i => i.status === 'running').length}`}
            color="secondary"
            variant="outlined"
            sx={{ mr: 2 }}
          />
          
          {instancesLoading && (
            <CircularProgress size={20} color="inherit" sx={{ mr: 2 }} />
          )}

          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <Typography variant="body2" color="inherit">
              {user?.name || user?.username}
            </Typography>
            <IconButton
              size="large"
              onClick={handleUserMenuOpen}
              color="inherit"
            >
              <Avatar sx={{ width: 32, height: 32, bgcolor: 'secondary.main' }}>
                {(user?.name || user?.username || 'U').charAt(0).toUpperCase()}
              </Avatar>
            </IconButton>
          </Box>

          <Menu
            anchorEl={userMenuAnchor}
            open={Boolean(userMenuAnchor)}
            onClose={handleUserMenuClose}
            anchorOrigin={{
              vertical: 'bottom',
              horizontal: 'right',
            }}
            transformOrigin={{
              vertical: 'top',
              horizontal: 'right',
            }}
          >
            <MenuItem onClick={handleUserMenuClose}>
              <AccountCircle sx={{ mr: 1 }} />
              プロフィール
            </MenuItem>
            <MenuItem onClick={handleSignOut}>
              <Logout sx={{ mr: 1 }} />
              ログアウト
            </MenuItem>
          </Menu>
        </Toolbar>
      </AppBar>

      <Container maxWidth="xl">
        <Alert severity="success" sx={{ mb: 3 }}>
          <Typography variant="body1">
            <strong>ようこそ、{user?.name || user?.username}さん！</strong>
          </Typography>
          <Typography variant="body2">
            AWS Ollama LLM Platformにログインしました。下記からLLMモデルをデプロイして利用を開始できます。
          </Typography>
        </Alert>

        {(modelsError || instancesError) && (
          <Alert 
            severity="error" 
            sx={{ mb: 3 }}
            action={
              <Button 
                color="inherit" 
                size="small" 
                onClick={() => {
                  refetchModels();
                  refetchInstances();
                }}
              >
                再試行
              </Button>
            }
          >
            データの取得に失敗しました: {modelsError || instancesError}
          </Alert>
        )}

        {instances.length > 0 && (
          <Box sx={{ mb: 4 }}>
            <Typography variant="h5" gutterBottom sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
              <CheckCircle color="success" />
              実行中のインスタンス
              {instancesLoading && <CircularProgress size={20} />}
            </Typography>
            <Box sx={{ 
              display: 'flex', 
              flexWrap: 'wrap', 
              gap: 3,
              justifyContent: 'flex-start'
            }}>
              {instances.map((instance) => {
                const statusInfo = getStatusInfo(instance.status);
                return (
                  <Box 
                    key={instance.id}
                    sx={{ 
                      width: { xs: '100%', md: '48%', lg: '31%' },
                      minWidth: '300px'
                    }}
                  >
                    <Card elevation={3}>
                      <CardContent>
                        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 2 }}>
                          <Typography variant="h6" component="div">
                            {instance.modelName}
                          </Typography>
                          <Chip
                            icon={statusInfo.icon}
                            label={statusInfo.text}
                            size="small"
                            sx={{ color: 'white', backgroundColor: statusInfo.color }}
                          />
                        </Box>
                        
                        <Typography variant="body2" color="text.secondary" gutterBottom>
                          インスタンスタイプ: {instance.instanceType}
                        </Typography>
                        
                        
                        
                        <Typography variant="body2" color="text.secondary" gutterBottom>
                          開始時刻: {instance.startedAt.toLocaleString()}
                        </Typography>

                        {instance.status === 'running' && (
                          <>
                            <Paper sx={{ p: 2, mt: 2, backgroundColor: '#f8f9fa' }}>
                              <Typography variant="subtitle2" gutterBottom>
                                API エンドポイント:
                              </Typography>
                              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                                <Typography 
                                  variant="body2" 
                                  sx={{ 
                                    fontFamily: 'monospace', 
                                    fontSize: '0.8rem',
                                    wordBreak: 'break-all',
                                    flex: 1
                                  }}
                                >
                                  {instance.endpoint}
                                </Typography>
                                <Tooltip title="エンドポイントをコピー">
                                  <IconButton 
                                    size="small" 
                                    onClick={() => copyEndpoint(instance.endpoint)}
                                  >
                                    <ContentCopy fontSize="small" />
                                  </IconButton>
                                </Tooltip>
                              </Box>
                            </Paper>
                            <Paper sx={{ p: 2, mt: 1, backgroundColor: '#f8f9fa' }}>
                              <Typography variant="subtitle2" gutterBottom>
                                cURL コマンド例:
                              </Typography>
                              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                                <Typography 
                                  variant="body2" 
                                  component="pre"
                                  sx={{
                                    fontFamily: 'monospace', 
                                    fontSize: '0.8rem',
                                    wordBreak: 'break-all',
                                    flex: 1,
                                    whiteSpace: 'pre-wrap',
                                    m: 0,
                                    color: '#333'
                                  }}
                                >
                                  {`curl -X POST "${new URL('api/generate', instance.endpoint)}" \
  -H 'Content-Type: application/json' \
  -d '{"model":"${instance.modelName}","prompt":"Hello","stream":false}'`}
                                </Typography>
                                <Tooltip title="cURLコマンドをコピー">
                                  <IconButton 
                                    size="small" 
                                    onClick={() => {
                                        const apiUrl = new URL('api/generate', instance.endpoint).toString();
                                        const command = `curl -X POST "${apiUrl}" \
  -H 'Content-Type: application/json' \
  -d '{"model":"${instance.modelName}","prompt":"Hello","stream":false}'`;
                                        copyToClipboard(command, 'cURLコマンドをコピーしました');
                                    }}
                                  >
                                    <ContentCopy fontSize="small" />
                                  </IconButton>
                                </Tooltip>
                                </Box>
                            </Paper>
                          </>
                        )}
                      </CardContent>
                      
                      <CardActions>
                        <Button
                          size="small"
                          color="error"
                          startIcon={<Stop />}
                          onClick={() => handleStopInstance(instance.id, instance.modelName)}
                          disabled={instance.status === 'stopping'}
                        >
                          停止
                        </Button>
                      </CardActions>
                    </Card>
                  </Box>
                );
              })}
            </Box>
          </Box>
        )}

        <Typography variant="h5" gutterBottom sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Memory color="primary" />
          利用可能なLLMモデル
          {modelsLoading && <CircularProgress size={20} />}
        </Typography>
        
        <Box sx={{ 
          display: 'flex', 
          flexWrap: 'wrap', 
          gap: 3,
          justifyContent: 'flex-start'
        }}>
          {modelsLoading ? (
            Array.from({ length: 6 }).map((_, index) => (
              <ModelSkeleton key={index} />
            ))
          ) : models.length === 0 ? (
            <Box sx={{ width: '100%' }}>
              <Alert severity="info" sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                <Warning />
                利用可能なモデルがありません
              </Alert>
            </Box>
          ) : (
            models.map((model: LLMModel) => (
              <Box 
                key={model.id}
                sx={{ 
                  width: { xs: '100%', md: '48%', lg: '31%' },
                  minWidth: '300px'
                }}
              >
                <Card 
                  elevation={2}
                  sx={{ 
                    height: '100%',
                    display: 'flex',
                    flexDirection: 'column',
                    position: 'relative',
                    '&:hover': { elevation: 4 }
                  }}
                >
                  {model.isPopular && (
                    <Chip
                      label="人気"
                      color="secondary"
                      size="small"
                      sx={{ 
                        position: 'absolute', 
                        top: 8, 
                        right: 8, 
                        zIndex: 1 
                      }}
                    />
                  )}
                  
                  <CardContent sx={{ flexGrow: 1 }}>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 1 }}>
                      <Typography variant="h6" component="div">
                        {model.name}
                      </Typography>
                      <Chip
                        label={model.category}
                        size="small"
                        sx={{ 
                          backgroundColor: getCategoryColor(model.category),
                          color: 'white',
                          fontSize: '0.7rem'
                        }}
                      />
                    </Box>
                    
                    <Typography variant="body2" color="text.secondary" paragraph>
                      {model.description}
                    </Typography>
                    
                    <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
                      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                        <Storage fontSize="small" color="action" />
                        <Typography variant="body2">{model.size}</Typography>
                      </Box>
                      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                        <Memory fontSize="small" color="action" />
                        <Typography variant="body2">必要メモリ: {model.memoryRequired}</Typography>
                      </Box>
                      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                        <Speed fontSize="small" color="action" />
                        <Typography variant="body2">起動時間: {model.estimatedStartTime}</Typography>
                      </Box>
                    </Box>
                  </CardContent>
                  
                  <CardActions>
                    <Button
                      size="small"
                      variant="contained"
                      startIcon={<PlayArrow />}
                      onClick={() => {
                        setSelectedModel(model);
                        setDeployDialogOpen(true);
                      }}
                      disabled={instances.some(inst => inst.modelId === model.id)}
                    >
                      {instances.some(inst => inst.modelId === model.id) ? '実行中' : 'デプロイ'}
                    </Button>
                  </CardActions>
                </Card>
              </Box>
            ))
          )}
        </Box>

        <Dialog open={deployDialogOpen} onClose={() => setDeployDialogOpen(false)} maxWidth="sm" fullWidth>
          <DialogTitle>
            {selectedModel?.name} をデプロイ
          </DialogTitle>
          <DialogContent>
            <Alert severity="info" sx={{ mb: 2 }}>
              コンピューティングタイプを選択し、モデルをデプロイします。GPUを選択すると起動に時間がかかる場合があります。
            </Alert>

            <FormControl component="fieldset" sx={{ mt: 2 }}>
              <FormLabel component="legend">コンピューティングタイプ</FormLabel>
              <RadioGroup
                row
                aria-label="compute type"
                name="compute-type-group"
                value={compute}
                onChange={(e: React.ChangeEvent<HTMLInputElement>) => {
                  const newComputeType = e.target.value;
                  setCompute(newComputeType);
                  if (newComputeType === 'gpu') {
                    setInstanceType('g5.xlarge');
                  } else {
                    setInstanceType('{"cpu": 2048, "memory": 8192}');
                  }
                }}
              >
                <FormControlLabel value="fargate" control={<Radio />} label="Fargate (CPU)" />
                <FormControlLabel value="gpu" control={<Radio />} label="EC2 (GPU)" />
              </RadioGroup>
            </FormControl>
            
            <TextField
              fullWidth
              label={compute === 'fargate' ? 'vCPU / メモリ' : 'インスタンスタイプ'}
              select
              value={instanceType}
              onChange={(e) => setInstanceType(e.target.value)}
              SelectProps={{ native: true }}
              sx={{ mt: 2 }}
              helperText={compute === 'gpu' ? 'GPUインスタンスを選択してください' : 'Fargateインスタンスを選択してください'}
            >
              {compute === 'fargate' ? (
                [
                  <option key="fargate-1" value='{"cpu": 2048, "memory": 8192}'>2 vCPU / 8GB RAM</option>,
                  <option key="fargate-2" value='{"cpu": 4096, "memory": 16384}'>4 vCPU / 16GB RAM</option>,
                  <option key="fargate-3" value='{"cpu": 8192, "memory": 16384}'>8 vCPU / 16GB RAM</option>,
                  <option key="fargate-4" value='{"cpu": 8192, "memory": 32768}'>8 vCPU / 32GB RAM</option>,
                  <option key="fargate-5" value='{"cpu": 8192, "memory": 61440}'>8 vCPU / 60GB RAM</option>,
                  <option key="fargate-6" value='{"cpu": 16384, "memory": 32768}'>16 vCPU / 32GB RAM</option>,
                  <option key="fargate-7" value='{"cpu": 16384, "memory": 61440}'>16 vCPU / 60GB RAM</option>,
                  <option key="fargate-8" value='{"cpu": 16384, "memory": 92160}'>16 vCPU / 90GB RAM</option>,
                  <option key="fargate-9" value='{"cpu": 16384, "memory": 122880}'>16 vCPU / 120GB RAM</option>
                ]
              ) : (
                [
                  <option key="g5.xlarge" value="g5.xlarge">g5.xlarge (1 GPU, 16GB RAM)</option>,
                  <option key="g5.2xlarge" value="g5.2xlarge">g5.2xlarge (1 GPU, 32GB RAM)</option>,
                  <option key="g5.4xlarge" value="g5.4xlarge">g5.4xlarge (1 GPU, 64GB RAM)</option>,
                  <option key="g6.xlarge" value="g6.xlarge">g6.xlarge (1 GPU, 16GB RAM)</option>
                ]
              )}
            </TextField>
            
            {selectedModel && (
              <Box sx={{ mt: 2 }}>
                <Typography variant="subtitle2" gutterBottom>モデル情報:</Typography>
                <Typography variant="body2">• サイズ: {selectedModel.size}</Typography>
                <Typography variant="body2">• 必要メモリ: {selectedModel.memoryRequired}</Typography>
                <Typography variant="body2">• 推定起動時間: {selectedModel.estimatedStartTime}</Typography>
              </Box>
            )}
          </DialogContent>
          <DialogActions>
            <Button onClick={() => setDeployDialogOpen(false)} disabled={deployLoading}>
              キャンセル
            </Button>
            <Button 
              onClick={() => selectedModel && handleDeployModel(selectedModel)}
              variant="contained"
              startIcon={deployLoading ? <CircularProgress size={16} /> : <PlayArrow />}
              disabled={deployLoading}
            >
              {deployLoading ? 'デプロイ中...' : 'デプロイ開始'}
            </Button>
          </DialogActions>
        </Dialog>

        <Snackbar
          open={snackbarOpen}
          autoHideDuration={4000}
          onClose={() => setSnackbarOpen(false)}
          message={snackbarMessage}
        />
      </Container>
    </>
  );
};