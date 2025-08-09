#!/bin/bash

# 启动xinference服务
xinference-local -H 0.0.0.0 --log-level debug &

# 等待服务启动
sleep 60

# 加载第一个模型
xinference launch --model-name bge-large-zh-v1.5 --model-type embedding --replica 1 --download_hub modelscope --model-engine sentence_transformers --model-format pytorch --quantization none

# 加载第二个模型
xinference launch --model-name bge-reranker-large --model-type rerank --replica 1 --download_hub modelscope

# 保持容器运行
wait