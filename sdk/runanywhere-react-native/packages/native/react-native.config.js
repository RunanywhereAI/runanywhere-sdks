/**
 * @runanywhere/native - React Native configuration
 *
 * This configuration enables autolinking for the native RunAnywhere module.
 */
module.exports = {
  dependency: {
    platforms: {
      android: {
        sourceDir: './android',
        packageImportPath: 'import com.margelo.nitro.runanywhere.RunanywherePackage;',
        packageInstance: 'new RunanywherePackage()',
      },
      ios: {
        podspecPath: './RunAnywhereNative.podspec',
      },
    },
  },
};
