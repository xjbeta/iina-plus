#!/bin/bash

# Download iina-plugin-danmaku
wget -O 'IINA+/iina-plugin-danmaku.iinaplgz' $(curl -s https://api.github.com/repos/xjbeta/iina-plugin-danmaku/releases/latest | grep -wo "https.*.iinaplgz")


# Install webview deps
cd IINA+/WebFiles/
npm install
