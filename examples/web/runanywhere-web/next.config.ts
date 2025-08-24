import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  /* config options here */
  webpack: (config, { isServer }) => {
    // Handle binary node modules
    config.module.rules.push({
      test: /\.node$/,
      use: 'node-loader',
    });

    // Ignore ONNX runtime bindings in client bundle
    if (!isServer) {
      config.resolve.fallback = {
        ...config.resolve.fallback,
        fs: false,
        path: false,
        crypto: false,
      };

      // Ignore onnxruntime-node in browser builds
      config.externals = [...(config.externals || []), 'onnxruntime-node'];
    }

    return config;
  },
  // Suppress the workspace warning
  outputFileTracingRoot: '/Users/sanchitmonga/development/ODLM/sdks',
};

export default nextConfig;
