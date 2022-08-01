#!/bin/bash

# Generates Jazzy documentation: https://github.com/realm/jazzy
# This script performs without issues on CI. To generate docs locally see https://github.com/ably/ably-cocoa/issues/1438

jazzy \
  --objc \
  --clean \
  --author Ably \
  --module-version 1.2.12 \
  --umbrella-header Source/Ably.h \
  --framework-root . \
  --module Ably \
  --sdk iphonesimulator \
  --output Docs/jazzy
