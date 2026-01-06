module.exports = {
  dependency: {
    platforms: {
      android: {
        sourceDir: './android',
        packageImportPath: 'import com.margelo.nitro.runanywhere.core.*;',
      },
      ios: {
        podspecPath: './RunAnywhereCore.podspec',
      },
    },
  },
};
