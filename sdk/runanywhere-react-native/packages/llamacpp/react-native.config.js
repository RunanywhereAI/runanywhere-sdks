module.exports = {
  dependency: {
    platforms: {
      android: {
        sourceDir: './android',
        packageImportPath: 'import com.margelo.nitro.runanywhere.llama.*;',
      },
      ios: {
        podspecPath: './ios/LlamaCPPBackend.podspec',
      },
    },
  },
};
