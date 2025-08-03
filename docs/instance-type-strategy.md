# インスタンスタイプ別デプロイ戦略

## 概要

Ollamaモデルのデプロイでは、モデルサイズと要求されるパフォーマンスに応じて適切なインスタンスタイプを選択する必要があります。

## インスタンスタイプ分類

### 1. CPU専用インスタンス (Fargate)
- **ml.m5.large** (2 vCPU, 8GB RAM) - 小型モデル用
- **ml.m5.xlarge** (4 vCPU, 16GB RAM) - 中型モデル用
- **ml.m5.2xlarge** (8 vCPU, 32GB RAM) - 大型モデル用

**特徴:**
- サーバーレス（インフラ管理不要）
- 自動スケーリング
- 秒単位課金
- GPU不要のモデルに最適

### 2. GPU対応インスタンス (EC2)
- **ml.g4dn.xlarge** (4 vCPU, 16GB RAM, 1x NVIDIA T4) - GPU推論用
- **ml.g4dn.2xlarge** (8 vCPU, 32GB RAM, 1x NVIDIA T4) - 高性能GPU推論
- **ml.p3.2xlarge** (8 vCPU, 61GB RAM, 1x NVIDIA V100) - 大型モデル推論

**特徴:**
- GPU加速による高速推論
- EC2インスタンス管理が必要
- 配置制約による特定インスタンスタイプ指定
- 大型モデルや高頻度利用に最適

## モデル別推奨インスタンスタイプ

| モデル | サイズ | 推奨CPU | 推奨GPU | メモリ要件 |
|--------|--------|---------|---------|------------|
| Llama2 7B | 7B | ml.m5.large | ml.g4dn.xlarge | 4GB+ |
| Llama2 13B | 13B | ml.m5.xlarge | ml.g4dn.xlarge | 8GB+ |
| CodeLlama 7B | 7B | ml.m5.large | ml.g4dn.xlarge | 4GB+ |
| CodeLlama 13B | 13B | ml.m5.xlarge | ml.g4dn.2xlarge | 8GB+ |
| Mistral 7B | 7B | ml.m5.large | ml.g4dn.xlarge | 4GB+ |

## タスク定義の動的選択

Lambda関数では以下のロジックでタスク定義を選択：

```python
def get_task_configuration(model_id, instance_type):
    # GPU instances require EC2 launch type
    if instance_type in gpu_instance_types:
        return {
            'launch_type': 'EC2',
            'task_definition': GPU_TASK_DEFINITION_ARN,
            'placement_constraints': [
                {
                    'type': 'memberOf',
                    'expression': f'attribute:ecs.instance-type == {instance_type}'
                }
            ]
        }
    
    # CPU instances use Fargate
    else:
        return {
            'launch_type': 'FARGATE',
            'task_definition': CPU_TASK_DEFINITION_ARN
        }
```

## コスト最適化

### 開発環境
- Fargate Spot (最大70%削減)
- 小型インスタンス優先
- 自動停止機能

### 本番環境
- 予約インスタンス (最大72%削減)
- 適切なサイジング
- 負荷に応じたスケーリング

## 実装上の考慮事項

### 1. 配置制約
EC2起動タイプでは、ECSクラスターに適切なインスタンスタイプが存在する必要があります。

### 2. イメージ選択
モデル固有のECRイメージを使用することで起動時間を短縮できます。

### 3. ネットワーク設定
- Fargate: awsvpc ネットワークモード必須
- EC2: bridge または awsvpc モード選択可能

### 4. リソース制限
タスク定義でCPU/メモリ制限を適切に設定し、リソース競合を防ぎます。
