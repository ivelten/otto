#!/bin/bash

# Install Claude Code if it is not already available
if command -v claude >/dev/null 2>&1; then
  echo "🤖 Claude Code already installed, skipping."
else
  echo "🤖 Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
  echo "🤖 Claude Code installation completed."
fi
