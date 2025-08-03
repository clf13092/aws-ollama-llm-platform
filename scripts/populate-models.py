#!/usr/bin/env python3
"""
DynamoDBにOllamaモデル情報を投入するスクリプト
"""

import boto3
import json
from datetime import datetime

def populate_models():
    # DynamoDBクライアント
    dynamodb = boto3.resource('dynamodb')
    
    # テーブル名（環境に応じて変更）
    table_name = 'production-ollama-models'
    table = dynamodb.Table(table_name)
    
    # モデル情報
    models = [
        {
            'id': 'llama2:7b',
            'name': 'Llama 2 7B',
            'description': '汎用的な対話型AI。バランスの取れた性能で幅広いタスクに対応',
            'size': '7B parameters',
            'memoryRequired': '4GB',
            'estimatedStartTime': '2-3分',
            'category': 'chat',
            'isPopular': True,
            'ollama_model_name': 'llama2:7b',
            'min_memory_gb': 4,
            'recommended_cpu': 2,
            'supports_gpu': True,
            'created_at': datetime.utcnow().isoformat(),
            'status': 'available'
        },
        {
            'id': 'llama2:13b',
            'name': 'Llama 2 13B',
            'description': '高性能な対話型AI。より複雑なタスクや長い文脈の理解が可能',
            'size': '13B parameters',
            'memoryRequired': '8GB',
            'estimatedStartTime': '3-4分',
            'category': 'chat',
            'isPopular': True,
            'ollama_model_name': 'llama2:13b',
            'min_memory_gb': 8,
            'recommended_cpu': 4,
            'supports_gpu': True,
            'created_at': datetime.utcnow().isoformat(),
            'status': 'available'
        },
        {
            'id': 'codellama:7b',
            'name': 'Code Llama 7B',
            'description': 'プログラミング特化型AI。コード生成、デバッグ、説明に最適',
            'size': '7B parameters',
            'memoryRequired': '4GB',
            'estimatedStartTime': '2-3分',
            'category': 'code',
            'isPopular': True,
            'ollama_model_name': 'codellama:7b',
            'min_memory_gb': 4,
            'recommended_cpu': 2,
            'supports_gpu': True,
            'created_at': datetime.utcnow().isoformat(),
            'status': 'available'
        },
        {
            'id': 'codellama:13b',
            'name': 'Code Llama 13B',
            'description': '高性能プログラミングAI。複雑なコード生成とリファクタリング',
            'size': '13B parameters',
            'memoryRequired': '8GB',
            'estimatedStartTime': '3-4分',
            'category': 'code',
            'isPopular': False,
            'ollama_model_name': 'codellama:13b',
            'min_memory_gb': 8,
            'recommended_cpu': 4,
            'supports_gpu': True,
            'created_at': datetime.utcnow().isoformat(),
            'status': 'available'
        },
        {
            'id': 'mistral:7b',
            'name': 'Mistral 7B',
            'description': '効率的で高速な推論が可能な汎用モデル',
            'size': '7B parameters',
            'memoryRequired': '4GB',
            'estimatedStartTime': '2-3分',
            'category': 'text',
            'isPopular': False,
            'ollama_model_name': 'mistral:7b',
            'min_memory_gb': 4,
            'recommended_cpu': 2,
            'supports_gpu': True,
            'created_at': datetime.utcnow().isoformat(),
            'status': 'available'
        },
        {
            'id': 'mistral:7b-instruct',
            'name': 'Mistral 7B Instruct',
            'description': '指示に従うことに特化したMistralモデル',
            'size': '7B parameters',
            'memoryRequired': '4GB',
            'estimatedStartTime': '2-3分',
            'category': 'chat',
            'isPopular': False,
            'ollama_model_name': 'mistral:7b-instruct',
            'min_memory_gb': 4,
            'recommended_cpu': 2,
            'supports_gpu': True,
            'created_at': datetime.utcnow().isoformat(),
            'status': 'available'
        }
    ]
    
    # モデル情報を投入
    for model in models:
        try:
            table.put_item(Item=model)
            print(f"✅ Added model: {model['name']}")
        except Exception as e:
            print(f"❌ Failed to add model {model['name']}: {str(e)}")
    
    print(f"\n🎉 Model population completed! Added {len(models)} models to {table_name}")

if __name__ == '__main__':
    populate_models()
