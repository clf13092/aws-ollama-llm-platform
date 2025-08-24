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
  status: 'starting' | 'running' | 'stopping' | 'error' | 'deploying';
  endpoint: string;
  startedAt: Date;
  instanceType: string;
}

// API関数
class OllamaAPI {
  private static baseUrl = import.meta.env.VITE_API_URL;
  
  private static async getAuthToken(): Promise<string | null> {
    try {
      const { AuthService } = await import('../services/authService');
      const token = await AuthService.getAccessToken();
      if (!token) throw new Error('Auth token not available');
      return token;
    } catch (error) {
      console.error('Failed to get auth token:', error);
      throw new Error('Authentication required. Please log in again.');
    }
  }

  static async getAvailableModels(): Promise<LLMModel[]> {
    const token = await this.getAuthToken();
    const response = await fetch(`${this.baseUrl}/models`, {
      headers: { 'Authorization': `Bearer ${token}` },
    });
    if (!response.ok) {
      const errorBody = await response.text();
      throw new Error(`Failed to fetch models: ${response.status} ${errorBody}`);
    }
    const data = await response.json();
    return (data.models || []).map((model: any): LLMModel => ({
      id: model.model_id,
      name: model.model_name,
      description: model.description,
      size: `${model.model_size_gb} GB`,
      memoryRequired: `${model.cpu_requirements.memory_mb / 1024} GB`,
      estimatedStartTime: '約5分',
      category: model.model_family,
      isPopular: model.is_popular || false,
    }));
  }

  private static _mapToRunningInstance(instance: any): RunningInstance {
    return {
      id: instance.instance_id,
      modelId: instance.model_name,
      modelName: instance.model_name,
      status: instance.status.toLowerCase(),
      endpoint: instance.endpoint_url,
      startedAt: new Date(instance.created_at),
      instanceType: instance.instance_type
    };
  }

  static async getRunningInstances(): Promise<RunningInstance[]> {
    const token = await this.getAuthToken();
    const response = await fetch(`${this.baseUrl}/instances`, {
      headers: { 'Authorization': `Bearer ${token}` },
    });
    if (!response.ok) throw new Error('Failed to fetch instances');
    const data = await response.json();
    return (data.instances || []).map((instance: any) => this._mapToRunningInstance(instance));
  }

  static async deployModel(modelId: string, body: object): Promise<RunningInstance> {
    const token = await this.getAuthToken();
    const response = await fetch(`${this.baseUrl}/models/deploy`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model_name: modelId, ...body }),
    });
    if (!response.ok) throw new Error('Failed to deploy model');
    const newInstanceData = await response.json();
    return this._mapToRunningInstance(newInstanceData);
  }

  static async stopInstance(instanceId: string): Promise<void> {
    const token = await this.getAuthToken();
    const response = await fetch(`${this.baseUrl}/models/stop`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ instance_id: instanceId }),
    });
    if (!response.ok) throw new Error('Failed to stop instance');
  }

  
}

export const useModels = () => {
  const [models, setModels] = useState<LLMModel[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchModels = async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await OllamaAPI.getAvailableModels();
      setModels(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'An unknown error occurred');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchModels();
  }, []);

  return { models, loading, error, refetch: fetchModels };
};

export const useInstances = () => {
  const [instances, setInstances] = useState<RunningInstance[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchInstances = async () => {
    try {
      const data = await OllamaAPI.getRunningInstances();
      setInstances(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch instances');
    } finally {
      setLoading(false);
    }
  };

  const deployModel = async (modelId: string, body: object) => {
    const newInstance = await OllamaAPI.deployModel(modelId, body);
    setInstances(prev => [...prev, newInstance]);
    return newInstance;
  };

  const stopInstance = async (instanceId: string) => {
    await OllamaAPI.stopInstance(instanceId);
    setInstances(prev => prev.filter(inst => inst.id !== instanceId));
  };

  useEffect(() => {
    fetchInstances(); // Initial fetch
    const intervalId = setInterval(fetchInstances, 5000); // Poll every 5 seconds
    return () => clearInterval(intervalId); // Cleanup on unmount
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