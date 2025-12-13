import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  /* config options here */
  webpack: (config, { isServer }) => {
    // Completely ignore .node files
    config.module.rules.push({
      test: /\.node$/,
      loader: 'ignore-loader',
    });

    // Handle modules that shouldn't be bundled
    config.resolve.alias = {
      ...config.resolve.alias,
      'sharp$': false,
      'sharp': false,
    };

    // Handle ONNX runtime properly for client/server
    if (!isServer) {
      // Client-side: use browser-compatible version
      config.resolve.alias = {
        ...config.resolve.alias,
        'onnxruntime-node': 'onnxruntime-web',
        'sharp$': false,
        'sharp': false,
      };

      config.resolve.fallback = {
        ...config.resolve.fallback,
        fs: false,
        path: false,
        crypto: false,
        stream: false,
        buffer: false,
        child_process: false,
      };
    }

    // Ignore certain packages for SSR
    config.externals = [...(config.externals || [])];
    config.externals.push('sharp');

    return config;
  },
  // Suppress the workspace warning
  outputFileTracingRoot: '/Users/sanchitmonga/development/ODLM/sdks',

  // Disable SSR for pages that use heavy client-side libraries
  experimental: {
    optimizeCss: false,
  },
};

export default nextConfig;
