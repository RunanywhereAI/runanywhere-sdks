// Diffusion is iOS-only (CoreML). Android is not supported; no native module there.
module.exports = {
  dependency: {
    platforms: {
      ios: {
        podspecPath: './RunAnywhereDiffusion.podspec',
      },
    },
  },
};
