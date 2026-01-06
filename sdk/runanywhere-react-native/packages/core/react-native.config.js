module.exports = {
  dependency: {
    platforms: {
      android: {
        sourceDir: './android',
        packageImportPath: 'import com.margelo.nitro.runanywhere.RunAnywhereCorePackage;',
        packageInstance: 'new RunAnywhereCorePackage()',
      },
      ios: {
        podspecPath: './RunAnywhereCore.podspec',
      },
    },
  },
};
