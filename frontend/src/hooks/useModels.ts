import { useState, useEffect } from 'react';

// 型定義をexportする
export interface LLMModel {
  id: string;
  name: string;
  description: string;
  size: string;
  memoryRequired: string;
  estimatedStartTime: string;
  category: 'text' | 'code' | 'chat';
  isPopular?: boolean;
}

export interface RunningInstance {
  id: string;
  modelId: string;
  modelName: string;
  status: 'starting' | 'running' | 'stopping' | 'error';
  endpoint: string;
  startedAt: Date;
  instanceType: string;
  estimatedCost: string;
}

// API関数
class OllamaAPI {
  private static baseUrl = import.meta.env.VITE_API_URL || 'http://localhost:3001/api';
  
  // 認証トークンを取得する関数（本番環境用）
  private static async getAuthToken(): Promise<string> {
    if (import.meta.env.PROD) {
      // 本番環境では実際のCognito認証トークンを取得
      // TODO: AWS Amplify Auth を使用してトークンを取得
      return 'production-token';
    }
    return 'dev-token';
  }

  // 利用可能なモデル一覧を取得
  static async getAvailableModels(): Promise<LLMModel[]> {
    try {
      // 開発環境ではモックデータを返す
      if (import.meta.env.DEV) {
        return new Promise((resolve) => {
          setTimeout(() => {
            resolve([
              {
                id: 'llama2-7b',
                name: 'Llama 2 7B',
                description: '汎用的な対話型AI。バランスの取れた性能で幅広いタスクに対応',
                size: '7B parameters',
                memoryRequired: '4GB',
                estimatedStartTime: '2-3分',
                category: 'chat',
                isPopular: true
              },
              {
                id: 'llama2-13b',
                name: 'Llama 2 13B',
                description: '高性能な対話型AI。より複雑なタスクや長い文脈の理解が可能',
                size: '13B parameters',
                memoryRequired: '8GB',
                estimatedStartTime: '3-4分',
                category: 'chat',
                isPopular: true
              },
              {
                id: 'codellama-7b',
                name: 'Code Llama 7B',
                description: 'プログラミング特化型AI。コード生成、デバッグ、説明に最適',
                size: '7B parameters',
                memoryRequired: '4GB',
                estimatedStartTime: '2-3分',
                category: 'code',
                isPopular: true
              },
              {
                id: 'codellama-13b',
                name: 'Code Llama 13B',
                description: '高性能プログラミングAI。複雑なコード生成とリファクタリング',
                size: '13B parameters',
                memoryRequired: '8GB',
                estimatedStartTime: '3-4分',
                category: 'code'
              },
              {
                id: 'mistral-7b',
                name: 'Mistral 7B',
                description: '効率的で高速な推論が可能な汎用モデル',
                size: '7B parameters',
                memoryRequired: '4GB',
                estimatedStartTime: '2-3分',
                category: 'text'
              },
              {
                id: 'mistral-7b-instruct',
                name: 'Mistral 7B Instruct',
                description: '指示に従うことに特化したMistralモデル',
                size: '7B parameters',
                memoryRequired: '4GB',
                estimatedStartTime: '2-3分',
                category: 'chat'
              }
            ]);
          }, 1000);
        });
      }

      // 本番環境での実装
      const token = await this.getAuthToken();
      const response = await fetch(`${this.baseUrl}/models`, {
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
      });
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      return await response.json();
    } catch (error) {
      console.error('Failed to fetch models:', error);
      throw error;
    }
  }

  // 実行中のインスタンス一覧を取得
  static async getRunningInstances(): Promise<RunningInstance[]> {
    try {
      if (import.meta.env.DEV) {
        return new Promise((resolve) => {
          setTimeout(() => {
            resolve([]);
          }, 500);
        });
      }

      const token = await this.getAuthToken();
      const response = await fetch(`${this.baseUrl}/instances`, {
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
      });
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      const data = await response.json();
      
      return data.map((instance: any) => ({
        ...instance,
        startedAt: new Date(instance.startedAt)
      }));
    } catch (error) {
      console.error('Failed to fetch instances:', error);
      throw error;
    }
  }

