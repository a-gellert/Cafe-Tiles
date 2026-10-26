#!/bin/sh
# Debug wasm-web bundle into bundle/web (from the project root). Pass "release" for a release bundle.
VARIANT=${1:-debug}
DEFOLD=${DEFOLD:-C:/Defold}
JAVA=$(ls -d "$DEFOLD"/packages/jdk-*/bin/java.exe | tail -1)
JAR=$(ls "$DEFOLD"/packages/defold-*.jar | head -1)
"$JAVA" -cp "$JAR" com.dynamo.bob.Bob --root . --platform wasm-web --architectures wasm-web \
  --variant "$VARIANT" --archive --bundle-output bundle/web resolve build bundle
