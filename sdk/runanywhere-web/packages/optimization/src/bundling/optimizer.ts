// Bundle optimization strategies and implementations
export interface OptimizationConfig {
  target: 'web' | 'node' | 'worker';
  minify: boolean;
  compress: boolean;
  treeshake: boolean;
  splitChunks: boolean;
  lazyLoad: string[];
  exclude: string[];
  external: string[];
}

export interface ChunkStrategy {
  name: string;
  test: RegExp | ((module: string) => boolean);
  priority: number;
  enforce?: 'entry' | 'async';
  maxSize?: number;
  minSize?: number;
}

export interface TreeShakeConfig {
  sideEffects: false | string[];
  usedExports: boolean;
  providedExports: boolean;
  innerGraph: boolean;
}

export class BundleOptimizer {
  private config: OptimizationConfig;

  constructor(config: Partial<OptimizationConfig> = {}) {
    this.config = {
      target: 'web',
      minify: true,
      compress: true,
      treeshake: true,
      splitChunks: true,
      lazyLoad: [],
      exclude: [],
      external: ['react', 'react-dom'],
      ...config
    };
  }

  generateViteConfig(): any {
    const config: any = {
      build: {
        target: 'es2022',
        outDir: 'dist',
        sourcemap: true,
        emptyOutDir: true,
        rollupOptions: {
          external: this.config.external,
          output: {
            manualChunks: this.generateChunkStrategy(),
            chunkFileNames: (chunkInfo: any) => {
              // Optimize chunk naming for caching
              const facadeModuleId = chunkInfo.facadeModuleId;
              if (facadeModuleId?.includes('node_modules')) {
                return 'vendor/[name]-[hash].js';
              }
              return 'chunks/[name]-[hash].js';
            },
            assetFileNames: (assetInfo: any) => {
              // Optimize asset naming
              const name = assetInfo.name || 'asset';
              if (name.endsWith('.css')) {
                return 'styles/[name]-[hash][extname]';
              }
              return 'assets/[name]-[hash][extname]';
            }
          }
        }
      },
      define: {
        'process.env.NODE_ENV': JSON.stringify('production')
      }
    };

    if (this.config.minify) {
      config.build.minify = 'terser';
      config.build.terserOptions = this.getTerserConfig();
    }

    if (this.config.compress) {
      config.build.compress = true;
    }

    return config;
  }

  generateWebpackConfig(): any {
    const config: any = {
      mode: 'production',
      target: this.config.target,
      optimization: {
        minimize: this.config.minify,
        sideEffects: false,
        usedExports: this.config.treeshake,
        providedExports: this.config.treeshake,
        innerGraph: this.config.treeshake,
        splitChunks: this.config.splitChunks ? {
          chunks: 'all',
          cacheGroups: this.generateWebpackChunkStrategy()
        } : false
      },
      externals: this.config.external.reduce((acc, ext) => {
        acc[ext] = ext;
        return acc;
      }, {} as Record<string, string>),
      resolve: {
        alias: this.generateAliases()
      }
    };

    if (this.config.minify) {
      const TerserPlugin = require('terser-webpack-plugin');
      config.optimization.minimizer = [new TerserPlugin(this.getTerserConfig())];
    }

    return config;
  }

  private generateChunkStrategy(): Record<string, string[]> | ((id: string) => string | undefined) {
    return (id: string): string | undefined => {
      // Vendor chunks
      if (id.includes('node_modules')) {
        // Split large libraries into their own chunks
        if (id.includes('@xenova/transformers')) {
          return 'transformers';
        }
        if (id.includes('@ricky0123/vad-web')) {
          return 'vad';
        }
        if (id.includes('onnxruntime-web')) {
          return 'onnx';
        }
        if (id.includes('react') || id.includes('react-dom')) {
          return 'react-vendor';
        }
        return 'vendor';
      }

      // RunAnywhere packages
      if (id.includes('@runanywhere/')) {
        if (id.includes('@runanywhere/workers')) {
          return 'workers';
        }
        if (id.includes('@runanywhere/cache')) {
          return 'cache';
        }
        if (id.includes('@runanywhere/monitoring')) {
          return 'monitoring';
        }
        return 'runanywhere';
      }

      // Keep small modules together
      return undefined;
    };
  }

