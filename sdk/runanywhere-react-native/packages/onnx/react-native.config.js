module.exports = {
  dependency: {
    platforms: {
      android: {
        sourceDir: './android',
        packageImportPath: 'import com.margelo.nitro.runanywhere.onnx.RunAnywhereONNXPackage;',
        packageInstance: 'new RunAnywhereONNXPackage()',
      },
      ios: {
        podspecPath: './RunAnywhereONNX.podspec',
      },
    },
  },
};
