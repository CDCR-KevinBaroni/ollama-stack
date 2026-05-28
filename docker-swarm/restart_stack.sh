#!/bin/bash
STACK_NAME=ollama
./stop_stack.sh
sleep 10
./start_stack.sh
