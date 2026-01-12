module.exports = {
  dependency: {
    platforms: {
      android: {
        sourceDir: './android',
        packageImportPath: 'import com.margelo.nitro.runanywhere.llama.RunAnywhereLlamaPackage;',
        packageInstance: 'new RunAnywhereLlamaPackage()',
      },
      ios: {
        podspecPath: './RunAnywhereLlama.podspec',
      },
    },
  },
};
