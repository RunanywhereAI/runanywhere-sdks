import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  /* config options here */
  webpack: (config, { isServer }) => {
    // Completely ignore .node files
    config.module.rules.push({
      test: /\.node$/,
      loader: 'ignore-loader',
    });

    // Handle ONNX runtime properly for client/server
    if (!isServer) {
      // Client-side: use browser-compatible version
      config.resolve.alias = {
        ...config.resolve.alias,
        'onnxruntime-node': 'onnxruntime-web',
      };

      config.resolve.fallback = {
        ...config.resolve.fallback,
        fs: false,
        path: false,
        crypto: false,
        stream: false,
        buffer: false,
      };
    }

    return config;
  },
  // Suppress the workspace warning
  outputFileTracingRoot: '/Users/sanchitmonga/development/ODLM/sdks',
};

export default nextConfig;
