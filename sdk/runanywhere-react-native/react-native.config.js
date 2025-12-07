/**
 * React Native configuration for RunAnywhere SDK
 */
module.exports = {
  dependency: {
    platforms: {
      ios: {
        podspecPath: './RunAnywhere.podspec',
      },
      android: {
        sourceDir: './android',
        packageImportPath: 'import com.runanywhere.RunAnywherePackage;',
        packageInstance: 'new RunAnywherePackage()',
      },
    },
  },
};

