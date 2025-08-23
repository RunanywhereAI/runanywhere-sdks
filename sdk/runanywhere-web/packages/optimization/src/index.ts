// RunAnywhere Web Optimization Package
// Provides bundle optimization and analysis tools

// Bundle Analyzer exports
export { BundleAnalyzer } from './analysis/bundle-analyzer';
export type {
  BundleAnalysis,
  PackageInfo,
  ChunkInfo,
  ModuleInfo,
  Recommendation,
  BundleThresholds
} from './analysis/bundle-analyzer';

// Bundle Optimizer exports
export { BundleOptimizer } from './bundling/optimizer';
export type {
  OptimizationConfig,
  ChunkStrategy,
  TreeShakeConfig
} from './bundling/optimizer';

// Import types for use in utility functions
import type { BundleThresholds } from './analysis/bundle-analyzer';
import type { OptimizationConfig } from './bundling/optimizer';
import { BundleAnalyzer } from './analysis/bundle-analyzer';
import { BundleOptimizer } from './bundling/optimizer';

// Utility functions
export function createOptimizationPipeline(options: {
  analyze?: boolean;
  optimize?: boolean;
  thresholds?: Partial<BundleThresholds>;
  config?: Partial<OptimizationConfig>;
}) {
  const { analyze = true, optimize = true, thresholds, config } = options;

  const analyzer = analyze ? new BundleAnalyzer(thresholds) : null;
  const optimizer = optimize ? new BundleOptimizer(config) : null;

  return {
    analyzer,
    optimizer,
    async analyzeAndOptimize(bundlePaths: string[]) {
      const results: any = {};

      if (analyzer) {
        results.analysis = await analyzer.analyzeBundleFromFiles(bundlePaths);
        results.optimizationPlan = analyzer.generateOptimizationPlan(results.analysis);
      }

      if (optimizer) {
        results.viteConfig = optimizer.generateViteConfig();
        results.webpackConfig = optimizer.generateWebpackConfig();
        results.estimatedSavings = optimizer.calculateEstimatedSavings(
          results.analysis?.totalSize || 0
        );
      }

      return results;
    }
  };
}

// Pre-configured optimization presets
export const OptimizationPresets = {
  web: {
    target: 'web' as const,
    minify: true,
    compress: true,
    treeshake: true,
    splitChunks: true,
    external: ['react', 'react-dom']
  },

  worker: {
    target: 'worker' as const,
    minify: true,
    compress: true,
    treeshake: true,
    splitChunks: false,
    external: []
  },

  library: {
    target: 'web' as const,
    minify: true,
    compress: false,
    treeshake: true,
    splitChunks: false,
    external: [
      'react',
      'react-dom',
      '@runanywhere/core',
      '@runanywhere/voice',
      '@runanywhere/transcription',
      '@runanywhere/llm',
      '@runanywhere/tts'
    ]
  }
};

// Performance thresholds for different deployment scenarios
export const PerformanceThresholds = {
  strict: {
    totalSize: 512 * 1024, // 512KB
    chunkSize: 256 * 1024,  // 256KB
    packageSize: 50 * 1024, // 50KB
    duplicateThreshold: 1
  },

  moderate: {
    totalSize: 1024 * 1024, // 1MB
    chunkSize: 512 * 1024,  // 512KB
    packageSize: 100 * 1024, // 100KB
    duplicateThreshold: 2
  },

  relaxed: {
    totalSize: 2048 * 1024, // 2MB
    chunkSize: 1024 * 1024, // 1MB
    packageSize: 200 * 1024, // 200KB
    duplicateThreshold: 3
  }
};
