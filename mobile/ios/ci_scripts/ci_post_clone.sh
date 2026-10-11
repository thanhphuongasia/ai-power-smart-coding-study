#!/bin/sh

set -e

FLUTTER_VERSION="3.44.9"
FLUTTER_SDK_PATH="$HOME/flutter"

git clone \
  --branch "$FLUTTER_VERSION" \
  --depth 1 \
  https://github.com/flutter/flutter.git \
  "$FLUTTER_SDK_PATH"

export PATH="$FLUTTER_SDK_PATH/bin:$PATH"

cd "$CI_PRIMARY_REPOSITORY_PATH/mobile"
flutter config --no-analytics
flutter precache --ios
flutter pub get
