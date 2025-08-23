// Bundle analysis and size optimization tools
export interface BundleAnalysis {
  totalSize: number;
  gzippedSize: number;
  packages: PackageInfo[];
  chunks: ChunkInfo[];
  recommendations: Recommendation[];
  timestamp: number;
}

export interface PackageInfo {
  name: string;
  version: string;
  size: number;
  gzippedSize: number;
  dependents: string[];
  isTreeShakeable: boolean;
  duplicates?: string[];
}

export interface ChunkInfo {
  name: string;
  size: number;
  gzippedSize: number;
  modules: ModuleInfo[];
  isEntry: boolean;
  isAsync: boolean;
}

export interface ModuleInfo {
  path: string;
  size: number;
  imports: string[];
  exports: string[];
  isUsed: boolean;
}

export interface Recommendation {
  type: 'size' | 'dependency' | 'treeshaking' | 'splitting' | 'lazy-loading';
  severity: 'low' | 'medium' | 'high';
  message: string;
  estimatedSavings?: number;
  action?: string;
}

export interface BundleThresholds {
  totalSize: number; // bytes
  chunkSize: number;
  packageSize: number;
  duplicateThreshold: number;
}

export class BundleAnalyzer {
  private thresholds: BundleThresholds;

  constructor(thresholds: Partial<BundleThresholds> = {}) {
    this.thresholds = {
      totalSize: 1024 * 1024, // 1MB
      chunkSize: 500 * 1024, // 500KB
      packageSize: 100 * 1024, // 100KB
      duplicateThreshold: 2,
      ...thresholds
    };
  }

  async analyzeBundleFromStats(stats: any): Promise<BundleAnalysis> {
    const packages = this.extractPackages(stats);
    const chunks = this.extractChunks(stats);
    const totalSize = chunks.reduce((sum, chunk) => sum + chunk.size, 0);
    const gzippedSize = chunks.reduce((sum, chunk) => sum + chunk.gzippedSize, 0);

    const recommendations = this.generateRecommendations(packages, chunks, totalSize);

    return {
      totalSize,
      gzippedSize,
      packages,
      chunks,
      recommendations,
      timestamp: Date.now()
    };
  }

  async analyzeBundleFromFiles(bundlePaths: string[]): Promise<BundleAnalysis> {
    const chunks: ChunkInfo[] = [];
    let totalSize = 0;

    for (const bundlePath of bundlePaths) {
      try {
        const response = await fetch(bundlePath);
        const content = await response.text();
        const size = new Blob([content]).size;

        // Estimate gzipped size (rough approximation)
        const gzippedSize = Math.floor(size * 0.3);

        chunks.push({
          name: bundlePath.split('/').pop() || 'unknown',
          size,
          gzippedSize,
          modules: this.parseModulesFromBundle(content),
          isEntry: bundlePath.includes('index'),
          isAsync: bundlePath.includes('chunk')
        });

        totalSize += size;
      } catch (error) {
        console.warn(`Failed to analyze bundle: ${bundlePath}`, error);
      }
    }

    const packages = this.extractPackagesFromChunks(chunks);
    const gzippedSize = chunks.reduce((sum, chunk) => sum + chunk.gzippedSize, 0);
    const recommendations = this.generateRecommendations(packages, chunks, totalSize);

    return {
      totalSize,
      gzippedSize,
      packages,
      chunks,
      recommendations,
      timestamp: Date.now()
    };
  }

  private extractPackages(stats: any): PackageInfo[] {
    const packages: PackageInfo[] = [];
    const packageMap = new Map<string, PackageInfo>();

    // Extract from webpack stats or similar bundle stats
    if (stats.modules) {
      for (const module of stats.modules) {
        const packageName = this.extractPackageName(module.name);
        if (packageName) {
          const existing = packageMap.get(packageName);
          if (existing) {
            existing.size += module.size || 0;
          } else {
            packageMap.set(packageName, {
              name: packageName,
              version: 'unknown',
              size: module.size || 0,
              gzippedSize: Math.floor((module.size || 0) * 0.3),
              dependents: [],
              isTreeShakeable: this.checkTreeShakeable(module)
            });
          }
        }
      }
    }

    return Array.from(packageMap.values());
  }

  private extractChunks(stats: any): ChunkInfo[] {
    const chunks: ChunkInfo[] = [];

    if (stats.chunks) {
      for (const chunk of stats.chunks) {
        chunks.push({
          name: chunk.name || `chunk-${chunk.id}`,
          size: chunk.size || 0,
          gzippedSize: Math.floor((chunk.size || 0) * 0.3),
          modules: chunk.modules?.map((mod: any) => ({
            path: mod.name,
            size: mod.size || 0,
            imports: mod.dependencies || [],
            exports: mod.exports || [],
            isUsed: !mod.unusedExports?.length
          })) || [],
          isEntry: chunk.entry || false,
          isAsync: chunk.async || false
        });
      }
    }

    return chunks;
  }