  private generateWebpackChunkStrategy(): Record<string, any> {
    return {
      vendor: {
        test: /[\\/]node_modules[\\/]/,
        name: 'vendor',
        chunks: 'all',
        priority: 10
      },
      transformers: {
        test: /[\\/]node_modules[\\/]@xenova[\\/]transformers/,
        name: 'transformers',
        chunks: 'all',
        priority: 20
      },
      vad: {
        test: /[\\/]node_modules[\\/]@ricky0123[\\/]vad-web/,
        name: 'vad',
        chunks: 'all',
        priority: 20
      },
      onnx: {
        test: /[\\/]node_modules[\\/]onnxruntime-web/,
        name: 'onnx',
        chunks: 'all',
        priority: 20
      },
      runanywhere: {
        test: /[\\/]node_modules[\\/]@runanywhere[\\/]/,
        name: 'runanywhere',
        chunks: 'all',
        priority: 15
      },
      workers: {
        test: /\.worker\.(js|ts)$/,
        name: 'workers',
        chunks: 'async',
        priority: 25
      }
    };
  }

  private getTerserConfig(): any {
    return {
      compress: {
        drop_console: true,
        drop_debugger: true,
        pure_funcs: ['console.log', 'console.info', 'console.debug'],
        passes: 2
      },
      mangle: {
        safari10: true
      },
      format: {
        comments: false,
        safari10: true
      }
    };
  }

  private generateAliases(): Record<string, string> {
    // Create aliases for smaller builds
    return {
      // Use lighter alternatives when possible
      'eventemitter3': 'events', // Use built-in events if available
    };
  }

  generateLazyLoadingConfig(): {
    imports: Record<string, string>;
    routes: string[];
  } {
    const imports: Record<string, string> = {};
    const routes: string[] = [];

    // Generate dynamic imports for specified modules
    for (const module of this.config.lazyLoad) {
      const importPath = module.replace('@runanywhere/', '');
      imports[module] = `() => import('${module}')`;

      // If it's a component or route, add to lazy routes
      if (module.includes('component') || module.includes('page')) {
        routes.push(module);
      }
    }

    return { imports, routes };
  }

  optimizeForProduction(): OptimizationConfig {
    return {
      ...this.config,
      minify: true,
      compress: true,
      treeshake: true,
      splitChunks: true,
      lazyLoad: [
        '@runanywhere/workers',
        '@runanywhere/monitoring',
        '@runanywhere/cache'
      ]
    };
  }

  optimizeForDevelopment(): OptimizationConfig {
    return {
      ...this.config,
      minify: false,
      compress: false,
      treeshake: false,
      splitChunks: false,
      lazyLoad: []
    };
  }

  calculateEstimatedSavings(baseSize: number): {
    minification: number;
    compression: number;
    treeShaking: number;
    chunkSplitting: number;
    total: number;
  } {
    const savings = {
      minification: this.config.minify ? baseSize * 0.15 : 0, // ~15% savings
      compression: this.config.compress ? baseSize * 0.30 : 0, // ~30% with gzip
      treeShaking: this.config.treeshake ? baseSize * 0.20 : 0, // ~20% unused code
      chunkSplitting: this.config.splitChunks ? baseSize * 0.10 : 0, // ~10% better caching
      total: 0
    };

    // Account for overlapping optimizations (not additive)
    savings.total = baseSize * (1 - (
      (1 - (savings.minification / baseSize)) *
      (1 - (savings.compression / baseSize)) *
      (1 - (savings.treeShaking / baseSize)) *
      (1 - (savings.chunkSplitting / baseSize))
    ));

    return savings;
  }
}