  // モデルをデプロイ
  static async deployModel(modelId: string, instanceType: string): Promise<RunningInstance> {
    try {
      if (import.meta.env.DEV) {
        return new Promise((resolve) => {
          setTimeout(() => {
            const models = [
              { id: 'llama2-7b', name: 'Llama 2 7B' },
              { id: 'llama2-13b', name: 'Llama 2 13B' },
              { id: 'codellama-7b', name: 'Code Llama 7B' },
              { id: 'codellama-13b', name: 'Code Llama 13B' },
              { id: 'mistral-7b', name: 'Mistral 7B' },
              { id: 'mistral-7b-instruct', name: 'Mistral 7B Instruct' }
            ];
            const model = models.find(m => m.id === modelId);
            
            resolve({
              id: `instance-${Date.now()}`,
              modelId,
              modelName: model?.name || 'Unknown Model',
              status: 'starting',
              endpoint: `https://ollama-${modelId}-${Date.now().toString().slice(-6)}.aws-ollama.com/api`,
              startedAt: new Date(),
              instanceType,
              estimatedCost: instanceType.includes('gpu') ? '$0.71/hour' : '$0.12/hour'
            });
          }, 500);
        });
      }

      const token = await this.getAuthToken();
      const response = await fetch(`${this.baseUrl}/instances`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ modelId, instanceType }),
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const data = await response.json();
      return {
        ...data,
        startedAt: new Date(data.startedAt)
      };
    } catch (error) {
      console.error('Failed to deploy model:', error);
      throw error;
    }
  }

  // インスタンスを停止
  static async stopInstance(instanceId: string): Promise<void> {
    try {
      if (import.meta.env.DEV) {
        return new Promise((resolve) => {
          setTimeout(() => {
            resolve();
          }, 1000);
        });
      }

      const token = await this.getAuthToken();
      const response = await fetch(`${this.baseUrl}/instances/${instanceId}`, {
        method: 'DELETE',
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
    } catch (error) {
      console.error('Failed to stop instance:', error);
      throw error;
    }
  }
}

// カスタムフック: 利用可能なモデルを管理
export const useModels = () => {
  const [models, setModels] = useState<LLMModel[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchModels = async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await OllamaAPI.getAvailableModels();
      setModels(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch models');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchModels();
  }, []);

  return { models, loading, error, refetch: fetchModels };
};

// カスタムフック: 実行中のインスタンスを管理
export const useInstances = () => {
  const [instances, setInstances] = useState<RunningInstance[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchInstances = async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await OllamaAPI.getRunningInstances();
      setInstances(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch instances');
    } finally {
      setLoading(false);
    }
  };

  const deployModel = async (modelId: string, instanceType: string) => {
    try {
      const newInstance = await OllamaAPI.deployModel(modelId, instanceType);
      setInstances(prev => [...prev, newInstance]);
      
      // 起動完了をシミュレート
      setTimeout(() => {
        setInstances(prev => 
          prev.map(inst => 
            inst.id === newInstance.id 
              ? { ...inst, status: 'running' }
              : inst
          )
        );
      }, 3000);
      
      return newInstance;
    } catch (err) {
      throw err;
    }
  };

  const stopInstance = async (instanceId: string) => {
    try {
      setInstances(prev => 
        prev.map(inst => 
          inst.id === instanceId 
            ? { ...inst, status: 'stopping' }
            : inst
        )
      );

      await OllamaAPI.stopInstance(instanceId);
      
      setTimeout(() => {
        setInstances(prev => prev.filter(inst => inst.id !== instanceId));
      }, 2000);
    } catch (err) {
      setInstances(prev => 
        prev.map(inst => 
          inst.id === instanceId 
            ? { ...inst, status: 'running' }
            : inst
        )
      );
      throw err;
    }
  };

  useEffect(() => {
    fetchInstances();
    
    // 定期的にインスタンス状態を更新
    const interval = setInterval(fetchInstances, 30000);
    
    return () => clearInterval(interval);
  }, []);

  return { 
    instances, 
    loading, 
    error, 
    refetch: fetchInstances,
    deployModel,
    stopInstance
  };
};

export { OllamaAPI };