  private extractPackagesFromChunks(chunks: ChunkInfo[]): PackageInfo[] {
    const packageMap = new Map<string, PackageInfo>();

    for (const chunk of chunks) {
      for (const module of chunk.modules) {
        const packageName = this.extractPackageName(module.path);
        if (packageName) {
          const existing = packageMap.get(packageName);
          if (existing) {
            existing.size += module.size;
          } else {
            packageMap.set(packageName, {
              name: packageName,
              version: 'unknown',
              size: module.size,
              gzippedSize: Math.floor(module.size * 0.3),
              dependents: [],
              isTreeShakeable: module.isUsed
            });
          }
        }
      }
    }

    return Array.from(packageMap.values());
  }

  private parseModulesFromBundle(content: string): ModuleInfo[] {
    // This is a simplified module extraction
    // In a real implementation, you might use a more sophisticated parser
    const modules: ModuleInfo[] = [];

    // Look for common patterns in bundled code
    const modulePatterns = [
      /\/\*\*\* (.*?) \*\*\*/g,
      /__webpack_require__\("([^"]+)"\)/g,
      /import\s+.*\s+from\s+["']([^"']+)["']/g
    ];

    let totalSize = content.length;
    let moduleCount = 0;

    for (const pattern of modulePatterns) {
      let match;
      while ((match = pattern.exec(content)) !== null) {
        const modulePath = match[1];
        if (modulePath && !modules.find(m => m.path === modulePath)) {
          modules.push({
            path: modulePath,
            size: Math.floor(totalSize / (moduleCount + 1)), // Rough estimate
            imports: [],
            exports: [],
            isUsed: true
          });
          moduleCount++;
        }
      }
    }

    return modules;
  }

  private extractPackageName(modulePath: string): string | null {
    if (!modulePath) return null;

    // Extract package name from module path
    const nodeModulesIndex = modulePath.indexOf('node_modules');
    if (nodeModulesIndex === -1) return null;

    const afterNodeModules = modulePath.substring(nodeModulesIndex + 'node_modules'.length + 1);
    const parts = afterNodeModules.split('/');

    // Handle scoped packages
    if (parts[0]?.startsWith('@')) {
      return parts.slice(0, 2).join('/');
    }

    return parts[0];
  }

  private checkTreeShakeable(module: any): boolean {
    // Check if module supports tree shaking
    return !module.providedExports?.includes('__esModule') ||
           module.usedExports?.length > 0;
  }

  private generateRecommendations(
    packages: PackageInfo[],
    chunks: ChunkInfo[],
    totalSize: number
  ): Recommendation[] {
    const recommendations: Recommendation[] = [];

    // Check total bundle size
    if (totalSize > this.thresholds.totalSize) {
      recommendations.push({
        type: 'size',
        severity: 'high',
        message: `Total bundle size (${this.formatSize(totalSize)}) exceeds threshold (${this.formatSize(this.thresholds.totalSize)})`,
        estimatedSavings: totalSize - this.thresholds.totalSize,
        action: 'Consider code splitting, lazy loading, or removing unused dependencies'
      });
    }

    // Check large packages
    for (const pkg of packages) {
      if (pkg.size > this.thresholds.packageSize) {
        recommendations.push({
          type: 'dependency',
          severity: 'medium',
          message: `Package ${pkg.name} (${this.formatSize(pkg.size)}) is large`,
          estimatedSavings: pkg.size * 0.3,
          action: `Consider alternatives or tree-shake unused exports from ${pkg.name}`
        });
      }
    }

    // Check large chunks
    for (const chunk of chunks) {
      if (chunk.size > this.thresholds.chunkSize) {
        recommendations.push({
          type: 'splitting',
          severity: 'medium',
          message: `Chunk ${chunk.name} (${this.formatSize(chunk.size)}) is large`,
          action: 'Consider splitting this chunk further'
        });
      }
    }

    // Check for duplicates
    const packageNames = packages.map(p => p.name);
    const duplicates = packageNames.filter((name, index) => packageNames.indexOf(name) !== index);

    if (duplicates.length > 0) {
      recommendations.push({
        type: 'dependency',
        severity: 'high',
        message: `Found duplicate packages: ${duplicates.join(', ')}`,
        action: 'Use dependency deduplication or version alignment'
      });
    }

    // Check for tree-shaking opportunities
    const nonTreeShakeablePackages = packages.filter(p => !p.isTreeShakeable);
    if (nonTreeShakeablePackages.length > 0) {
      recommendations.push({
        type: 'treeshaking',
        severity: 'medium',
        message: `${nonTreeShakeablePackages.length} packages don't support tree-shaking`,
        action: 'Consider switching to ES modules versions or alternative packages'
      });
    }

    return recommendations;
  }

  private formatSize(bytes: number): string {
    const units = ['B', 'KB', 'MB', 'GB'];
    let size = bytes;
    let unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    return `${size.toFixed(2)} ${units[unitIndex]}`;
  }

  generateOptimizationPlan(analysis: BundleAnalysis): {
    immediate: Recommendation[];
    longTerm: Recommendation[];
    estimatedSavings: number;
  } {
    const immediate = analysis.recommendations
      .filter(r => r.severity === 'high')
      .slice(0, 5);

    const longTerm = analysis.recommendations
      .filter(r => r.severity === 'medium' || r.severity === 'low');

    const estimatedSavings = analysis.recommendations
      .reduce((sum, r) => sum + (r.estimatedSavings || 0), 0);

    return {
      immediate,
      longTerm,
      estimatedSavings
    };
  }
}
