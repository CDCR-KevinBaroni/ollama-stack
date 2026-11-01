#!/bin/bash

echo "Testing web search with different models..."
echo "=== Testing with mistral:7b ==="

curl -s -X POST http://192.168.88.104:8080/api/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral:7b",
    "messages": [{"role": "user", "content": "What is the current price of gold today?"}],
    "web_search": true
  }' | python3 -m json.tool | head -50

